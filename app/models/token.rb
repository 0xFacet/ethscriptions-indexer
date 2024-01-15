class Token < ApplicationRecord
  has_many :token_items,
    foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :deploy_ethscription_transaction_hash,
    inverse_of: :token
    
  belongs_to :deploy_ethscription,
    foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :transaction_hash,
    class_name: 'Ethscription',
    inverse_of: :token,
    optional: true
  
  scope :minted_out, -> { where("total_supply = max_supply") }
  
  def minted_out?
    total_supply == max_supply
  end
  
  def self.create_from_token_details!(tick:, p:, max:, lim:)
    deploy_tx = find_deploy_transaction(tick: tick, p: p, max: max, lim: lim)
    
    existing = find_by(deploy_ethscription_transaction_hash: deploy_tx.transaction_hash)
    
    return existing if existing
    
    content = OpenStruct.new(JSON.parse(deploy_tx.content))
    
    create!(
      deploy_ethscription_transaction_hash: deploy_tx.transaction_hash,
      deploy_block_number: deploy_tx.block_number,
      deploy_transaction_index: deploy_tx.transaction_index,
      protocol: content.p,
      tick: content.tick,
      max_supply: content.max.to_i,
      mint_amount: content.lim.to_i,
      total_supply: 0
    )
  end
  
  def sync_token_items!
    return if minted_out?
    
    sanitized_tick = ActiveRecord::Base.sanitize_sql_like(tick)
    trailing_digit_count = max_id.to_i.to_s.length - 1

    regex = %Q{^data:,{"p":"#{protocol}","op":"mint","tick":"#{sanitized_tick}","id":"([1-9][0-9]{0,#{trailing_digit_count}})","amt":"#{mint_amount}"}$}

    sql = %Q{
      INSERT INTO token_items (ethscription_transaction_hash, deploy_ethscription_transaction_hash, token_item_id, created_at, updated_at)
      SELECT e.transaction_hash, '#{deploy_ethscription_transaction_hash}', (substring(e.content_uri from '#{regex}')::integer), NOW(), NOW()
      FROM ethscriptions e
      INNER JOIN ethscriptions d ON d.transaction_hash = '#{deploy_ethscription_transaction_hash}'
      WHERE e.content_uri ~ '#{regex}'
      AND substring(e.content_uri from '#{regex}')::integer BETWEEN 1 AND #{max_id}
      AND (e.block_number > d.block_number OR (e.block_number = d.block_number AND e.transaction_index > d.transaction_index))
      ON CONFLICT (ethscription_transaction_hash, deploy_ethscription_transaction_hash, token_item_id) DO NOTHING
    }

    Token.transaction do
      ActiveRecord::Base.connection.execute(sql)
    
      update!(total_supply: token_items.count * mint_amount)
    end
  end
  
  def max_id
    max_supply.div(mint_amount)
  end
  
  def token_items_checksum
    Rails.cache.fetch(["token-items-checksum", token_items]) do
      item_hashes = token_items.select(:ethscription_transaction_hash)
      scope = Ethscription.oldest_first.where(transaction_hash: item_hashes)
      Ethscription.scope_checksum(scope)
    end
  end
  
  def take_holders_snapshot
    with_lock do
      snapshots = {}

      last_blocks = EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(5)

      last_blocks.each do |block|
        snapshots[block.block_number] = token_balances_at_block_and_tx_index(
          block.block_number,
          1e18.to_i
        )
      end

      update!(versioned_balances: snapshots)
    end
  end
  
  def balances(block_number = nil)
    if block_number
      versioned_balances[block_number.to_s]
    else
      latest_key = versioned_balances.keys.max_by { |key| key.to_i }
      versioned_balances[latest_key]
    end
  end
  
  def balance_of(user, block_number = nil)
    balances = self.balances(block_number)
    balances[user]
  end
  
  def token_balances_at_block_and_tx_index(block_number, tx_index)
    item_hashes = token_items.select(:ethscription_transaction_hash)
    
    ownerships = EthscriptionOwnershipVersion
      .where(
        'block_number < ? OR (block_number = ? AND transaction_index <= ?)',
        block_number, block_number, tx_index)
      .where(ethscription_transaction_hash: item_hashes)
      .newest_first
      .to_a

    latest_ownerships = ownerships
      .group_by(&:ethscription_transaction_hash)
      .values
      .map(&:first)

    latest_ownerships
      .group_by(&:current_owner)
      .transform_values { |os| os.count * mint_amount }
  end
  
  def self.batch_import(tokens)
    tokens.each do |token|
      tick = token.fetch('tick')
      protocol = token.fetch('p')
      max = token.fetch('max')
      lim = token.fetch('lim')
      
      token = create_from_token_details!(tick: tick, p: protocol, max: max, lim: lim)
      
      token.sync_token_items!
    end
  end
  
  def self.batch_balance_snapshot
    all.find_each do |token|
      token.delay.take_holders_snapshot
    end
  end
  
  def self.batch_token_item_sync
    all.find_each do |token|
      token.delay.sync_token_items!
    end
  end
  
  def self.find_deploy_transaction(tick:, p:, max:, lim:)    
    uri = %<data:,{"p":"#{p}","op":"deploy","tick":"#{tick}","max":"#{max}","lim":"#{lim}"}>
    
    Ethscription.find_by_content_uri(uri)
  end
end

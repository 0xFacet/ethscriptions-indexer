class Token < ApplicationRecord
  MAX_PROTOCOL_LENGTH = MAX_TICK_LENGTH = 1000
  
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
  scope :not_minted_out, -> { where("total_supply < max_supply") }
  
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
    
    unless tick =~ /\A[[:alnum:]\p{Emoji_Presentation}]+\z/
      raise "Invalid tick format: #{tick.inspect}"
    end
    quoted_tick = ActiveRecord::Base.connection.quote_string(tick)
    
    unless protocol =~ /\A[a-z0-9\-]+\z/
      raise "Invalid protocol format: #{protocol.inspect}"
    end
    quoted_protocol = ActiveRecord::Base.connection.quote_string(protocol)
    
    trailing_digit_count = max_id.to_i.to_s.length - 1

    regex = %Q{^data:,{"p":"#{quoted_protocol}","op":"mint","tick":"#{quoted_tick}","id":"([1-9][0-9]{0,#{trailing_digit_count}})","amt":"#{mint_amount.to_i}"}$}

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
      balance_map, latest_block_number, latest_block_hash = token_balances
      
      snapshot = {
        balances: balance_map,
        as_of_block_number: latest_block_number,
        as_of_blockhash: latest_block_hash
      }
      
      update!(balances: snapshot)
    end
  end
    
  def safe_balances(max_blocks_behind = nil)
    return {} unless EthBlock.exists?(
      block_number: balances['as_of_block_number'],
      blockhash: balances['as_of_blockhash']
    )
    
    blocks_behind = EthBlock.cached_global_block_number - balances['as_of_block_number']
    
    if max_blocks_behind && blocks_behind > max_blocks_behind
      return {}
    end
    
    balances['balances']
  end
  
  def balance_of(user, max_blocks_behind = nil)
    safe_balances(max_blocks_behind)[user]
  end
  
  def token_balances
    item_hashes = token_items.select(:ethscription_transaction_hash)
    
    balances = Ethscription.where(transaction_hash: item_hashes).
      select(
        :current_owner,
        Arel.sql("SUM(#{mint_amount}) AS balance"),
        Arel.sql("(SELECT block_number FROM eth_blocks WHERE imported_at IS NOT NULL ORDER BY block_number DESC LIMIT 1) AS latest_block_number"),
        Arel.sql("(SELECT blockhash FROM eth_blocks WHERE imported_at IS NOT NULL ORDER BY block_number DESC LIMIT 1) AS latest_block_hash")
      ).
      group(:current_owner)

    balance_map = balances.each_with_object({}) do |balance, map|
      map[balance.current_owner] = balance.balance
    end

    latest_block_number = balances.first&.latest_block_number
    latest_block_hash = balances.first&.latest_block_hash

    return balance_map, latest_block_number, latest_block_hash
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
      token.take_holders_snapshot_no_duplicate_jobs
    end
  end
  
  def self.batch_token_item_sync
    not_minted_out.find_each do |token|
      token.delay.sync_token_items!
    end
  end
  
  def take_holders_snapshot_no_duplicate_jobs
    return if Delayed::Job.
    where("handler LIKE ?", "%method_name: :take_holders_snapshot%").
    where("handler ~ ?", ".*name: id\\s+value_before_type_cast: #{id}.*").exists?

    delay.take_holders_snapshot
  end
  
  def self.find_deploy_transaction(tick:, p:, max:, lim:)    
    uri = %<data:,{"p":"#{p}","op":"deploy","tick":"#{tick}","max":"#{max}","lim":"#{lim}"}>
    
    Ethscription.find_by_content_uri(uri)
  end
  
  def as_json(options = {})
    super(options.merge(except: [:balances]))
  end
  
  def self.import_test
    Token.create_from_token_details!(tick: "eths", p: "erc-20", max: 21e6.to_i, lim: 1000).sync_token_items!
    Token.create_from_token_details!(tick: "Facet", p: "erc-20", max: 21e6.to_i, lim: 1000).sync_token_items!
    Token.create_from_token_details!(tick: "gwei", p: "erc-20", max: 21e6.to_i, lim: 1000).sync_token_items!
    Token.create_from_token_details!(tick: "mfpurrs", p: "erc-20", max: 21e6.to_i, lim: 1000).sync_token_items!
    Token.create_from_token_details!(tick: "dumb", p: "erc-20", max: 21e6.to_i, lim: 1000).sync_token_items!
    Token.create_from_token_details!(tick: "nodes", p: "erc-20", max: 10000000000, lim: 10000).sync_token_items!
  end
end

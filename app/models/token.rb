class Token < ApplicationRecord
  include OrderQuery
  order_query :newest_first,
    [:deploy_block_number, :desc],
    [:deploy_transaction_index, :desc, unique: true]
  
  order_query :oldest_first,
    [:deploy_block_number, :asc],
    [:deploy_transaction_index, :asc, unique: true]
    
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
  
  has_many :token_states, foreign_key: :deploy_ethscription_transaction_hash, primary_key: :deploy_ethscription_transaction_hash, inverse_of: :token

  scope :minted_out, -> { where("total_supply = max_supply") }
  scope :not_minted_out, -> { where("total_supply < max_supply") }
  
  def self.find_by_page_key(...)
    find_by_deploy_ethscription_transaction_hash(...)
  end
  
  def page_key
    deploy_ethscription_transaction_hash
  end
  
  def minted_out?
    total_supply == max_supply
  end
  
  def self.create_from_token_details!(tick:, p:, max:, lim:)
    deploy_tx = find_deploy_transaction(tick: tick, p: p, max: max, lim: lim)
    
    existing = find_by(deploy_ethscription_transaction_hash: deploy_tx.transaction_hash)
    
    return existing if existing
    
    content = OpenStruct.new(JSON.parse(deploy_tx.content))
    
    token = nil
    
    Token.transaction do
      token = create!(
        deploy_ethscription_transaction_hash: deploy_tx.transaction_hash,
        deploy_block_number: deploy_tx.block_number,
        deploy_transaction_index: deploy_tx.transaction_index,
        protocol: content.p,
        tick: content.tick,
        max_supply: content.max.to_i,
        mint_amount: content.lim.to_i,
        total_supply: 0
      )
      
      token.sync_past_token_items!
      token.save_state_checkpoint!
    end
    
    token
  end
  
  def self.process_block(block)
    all_tokens = Token.all.to_a
    
    return unless all_tokens.present?
    
    # Find all transfers within the given block number
    transfers = EthscriptionTransfer.where(block_number: block.block_number).includes(:ethscription)

    # Group transfers by token
    transfers_by_token = transfers.group_by do |transfer|
      all_tokens.detect { |token| token.ethscription_is_token_item?(transfer.ethscription) }
    end
    
    new_token_items = []
    
    # Process each token's transfers as a batch
    transfers_by_token.each do |token, transfers|
      next unless token.present?

      # Start with the current state
      total_supply = token.total_supply.to_i
      balances = Hash.new(0).merge(token.balances.deep_dup)

      # Apply all transfers to the state
      transfers.each do |transfer|
        balances[transfer.to_address] += token.mint_amount
        
        if transfer.is_first_transfer?
          total_supply += token.mint_amount
          # Prepare token item for bulk import
          new_token_items << TokenItem.new(
            deploy_ethscription_transaction_hash: token.deploy_ethscription_transaction_hash,
            ethscription_transaction_hash: transfer.ethscription_transaction_hash,
            token_item_id: token.ethscription_is_token_item?(transfer.ethscription),
            block_number: transfer.block_number,
            transaction_index: transfer.transaction_index
          )
        else
          balances[transfer.from_address] -= token.mint_amount
        end
      end

      balances.delete_if { |address, amount| amount == 0 }
      
      # Create a single state change for the block
      token.token_states.create!(
        total_supply: total_supply,
        balances: balances,
        block_number: block.block_number,
        block_timestamp: block.timestamp,
        block_blockhash: block.blockhash,
      )
    end
    
    TokenItem.import!(new_token_items) if new_token_items.present?
  end
  
  def ethscription_is_token_item?(ethscription)
    regex = /\Adata:,\{"p":"#{Regexp.escape(protocol)}","op":"mint","tick":"#{Regexp.escape(tick)}","id":"([1-9][0-9]{0,#{trailing_digit_count}})","amt":"#{mint_amount.to_i}"\}\z/
    
    id = ethscription.content_uri[regex, 1]

    valid = id.to_i.between?(1, max_id) &&
    (ethscription.block_number > deploy_block_number ||
    (ethscription.block_number == deploy_block_number &&
    ethscription.transaction_index > deploy_transaction_index))
    
    return id.to_i if valid
  end
  
  def trailing_digit_count
    max_id.to_i.to_s.length - 1
  end
  
  def sync_past_token_items!
    return if minted_out?
    
    unless tick =~ /\A[[:alnum:]\p{Emoji_Presentation}]+\z/
      raise "Invalid tick format: #{tick.inspect}"
    end
    quoted_tick = ActiveRecord::Base.connection.quote_string(tick)
    
    unless protocol =~ /\A[a-z0-9\-]+\z/
      raise "Invalid protocol format: #{protocol.inspect}"
    end
    quoted_protocol = ActiveRecord::Base.connection.quote_string(protocol)

    regex = %Q{^data:,{"p":"#{quoted_protocol}","op":"mint","tick":"#{quoted_tick}","id":"([1-9][0-9]{0,#{trailing_digit_count}})","amt":"#{mint_amount.to_i}"}$}

    deploy_ethscription = Ethscription.find_by(
      transaction_hash: deploy_ethscription_transaction_hash
    )
    
    sql = <<-SQL
      INSERT INTO token_items (
        ethscription_transaction_hash,
        deploy_ethscription_transaction_hash,
        token_item_id,
        block_number,
        transaction_index,
        created_at,
        updated_at
      )
      SELECT 
        e.transaction_hash,
        '#{deploy_ethscription_transaction_hash}',
        (substring(e.content_uri from '#{regex}')::integer),
        e.block_number,
        e.transaction_index,
        NOW(),
        NOW()
      FROM 
        ethscriptions e
      WHERE 
        e.content_uri ~ '#{regex}' AND
        substring(e.content_uri from '#{regex}')::integer BETWEEN 1 AND #{max_id} AND
        (
          e.block_number > #{deploy_ethscription.block_number} OR 
          (
            e.block_number = #{deploy_ethscription.block_number} AND 
            e.transaction_index > #{deploy_ethscription.transaction_index}
          )
        )
      ON CONFLICT (ethscription_transaction_hash, deploy_ethscription_transaction_hash, token_item_id) 
      DO NOTHING
    SQL

    ActiveRecord::Base.connection.execute(sql)
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
  
  def balance_of(address)
    balances.fetch(address&.downcase, 0)
  end
  
  def save_state_checkpoint!
    item_hashes = token_items.select(:ethscription_transaction_hash)
    
    last_transfer = EthscriptionTransfer.
      where(ethscription_transaction_hash: item_hashes).
      newest_first.first
    
    return unless last_transfer.present?
      
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
    
    if latest_block_number > last_transfer.block_number
      token_states.create!(
        total_supply: balance_map.values.sum,
        balances: balance_map,
        block_number: latest_block_number,
        block_blockhash: latest_block_hash,
        block_timestamp: EthBlock.where(block_number: latest_block_number).pick(:timestamp),
      )
    end
  end
  
  def self.batch_import(tokens)
    tokens.each do |token|
      tick = token.fetch('tick')
      protocol = token.fetch('p')
      max = token.fetch('max')
      lim = token.fetch('lim')
      
      create_from_token_details!(tick: tick, p: protocol, max: max, lim: lim)
    end
  end
  
  def self.find_deploy_transaction(tick:, p:, max:, lim:)    
    uri = %<data:,{"p":"#{p}","op":"deploy","tick":"#{tick}","max":"#{max}","lim":"#{lim}"}>
    
    Ethscription.find_by_content_uri(uri)
  end
  
  def as_json(options = {})
    super(options.merge(except: [:balances])).tap do |json|
      if options[:include_balances]
        json[:balances] = balances
      end
    end
  end
end

class EthBlock < ApplicationRecord
  include OrderQuery
  class BlockNotReadyToImportError < StandardError; end
  
  order_query :newest_first,
    [:block_number, :desc, unique: true]
  
  order_query :oldest_first,
    [:block_number, :asc, unique: true]
    
  %i[
    eth_transactions
    ethscriptions
    ethscription_transfers
    ethscription_ownership_versions
    token_states
  ].each do |association|
    has_many association,
      foreign_key: :block_number,
      primary_key: :block_number,
      inverse_of: :eth_block
  end
  
  before_validation :generate_attestation_hash, if: -> { imported_at.present? }
  
  def self.find_by_page_key(...)
    find_by_block_number(...)
  end
  
  def page_key
    block_number
  end
    
  def self.ethereum_client
    @_ethereum_client ||= begin
      client_class = ENV.fetch('ETHEREUM_CLIENT_CLASS', 'AlchemyClient').constantize
      
      client_class.new(
        api_key: ENV['ETHEREUM_CLIENT_API_KEY'],
        base_url: ENV.fetch('ETHEREUM_CLIENT_BASE_URL')
      )
    end
  end
  
  def self.beacon_client
    @_beacon_client ||= begin
      client_class = ENV.fetch('BEACON_CLIENT_CLASS', 'QuickNodeClient').constantize
      
      client_class.new(
        api_key: ENV['ETHEREUM_BEACON_NODE_API_KEY'],
        base_url: ENV.fetch('ETHEREUM_BEACON_NODE_API_BASE_URL')
      )
    end
  end
    
  def self.genesis_blocks
    blocks = if ENV.fetch('ETHEREUM_NETWORK') == "eth-mainnet"
      [1608625, 3369985, 3981254, 5873780, 8205613, 9046950,
      9046974, 9239285, 9430552, 10548855, 10711341, 15437996, 17478950]
    else
      [[ENV.fetch('TESTNET_START_BLOCK').to_i, 4370001].max]
    end
  
    @_genesis_blocks ||= blocks.sort.freeze
  end
  
  def self.most_recently_imported_block_number
    EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(1).pluck(:block_number).first
  end
  
  def self.most_recently_imported_blockhash
    EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(1).pluck(:blockhash).first
  end
  
  def self.blocks_behind
    (cached_global_block_number - next_block_to_import) + 1
  end
  
  def self.import_batch_size
    [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
  end
  
  def self.import_blocks_until_done
    loop do
      begin
        block_numbers = EthBlock.next_blocks_to_import(import_batch_size)
        
        if block_numbers.blank?
          raise BlockNotReadyToImportError.new("Block not ready")
        end
        
        EthBlock.import_blocks(block_numbers)
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end
  
  def self.import_next_block
    next_block_to_import.tap do |block|
      import_blocks([block])
    end
  end
  
  def self.import_blocks(block_numbers)
    logger.info "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current
    _blocks_behind = blocks_behind
    
    block_by_number_promises = block_numbers.map do |block_number|
      Concurrent::Promise.execute do
        [block_number, ethereum_client.get_block(block_number)]
      end
    end
    
    receipts_promises = block_numbers.map do |block_number|
      Concurrent::Promise.execute do
        [
          block_number,
          ethereum_client.get_transaction_receipts(
            block_number,
            blocks_behind: _blocks_behind
          )
        ]
      end
    end
    
    block_by_number_responses = block_by_number_promises.map(&:value!).sort_by(&:first)
    receipts_responses = receipts_promises.map(&:value!).sort_by(&:first)
    
    res = []
    
    block_by_number_responses.zip(receipts_responses).each do |(block_number1, block_by_number_response), (block_number2, receipts_response)|
      raise "Mismatched block numbers: #{block_number1} and #{block_number2}" unless block_number1 == block_number2
      res << import_block(block_number1, block_by_number_response, receipts_response)
    end
    
    blocks_per_second = (block_numbers.length / (Time.current - start)).round(2)
    puts "Imported #{res.map(&:ethscriptions_imported).sum} ethscriptions"
    puts "Imported #{block_numbers.length} blocks. #{blocks_per_second} blocks / s"
    
    block_numbers
  end
  
  def self.import_block(block_number, block_by_number_response, receipts_response)
    ActiveRecord::Base.transaction do
      validate_ready_to_import!(block_by_number_response, receipts_response)

      result = block_by_number_response['result']
      
      parent_block = EthBlock.find_by(block_number: block_number - 1)
      
      if (block_number > genesis_blocks.max) && parent_block.blockhash != result['parentHash']
        Airbrake.notify("
          Reorg detected: #{block_number},
          #{parent_block.blockhash},
          #{result['parentHash']},
          Deleting block(s): #{EthBlock.where("block_number >= ?", parent_block.block_number).pluck(:block_number).join(', ')}
        ")
        
        EthBlock.where("block_number >= ?", parent_block.block_number).delete_all
        
        return OpenStruct.new(ethscriptions_imported: 0)
      end
      
      block_record = create!(
        block_number: block_number,
        blockhash: result['hash'],
        parent_blockhash: result['parentHash'],
        parent_beacon_block_root: result['parentBeaconBlockRoot'],
        timestamp: result['timestamp'].to_i(16),
        is_genesis_block: genesis_blocks.include?(block_number)
      )
      
      receipts = receipts_response['result']['receipts']
      
      tx_record_instances = result['transactions'].map do |tx|
        current_receipt = receipts.detect { |receipt| receipt['transactionHash'] == tx['hash'] }
        
        gas_price = current_receipt['effectiveGasPrice'].to_i(16).to_d
        gas_used = current_receipt['gasUsed'].to_i(16).to_d
        transaction_fee = gas_price * gas_used
        
        EthTransaction.new(
          block_number: block_record.block_number,
          block_timestamp: block_record.timestamp,
          block_blockhash: block_record.blockhash,
          transaction_hash: tx['hash'],
          from_address: tx['from'],
          to_address: tx['to'],
          created_contract_address: current_receipt['contractAddress'],
          transaction_index: tx['transactionIndex'].to_i(16),
          input: tx['input'],
          status: current_receipt['status']&.to_i(16),
          logs: current_receipt['logs'],
          gas_price: gas_price,
          gas_used: gas_used,
          transaction_fee: transaction_fee,
          value: tx['value'].to_i(16).to_d,
          blob_versioned_hashes: tx['blobVersionedHashes'].presence || []
        )
      end
      
      possibly_relevant = tx_record_instances.select(&:possibly_relevant?)
      
      if possibly_relevant.present?
        EthTransaction.import!(possibly_relevant)
        
        eth_transactions = EthTransaction.where(block_number: block_number).order(transaction_index: :asc)
        
        eth_transactions.each(&:process!)
        
        ethscriptions_imported = eth_transactions.map(&:ethscription).compact.size
      end
      
      EthTransaction.prune_transactions(block_number)
      
      Token.process_block(block_record)
      
      block_record.create_attachments_for_previous_block
      
      block_record.update!(imported_at: Time.current)
      
      puts "Block Importer: imported block #{block_number}"
      
      OpenStruct.new(ethscriptions_imported: ethscriptions_imported.to_i)
    end
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("eth_blocks") && e.message.include?("block_number")
      logger.info "Block Importer: Block #{block_number} already exists"
      raise ActiveRecord::Rollback
    else
      raise
    end
  end
  
  def ensure_blob_sidecars(beacon_block_root = nil)
    if blob_sidecars.present? && blob_sidecars.first['blob'].present?
      return blob_sidecars
    end
    
    beacon_block_root ||= EthBlock.where(block_number: block_number + 1).pick(:parent_beacon_block_root)
    
    raise "Need beacon root" unless beacon_block_root.present?
    
    self.blob_sidecars = EthBlock.beacon_client.get_blob_sidecars(beacon_block_root)
  end
  
  def create_attachments_for_previous_block
    return unless EthTransaction.esip8_enabled?(block_number - 1)
    
    scope = EthTransaction.with_blobs.joins(:ethscription).where(block_number: block_number - 1)
    
    return unless scope.exists?
    
    prev_block = EthBlock.find_by(block_number: block_number - 1)
    
    prev_block.ensure_blob_sidecars(parent_beacon_block_root)
    
    scope.find_each do |tx|
      tx.block_blob_sidecars = prev_block.blob_sidecars
      tx.create_ethscription_attachment_if_needed!
    end
    
    prev_block.blob_sidecars = prev_block.blob_sidecars.map do |sidecar|
      sidecar.except('blob')
    end
    
    prev_block.save!
  end
  
  def self.uncached_global_block_number
    ethereum_client.get_block_number.tap do |block_number|
      Rails.cache.write('global_block_number', block_number, expires_in: 1.second)
    end
  end
  
  def self.cached_global_block_number
    Rails.cache.read('global_block_number') || uncached_global_block_number
  end
  
  def self.validate_ready_to_import!(block_by_number_response, receipts_response)
    is_ready = block_by_number_response.present? &&
      block_by_number_response.dig('result', 'hash').present? &&
      receipts_response.present? &&
      receipts_response.dig('error', 'code') != -32600 &&
      receipts_response.dig('error', 'message') != "Block being processed - please try again later"
    
    unless is_ready
      raise BlockNotReadyToImportError.new("Block not ready")
    end
  end
  
  def self.next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def self.next_blocks_to_import(n)
    max_db_block = EthBlock.maximum(:block_number)
    
    return genesis_blocks.sort.first(n) unless max_db_block
    
    if max_db_block < genesis_blocks.max
      imported_genesis_blocks = EthBlock.where.not(imported_at: nil).where(block_number: genesis_blocks).pluck(:block_number).to_set
      remaining_genesis_blocks = (genesis_blocks.to_set - imported_genesis_blocks).sort
      return remaining_genesis_blocks.first(n)
    end
  
    (max_db_block + 1..max_db_block + n).to_a
  end
  
  def generate_attestation_hash
    hash = Digest::SHA256.new
    
    self.parent_state_hash = EthBlock.where(block_number: block_number - 1).
      limit(1).pluck(:state_hash).first
    
    hash << parent_state_hash.to_s
    
    hash << hashable_attributes.map do |attr|
      send(attr)
    end.to_json

    associations_to_hash.each do |association|
      hashable_attributes = quoted_hashable_attributes(association.klass)
      records = association_scope(association).pluck(*hashable_attributes)

      hash << records.to_json
    end

    self.state_hash = "0x" + hash.hexdigest
  end
  
  delegate :quoted_hashable_attributes, :associations_to_hash, to: :class

  def hashable_attributes
    self.class.hashable_attributes(self.class)
  end
  
  def check_attestation_hash
    current_hash = state_hash
    
    current_hash == generate_attestation_hash &&
    parent_state_hash == EthBlock.find_by(block_number: block_number - 1)&.generate_attestation_hash
  ensure
    self.state_hash = current_hash
  end

  def association_scope(association)
    association.klass.oldest_first.where(block_number: block_number)
  end

  def self.associations_to_hash
    reflect_on_all_associations(:has_many).sort_by(&:name)
  end
  
  def self.all_hashable_attrs
    classes = [self, associations_to_hash.map(&:klass)].flatten
    
    classes.map(&:column_names).flatten.uniq.sort - [
      'state_hash',
      'parent_state_hash',
      'id',
      'created_at',
      'updated_at',
      'imported_at'
    ]
  end
  
  def self.hashable_attributes(klass)
    (all_hashable_attrs & klass.column_names).sort
  end

  def self.quoted_hashable_attributes(klass)
    hashable_attributes(klass).map do |attr|
      Arel.sql("encode(digest(#{klass.connection.quote_column_name(attr)}::text, 'sha256'), 'hex')")
    end
  end
end

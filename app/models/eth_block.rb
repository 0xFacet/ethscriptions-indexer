class EthBlock < ApplicationRecord
  class BlockNotReadyToImportError < StandardError; end
  
  has_many :eth_transactions, foreign_key: :block_number, primary_key: :block_number,
    inverse_of: :eth_block
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number,
    inverse_of: :eth_block
  has_many :ethscription_transfers, foreign_key: :block_number, primary_key: :block_number,
    inverse_of: :eth_block
  
  def self.genesis_blocks
    blocks = if ENV.fetch('ETHEREUM_NETWORK') == "eth-mainnet"
      [1608625, 3369985, 3981254, 5873780, 8205613, 9046950,
      9046974, 9239285, 9430552, 10548855, 10711341, 15437996, 17478950]
    elsif ENV.fetch('ETHEREUM_NETWORK') == "eth-goerli"
      [ENV.fetch('GOERLI_START_BLOCK', 9228092).to_i]
    end
  
    @_genesis_blocks ||= blocks.sort.freeze
  end
  
  def self.most_recently_imported_block_number
    EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(1).pluck(:block_number).first
  end
  
  def self.import_blocks_until_done
    loop do
      begin
        last_imported = nil
        elapsed = Benchmark.ms do
          last_imported = EthBlock.import_next_block
        end
        
        puts "Imported #{last_imported} in #{elapsed.round}ms"
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end
  
  # def self.a
  #   import_next_block
  # end
  
  def self.import_next_block
    import_block(next_block_to_import)
  end
  
  # def self.handle_long_reorgs
  #   last_finalized_block = AlchemyClient.query_api(
  #     method: 'eth_getBlockByNumber',
  #     params: ['finalized', false]
  #   )['result']['number'].to_i(16)
    
  #   detect_and_rollback_reorg(from_block: last_finalized_block)
  # end
  
  # def self.handle_short_reorgs
  #   detect_and_rollback_reorg(from_block: Ethscription.partially_confirmed_block_number)
  # end
  
  # def self.handle_medium_reorgs
  #   detect_and_rollback_reorg(
  #     from_block: Ethscription.partially_confirmed_block_number - 7
  #   )
  # end
  
  # def self.detect_and_rollback_reorg(from_block:)
  #   ActiveRecord::Base.transaction do
  #     possible_reorg_blocks = EthBlock.where(
  #       "block_number > ?", from_block
  #     ).order(block_number: :asc)
      
  #     oldest_reorged_block = possible_reorg_blocks.detect do |block|
  #       block_data = AlchemyClient.query_api(
  #         method: 'eth_getBlockByNumber',
  #         params: ['0x' + block.block_number.to_s(16), false]
  #       )['result']
        
  #       live_hash = block_data['hash']
  #       saved_hash = block.blockhash
        
  #       block if live_hash != saved_hash
  #     end
      
  #     raise ActiveRecord::Rollback if oldest_reorged_block.blank?
      
  #     blocks_to_reimport = EthBlock.where("block_number >= ?", oldest_reorged_block.block_number)
      
  #     destroyed = blocks_to_reimport.each(&:destroy!)
      
  #     current_block_number = EthBlock.uncached_global_block_number

  #     Airbrake.notify("Current block: #{current_block_number}, reorg detected: #{oldest_reorged_block.block_number}, destroyed blocks: #{destroyed.map(&:block_number)}")
  #   end
  # end
  
  def self.import_block(block_number)
    logger.info "Block Importer: importing #{block_number}"
    
    ActiveRecord::Base.transaction do
      unless EthBlock.next_block_to_import == block_number
        logger.info "Block Importer: #{block_number} is not next to import"
        raise ActiveRecord::Rollback
      end
      
      block_by_number_promise = Concurrent::Promise.execute do
        AlchemyClient.query_api(
          method: 'eth_getBlockByNumber',
          params: ['0x' + block_number.to_s(16), true]
        )
      end
      
      receipts_promise = Concurrent::Promise.execute do
        AlchemyClient.query_api(
          method: 'alchemy_getTransactionReceipts',
          params: [{ blockNumber: "0x" + block_number.to_s(16) }]
        )
      end
      
      block_by_number_response = block_by_number_promise.value
      receipts_response = receipts_promise.value      
      
      result = block_by_number_response['result']
      
      validate_ready_to_import!(block_by_number_response, receipts_response)
      
      parent_block = EthBlock.find_by(block_number: block_number - 1)
      
      if (block_number > genesis_blocks.max) && parent_block.blockhash != result['parentHash']
        logger.info "Block Importer: Parent block hash does not match, reorg detected"
        EthBlock.where("block_number >= ?", parent_block.block_number).delete_all
        return
      end
      
      block_record = create!(
        block_number: block_number,
        blockhash: result['hash'],
        parent_blockhash: result['parentHash'],
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
        )
      end
      
      possibly_relevant = tx_record_instances.select(&:possibly_relevant?)
      
      if possibly_relevant.present?
        EthTransaction.import!(possibly_relevant)
        
        eth_transactions = EthTransaction.where(block_number: block_number).order(transaction_index: :asc)
        
        eth_transactions.each(&:process!)
        
        # EthTransaction.where(block_number: block_number)
        #   .where.not(transaction_hash: Ethscription.where(block_number: block_number).select(:transaction_hash))
        #   .where.not(transaction_hash: EthscriptionTransfer.where(block_number: block_number).select(:transaction_hash))
        #   .delete_all
      end
      
      block_record.update!(imported_at: Time.current)
      
      logger.info "Block Importer: imported block #{block_number}"
    end
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("eth_blocks") && e.message.include?("block_number")
      logger.info "Block Importer: Block #{block_number} already exists"
      raise ActiveRecord::Rollback
    else
      raise
    end
  end
  
  def self.uncached_global_block_number
    AlchemyClient.query_api(method: 'eth_blockNumber')['result'].to_i(16)
  end
  
  def self.cached_global_block_number
    Rails.cache.fetch('global_block_number', expires_in: 1.second) do
      uncached_global_block_number
    end
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
    max_db_block = EthBlock.maximum(:block_number)
    
    return genesis_blocks.min unless max_db_block
    
    if max_db_block < genesis_blocks.max
      imported_genesis_blocks = EthBlock.where.not(imported_at: nil).where(block_number: genesis_blocks).pluck(:block_number).to_set
      
      return (genesis_blocks.to_set - imported_genesis_blocks).min
    end

    max_db_block + 1
  end
  
  def essential_attributes
    attributes.slice(
      'block_number',
      'timestamp',
      "blockhash",
      "parent_blockhash"
    )
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :block_number,
          :imported_at,
          :blockhash,
          :parent_blockhash,
        ],
      )
    ).with_indifferent_access
  end
end

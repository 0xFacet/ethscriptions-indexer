class EthscriptionsController < ApplicationController
  def index
    scope = filter_by_params(Ethscription.all,
      :current_owner,
      :creator,
      :previous_owner,
      :mimetype,
      :media_type,
      :mime_subtype,
      :sha,
      :transaction_hash,
      :block_number,
      :ethscription_number
    )

    include_latest_transfer = params[:include_latest_transfer].present?
    
    if include_latest_transfer
      scope = scope.includes(:ethscription_transfers)
    end
    
    token_tick = parse_param_array(params[:token_tick]).first
    token_protocol = parse_param_array(params[:token_protocol]).first
    transferred_in_tx = parse_param_array(params[:transferred_in_tx])
    
    if token_tick && token_protocol
      scope = scope.with_token_tick_and_protocol(token_tick, token_protocol)
    end
    
    if transferred_in_tx.present?
      sub_query = EthscriptionTransfer.where(transaction_hash: transferred_in_tx).select(:ethscription_transaction_hash)
      scope = scope.where(transaction_hash: sub_query)
    end
    
    transaction_hash_only = params[:transaction_hash_only].present? && !include_latest_transfer
    
    if transaction_hash_only
      scope = scope.select(:id, :transaction_hash)
    end
    
    results_limit = if transaction_hash_only
      1000
    elsif include_latest_transfer
      50
    else
      100
    end
    
    cache_on_block do
      results, pagination_response = paginate(
        scope,
        results_limit: results_limit
      )
      
      results = results.map do |ethscription|
        ethscription.as_json(include_latest_transfer: include_latest_transfer)
      end
      
      render json: {
        result: numbers_to_strings(results),
        pagination: pagination_response
      }
    end
  end
  
  def show
    scope = Ethscription.all.includes(:ethscription_transfers)
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: id_or_hash) : 
      scope.where(ethscription_number: id_or_hash)
    
    ethscription = Rails.cache.fetch(["ethscription-api-show", scope]) do
      scope.first
    end
    
    if !ethscription
      render json: { error: "Not found" }, status: 404
      return
    end
    
    cache_on_block do
      render json: {
        result: numbers_to_strings(ethscription.as_json(include_transfers: true))
      }
    end
  end
  
  def data
    scope = Ethscription.all
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: id_or_hash) : 
      scope.where(ethscription_number: id_or_hash)
    
    item = scope.first
    
    if item
      cache_on_block(cache_forever_with: item.block_number) do
        uri_obj = item.parsed_data_uri
      
        send_data(uri_obj.decoded_data, type: uri_obj.mimetype, disposition: 'inline')
      end
    else
      head 404
    end
  end
  
  def newer_ethscriptions
    mimetypes = params[:mimetypes] || []
    initial_owner = params[:initial_owner]
    requested_block_number = params[:block_number].to_i
    client_past_ethscriptions_count = params[:past_ethscriptions_count]
    past_ethscriptions_checksum = params[:past_ethscriptions_checksum]
    
    system_max_ethscriptions = ENV.fetch('MAX_ETHSCRIPTIONS_PER_VM_REQUEST', 25).to_i
    system_max_blocks = ENV.fetch('MAX_BLOCKS_PER_VM_REQUEST', 50).to_i
    
    max_ethscriptions = [params[:max_ethscriptions]&.to_i || 50, system_max_ethscriptions].min
    max_blocks = [params[:max_blocks]&.to_i || 500, system_max_blocks].min

    scope = Ethscription.all.oldest_first
    scope = scope.where(mimetype: mimetypes) if mimetypes.present?
    scope = scope.where(initial_owner: initial_owner) if initial_owner.present?
    
    unless scope.exists?
      render json: {
        error: {
          message: "No matching ethscriptions found",
          resolution: :retry_with_delay
        }
      }, status: :unprocessable_entity
      return
    end
    
    requested_block_number = [requested_block_number, scope.limit(1).pluck(:block_number).first].max
    
    we_are_up_to_date = EthBlock.where(block_number: requested_block_number).
      where.not(imported_at: nil).exists?
    
    unless we_are_up_to_date
      render json: {
        error: {
          message: "Block not yet imported. Please try again later",
          resolution: :retry
        }
      }, status: :unprocessable_entity
      return
    end
    
    if client_past_ethscriptions_count && past_ethscriptions_checksum.blank?
      our_past_count = scope.where('block_number < ?', requested_block_number).count
    
      if our_past_count != client_past_ethscriptions_count.to_i
        render json: {
          error: {
            message: "Count is off",
            resolution: :reindex
          }
        }, status: :unprocessable_entity
        return
      end
    end
    
    if past_ethscriptions_checksum.present?
      checksum_scope = scope.where("block_number < ?", requested_block_number)
      our_checksum = Ethscription.scope_checksum(checksum_scope)
      
      if our_checksum != past_ethscriptions_checksum
        render json: {
          error: {
            message: "Invalid Checksum",
            resolution: :reindex
          }
        }, status: :unprocessable_entity
        return
      end
    end
    
    last_ethscription_block = scope.where('block_number >= ? AND block_number < ?', 
                                requested_block_number, 
                                requested_block_number + max_blocks)
                          .order(:block_number, :transaction_index)
                          .offset(max_ethscriptions - 1)
                          .pluck(:block_number)
                          .first

    last_block_in_range = last_ethscription_block || requested_block_number + max_blocks - 1
    
    last_block_in_range -= 1 if last_block_in_range > requested_block_number
    
    block_range = (requested_block_number..last_block_in_range).to_a
    
    all_blocks_in_range = EthBlock.where(block_number: block_range).where.not(imported_at: nil).order(:block_number).index_by(&:block_number)
    
    if all_blocks_in_range[requested_block_number].nil?
      render json: {
        error: {
          message: "Block not yet imported. Please try again later",
          resolution: :retry
        }
      }, status: :unprocessable_entity
      return
    end
    
    ethscriptions_in_range = scope.where(block_number: block_range)

    ethscriptions_by_block = ethscriptions_in_range.group_by(&:block_number)
  
    block_data = all_blocks_in_range.map do |block_number, block|
      current_block_ethscriptions = ethscriptions_by_block[block_number] || []
      {
        blockhash: block.blockhash,
        parent_blockhash: block.parent_blockhash,
        block_number: block.block_number,
        timestamp: block.timestamp.to_i,
        ethscriptions: current_block_ethscriptions
      }
    end
    
    total_ethscriptions_in_future_blocks = scope.where('block_number > ?', block_range.last).count
    
    cache_on_block do
      render json: {
        total_future_ethscriptions: total_ethscriptions_in_future_blocks,
        blocks: block_data
      }
    end
  end
end

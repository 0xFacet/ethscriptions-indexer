class TokensController < ApplicationController
  def index
    scope = filter_by_params(Token.all,
      :protocol,
      :tick
    )
    
    results, pagination_response = paginate(scope)
    
    cache_on_block
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
  end
  
  def balances
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    if !token
      render json: { error: "Not found" }, status: 404
      return
    end
    
    cache_on_block
    
    render json: {
      result: numbers_to_strings(token.balances(params[:as_of_block_number]&.to_i))
    }
  end
  
  def balance_of
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    if !token
      render json: { error: "Not found" }, status: 404
      return
    end
    
    balance = token.balance_of(
      address: params[:address]&.downcase,
      as_of_block_number: params[:as_of_block_number]&.to_i
    )
    
    cache_on_block
    
    render json: {
      result: numbers_to_strings(balance.to_s)
    }
  end
  
  def balances_observations
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    cache_on_block
    
    render json: {
      result: numbers_to_strings(token.balances_observations)
    }
  end
  
  def validate_token_items
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])

    tx_hashes = if request.post?
      params.require(:transaction_hashes)
    else
      parse_param_array(params[:transaction_hashes])
    end
    
    valid_tx_hash_scope = token.token_items.where(
      ethscription_transaction_hash: tx_hashes
    )
    
    results, pagination_response = paginate(valid_tx_hash_scope)
    
    valid_tx_hashes = results.map(&:ethscription_transaction_hash)
    
    invalid_tx_hashes = tx_hashes.sort - valid_tx_hashes.sort
    
    cache_on_block
    
    res = {
      valid: valid_tx_hashes,
      invalid: invalid_tx_hashes,
      token_items_checksum: token.token_items_checksum
    }
    
    render json: {
      result: numbers_to_strings(res),
      pagination: pagination_response
    }
  end
end

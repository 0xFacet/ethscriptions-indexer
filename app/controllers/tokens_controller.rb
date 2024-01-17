class TokensController < ApplicationController
  def index
    page, per_page = pagination_params
    
    scope = Token.all.page(page).per(per_page)
    
    tokens = Rails.cache.fetch(["tokens-api-all", scope]) do
      numbers_to_strings(scope.to_a)
    end
    
    render json: {
      result: tokens
    }
  end
  
  def balances
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    render json: {
      result: numbers_to_strings(token.balances(params[:as_of_block_number]&.to_i))
    }
  end
  
  def balance_of
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    balance = token.balance_of(
      address: params[:address],
      as_of_block_number: params[:as_of_block_number]&.to_i
    )
    
    render json: {
      result: numbers_to_strings(balance.to_s)
    }
  end
  
  def balances_observations
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    render json: {
      result: numbers_to_strings(token.balances_observations)
    }
  end
  
  def validate_token_items
    page, per_page = pagination_params
    
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])

    tx_hashes = parse_param_array(params[:transaction_hashes])
    
    valid_tx_hash_scope = token.token_items.where(
      ethscription_transaction_hash: tx_hashes
    ).page(page).per(per_page)
    
    valid_tx_hashes = valid_tx_hash_scope.pluck(:ethscription_transaction_hash)
    
    invalid_tx_hashes = tx_hashes.sort - valid_tx_hashes.sort
    
    res = {
      valid: valid_tx_hashes,
      invalid: invalid_tx_hashes,
      token_items_checksum: token.token_items_checksum
    }
    
    render json: {
      result: numbers_to_strings(res),
      total_count: valid_tx_hash_scope.total_count
    }
  end
end

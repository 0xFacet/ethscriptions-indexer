class TokensController < ApplicationController
  before_action :set_token, only: [:show, :historical_state, :balance_of, :validate_token_items]
  
  def index
    scope = filter_by_params(Token.all,
      :protocol,
      :tick
    )
    
    cache_on_block do
      results, pagination_response = paginate(scope)
      
      render json: {
        result: numbers_to_strings(results),
        pagination: pagination_response
      }
    end
  end
  
  def show
    cache_on_block do
      json = @token.as_json(include_balances: true)
      
      render json: {
        result: numbers_to_strings(json),
        pagination: {}
      }
    end
  end
  
  def historical_state
    as_of_block = params[:as_of_block].to_i
    
    cache_on_block do
      state = @token.token_states.
        where("block_number <= ?", as_of_block).
        newest_first.limit(1).first
      
      render json: {
        result: numbers_to_strings(state),
        pagination: {}
      }
    end
  end
  
  def balance_of
    balance = @token.balance_of(params[:address])
    
    cache_on_block do
      render json: {
        result: numbers_to_strings(balance.to_s)
      }
    end
  end
  
  def validate_token_items
    tx_hashes = if request.post?
      params.require(:transaction_hashes)
    else
      parse_param_array(params[:transaction_hashes])
    end
    
    cache_on_block do
      valid_tx_hash_scope = @token.token_items.where(
        ethscription_transaction_hash: tx_hashes
      )
      
      results, pagination_response = paginate(valid_tx_hash_scope)
      
      valid_tx_hashes = results.map(&:ethscription_transaction_hash)
      
      invalid_tx_hashes = tx_hashes.sort - valid_tx_hashes.sort
      
      res = {
        valid: valid_tx_hashes,
        invalid: invalid_tx_hashes,
        token_items_checksum: @token.token_items_checksum
      }
      
      render json: {
        result: numbers_to_strings(res),
        pagination: pagination_response
      }
    end
  end
  
  private

  def set_token
    @token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    raise RequestedRecordNotFound unless @token
  end
end

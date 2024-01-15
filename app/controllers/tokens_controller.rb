class TokensController < ApplicationController
  def index
    page = (params[:page] || 1).to_i.clamp(1, 10)
    per_page = (params[:per_page] || 25).to_i.clamp(1, 50)
    
    scope = Token.all.page(page).per(per_page)
    
    tokens = Rails.cache.fetch(["tokens-api-all", scope]) do
      scope.to_a
    end
    
    render json: {
      result: tokens
    }
  end
  
  def holders
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    render json: {
      result: token.safe_balances(params[:max_blocks_behind])
    }
  end
  
  def balance_of
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])
    
    balance = token.balance_of(params[:address], params[:max_blocks_behind])
    
    render json: {
      result: balance.to_s
    }
  end
  
  def validate_token_items
    token = Token.find_by_protocol_and_tick(params[:protocol], params[:tick])

    valid_tx_hashes = token.token_items.where(
      ethscription_transaction_hash: params[:transaction_hashes]
    ).pluck(:ethscription_transaction_hash)
    
    invalid_tx_hashes = params[:transaction_hashes].sort - valid_tx_hashes.sort
    
    render json: {
      result: {
        valid: valid_tx_hashes,
        invalid: invalid_tx_hashes,
        token_items_checksum: token.token_items_checksum
      }
    }
  end
end

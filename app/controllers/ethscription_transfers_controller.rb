class EthscriptionTransfersController < ApplicationController
  def index
    page = (params[:page] || 1).to_i.clamp(1, 10)
    per_page = (params[:per_page] || 25).to_i.clamp(1, 50)
    
    scope = EthscriptionTransfer.all.page(page).per(per_page)
    
    scope = scope.where(from_address: parse_param_array(params[:from])) if params[:from].present?
    scope = scope.where(to_address: parse_param_array(params[:to])) if params[:to].present?
    scope = scope.where(transaction_hash: parse_param_array(params[:transaction_hash])) if params[:transaction_hash].present?
    
    scope = params[:sort_order]&.downcase == "asc" ? scope.oldest_first : scope.newest_first
    
    render json: {
      result: numbers_to_strings(scope)
    }
  end
end

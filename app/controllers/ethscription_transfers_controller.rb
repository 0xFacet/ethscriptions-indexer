class EthscriptionTransfersController < ApplicationController
  def index
    page, per_page = pagination_params
    
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

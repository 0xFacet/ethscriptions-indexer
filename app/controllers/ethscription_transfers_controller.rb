class EthscriptionTransfersController < ApplicationController
  def index
    page, per_page = pagination_params
    
    scope = EthscriptionTransfer.all.page(page).per(per_page)
    
    scope = filter_by_params(scope,
      :from_address,
      :to_address,
      :transaction_hash
    )
    
    scope = params[:sort_order]&.downcase == "asc" ? scope.oldest_first : scope.newest_first
    
    render json: {
      result: numbers_to_strings(scope),
      total_count: scope.total_count
    }
  end
end

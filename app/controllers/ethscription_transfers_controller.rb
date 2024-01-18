class EthscriptionTransfersController < ApplicationController
  def index
    page, per_page = pagination_params
    
    scope = EthscriptionTransfer.all.page(page).per(per_page)
    
    scope = filter_by_params(scope,
      :from_address,
      :to_address,
      :transaction_hash
    )
    
    to_or_from = parse_param_array(params[:to_or_from])
    
    if to_or_from.present?
      scope = scope.where(from_address: to_or_from)
                   .or(scope.where(to_address: to_or_from))
    end
    
    ethscription_token_tick = parse_param_array(params[:ethscription_token_tick]).first
    ethscription_token_protocol = parse_param_array(params[:ethscription_token_protocol]).first
    
    if ethscription_token_tick && ethscription_token_protocol
      tokens = Ethscription.with_token_tick_and_protocol(
        ethscription_token_tick,
        ethscription_token_protocol
      ).select(:transaction_hash)
      
      scope = scope.where(ethscription_transaction_hash: tokens)
    end
    
    scope = params[:sort_order]&.downcase == "asc" ? scope.oldest_first : scope.newest_first
    
    render json: {
      result: numbers_to_strings(scope),
      total_count: scope.total_count
    }
  end
end

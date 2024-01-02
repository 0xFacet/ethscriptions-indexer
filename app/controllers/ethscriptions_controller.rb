class EthscriptionsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i.clamp(1, 10)
    per_page = (params[:per_page] || 25).to_i.clamp(1, 50)
    
    scope = Ethscription.all.page(page).per(per_page).includes(:ethscription_transfers)
    
    scope = params[:sort_order]&.downcase == "asc" ? scope.oldest_first : scope.newest_first
    
    ethscriptions = Rails.cache.fetch(["ethscription-api-all", scope]) do
      scope.to_a
    end
    
    render json: ethscriptions
  end
  
  def show
    scope = Ethscription.all.includes(:ethscription_transfers)
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: params[:id]) : 
      scope.where(ethscription_number: params[:id])
    
    ethscription = Rails.cache.fetch(["ethscription-api-show", scope]) do
      scope.first
    end
    
    if !ethscription
      render json: { error: "Not found" }, status: 404
      return
    end
    
    render json: ethscription
  end
  
  def data
    scope = Ethscription.all
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: params[:id]) : 
      scope.where(ethscription_number: params[:id])
    
    item = scope.first
    
    if item
      uri_obj = item.parsed_data_uri
      
      send_data(uri_obj.decoded_data, type: uri_obj.mimetype, disposition: 'inline')
    else
      head 404
    end
  end
end

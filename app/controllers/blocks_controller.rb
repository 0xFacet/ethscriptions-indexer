class BlocksController < ApplicationController
  cache_actions_on_block
  
  def index
    results, pagination_response = paginate(EthBlock.all)
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
  end

  def show
    scope = EthBlock.all.where(block_number: params[:id])

    block = Rails.cache.fetch(["block-api-show", scope]) do
      scope.first
    end
    
    if !block
      render json: { error: "Not found" }, status: 404
      return
    end
    
    render json: block
  end
  
  def newer_blocks
    limit = [params[:limit]&.to_i || 100, 2500].min
    requested_block_number = params[:block_number].to_i
    
    scope = EthBlock.where("block_number >= ?", requested_block_number).
      limit(limit).
      where.not(imported_at: nil)
    
    res = Rails.cache.fetch(['newer_blocks', scope]) do
      scope.to_a
    end
    
    render json: {
      result: res
    }
  end
end

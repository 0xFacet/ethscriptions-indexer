class BlocksController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 25).to_i.clamp(1, 50)

    scope = EthBlock.all.page(page).per(per_page)

    scope = params[:sort_order]&.downcase == "asc" ? scope.oldest_first : scope.newest_first

    blocks = Rails.cache.fetch(["block-api-all", scope]) do
      scope.to_a
    end

    render json: blocks
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
end

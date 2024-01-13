class StatusController < ApplicationController
  def indexer_status
    current_block_number = EthBlock.cached_global_block_number
    last_imported_block = EthBlock.most_recently_imported_block_number
    
    blocks_behind = current_block_number - last_imported_block
    
    resp = {
      current_block_number: current_block_number,
      last_imported_block: last_imported_block,
      blocks_behind: blocks_behind
    }
    
    render json: resp
  end
end

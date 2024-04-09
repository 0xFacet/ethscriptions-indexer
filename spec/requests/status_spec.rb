require 'swagger_helper'

RSpec.describe 'Status API', doc: true do
  path '/status' do
    get 'Show Indexer Status' do
      tags 'Status'
      operationId 'getIndexerStatus'
      produces 'application/json'
      description 'Retrieves the current status of the blockchain indexer, including the latest block number known, the last block number imported into the system, and the number of blocks the indexer is behind.'
  
      response '200', 'Indexer status retrieved successfully' do
        schema type: :object,
               properties: {
                 current_block_number: {
                   type: :integer,
                   example: 19620494,
                   description: 'The most recent block number known to the global blockchain network.'
                 },
                 last_imported_block: {
                   type: :integer,
                   example: 19620494,
                   description: 'The last block number that was successfully imported into the system.'
                 },
                 blocks_behind: {
                   type: :integer,
                   example: 0,
                   description: 'The number of blocks the indexer is behind the current block number.'
                 }
               },
               required: ['current_block_number', 'last_imported_block', 'blocks_behind'],
               description: 'Response body containing the current status of the blockchain indexer.'
  
        run_test!
      end
  
      response '500', 'Error retrieving indexer status' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Internal Server Error' }
               },
               description: 'Error message indicating a failure to retrieve the indexer status.'
  
        run_test!
      end
    end
  end  
end

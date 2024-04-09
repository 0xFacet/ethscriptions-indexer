require 'swagger_helper'

RSpec.describe 'Tokens API', doc: true do
  path '/tokens' do
    get 'List Tokens' do
      tags 'Tokens'
      operationId 'listTokens'
      produces 'application/json'
      description 'Retrieves a list of tokens based on specified criteria such as protocol and tick.'
  
      parameter name: :protocol, 
                in: :query, 
                type: :string, 
                description: 'Filter tokens by protocol (e.g., "erc-20"). Optional.',
                required: false
  
      parameter name: :tick, 
                in: :query, 
                type: :string, 
                description: 'Filter tokens by tick (symbol). Optional.',
                required: false
  
      # Assuming you've already defined common pagination parameters in ApiCommonParameters
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter
  
      response '200', 'Tokens retrieved successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :array,
                   items: { '$ref' => '#/components/schemas/Token' }
                 },
                 pagination: { '$ref' => '#/components/schemas/PaginationObject' }
               },
               description: 'A list of tokens that match the query criteria, along with pagination details.'
  
        run_test!
      end
  
      response '400', 'Invalid request parameters' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Invalid parameters' }
               },
               description: 'Error message indicating that the request parameters were invalid.'
  
        run_test!
      end
    end
  end
  
  path '/tokens/{protocol}/{tick}' do
    get 'Show Token Details' do
      tags 'Tokens'
      operationId 'showTokenDetails'
      produces 'application/json'
      description 'Retrieves detailed information about a specific token, identified by its protocol and tick, including its balances.'
  
      parameter name: :protocol, 
                in: :path, 
                type: :string, 
                description: 'The protocol of the token to retrieve (e.g., "erc-20").',
                required: true
  
      parameter name: :tick, 
                in: :path, 
                type: :string, 
                description: 'The tick (symbol) of the token to retrieve.',
                required: true
  
      response '200', 'Token details retrieved successfully' do
        schema type: :object,
               properties: {
                 result: { '$ref' => '#/components/schemas/TokenWithBalances' },
               },
               description: 'Detailed information about the requested token, including its balances.'
  
        run_test!
      end
  
      response '404', 'Token not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Token not found' }
               },
               description: 'Error message indicating that the requested token was not found.'
  
        run_test!
      end
    end
  end
  
  path '/tokens/{protocol}/{tick}/historical_state' do
    get 'Get Token Historical State' do
      tags 'Tokens'
      operationId 'getTokenHistoricalState'
      produces 'application/json'
      description 'Retrieves the state of a specific token, identified by its protocol and tick, at a given block number.'
  
      parameter name: :protocol, 
                in: :path, 
                type: :string, 
                description: 'The protocol of the token for which historical state is being requested (e.g., "erc-20").',
                required: true
  
      parameter name: :tick, 
                in: :path, 
                type: :string, 
                description: 'The tick (symbol) of the token for which historical state is being requested.',
                required: true
  
      parameter name: :as_of_block, 
                in: :query, 
                type: :integer, 
                description: 'The block number at which the token state is requested.',
                required: true
  
      response '200', 'Token historical state retrieved successfully' do
        schema type: :object,
               properties: {
                 result: { '$ref' => '#/components/schemas/TokenWithBalances' }
               },
               description: 'The state of the requested token at the specified block number, including its balances.'
  
        run_test!
      end
  
      response '404', 'Token or state not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Token or state not found at the specified block number' }
               },
               description: 'Error message indicating that either the token or its state at the specified block number was not found.'
  
        run_test!
      end
    end
  end
  path '/tokens/{protocol}/{tick}/validate_token_items' do
    get 'Validate Token Items' do
      tags 'Tokens'
      operationId 'validateTokenItems'
      produces 'application/json'
      description <<~DESC
        Validates a list of transaction hashes against the token items of a specified token. Returns arrays of valid and invalid transaction hashes along with a checksum for the token items.
      DESC
  
      parameter name: :protocol,
                in: :path,
                type: :string,
                description: 'The protocol of the token for which items are being validated (e.g., "erc-20").',
                required: true
  
      parameter name: :tick,
                in: :path,
                type: :string,
                description: 'The tick (symbol) of the token for which items are being validated.',
                required: true
  
      parameter name: :transaction_hashes,
                in: :query,
                type: :array,
                items: {
                  type: :string,
                  description: 'A transaction hash.'
                },
                collectionFormat: :multi,
                description: 'An array of transaction hashes to validate against the token\'s items.',
                required: true
  
      response '200', 'Token items validated successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :object,
                   properties: {
                     valid: {
                       type: :array,
                       items: {
                         type: :string
                       },
                       description: 'Valid transaction hashes.'
                     },
                     invalid: {
                       type: :array,
                       items: {
                         type: :string
                       },
                       description: 'Invalid transaction hashes.'
                     },
                     token_items_checksum: {
                       type: :string,
                       description: 'A checksum for the token items.'
                     }
                   }
                 }
               },
               description: 'Returns arrays of valid and invalid transaction hashes along with a checksum for the token items.'
  
        run_test!
      end
  
      response '404', 'Token not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Requested token not found' }
               },
               description: 'Error message indicating the token was not found.'
  
        run_test!
      end
    end
  end
  
end

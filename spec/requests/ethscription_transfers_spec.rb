require 'swagger_helper'

RSpec.describe 'Ethscription Transfers API', doc: true do
  path '/ethscription_transfers' do
    get 'List Ethscription Transfers' do
      tags 'Ethscription Transfers'
      operationId 'listEthscriptionTransfers'
      produces 'application/json'
      description <<~DESC
        Retrieves a list of Ethscription transfers based on filter criteria such as from address, to address, and transaction hash. Supports filtering by token characteristics (tick and protocol) and address involvement (to or from).
      DESC
  
      parameter name: :from_address, in: :query, type: :string,
                description: 'Filter transfers by the sender’s address.', required: false
  
      parameter name: :to_address, in: :query, type: :string,
                description: 'Filter transfers by the recipient’s address.', required: false
  
      parameter name: :transaction_hash, in: :query, type: :string,
                description: 'Filter transfers by the Ethscription transaction hash.', required: false
  
      parameter name: :to_or_from, in: :query, type: :array, items: { type: :string },
                description: 'Filter transfers by addresses involved either as sender or recipient.', required: false
  
      parameter name: :ethscription_token_tick, in: :query, type: :string,
                description: 'Filter transfers by the Ethscription token tick.', required: false
  
      parameter name: :ethscription_token_protocol, in: :query, type: :string,
                description: 'Filter transfers by the Ethscription token protocol.', required: false
  
      # Include pagination parameters as needed
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter
  
      response '200', 'Transfers retrieved successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :array,
                   items: { '$ref' => '#/components/schemas/EthscriptionTransfer' }
                 },
                 pagination: { '$ref' => '#/components/schemas/PaginationObject' }
               },
               description: 'A list of Ethscription transfers that match the filter criteria.'
  
        run_test!
      end
    end
  end
  
end


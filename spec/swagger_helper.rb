# frozen_string_literal: true

require 'rails_helper'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Ethscriptions API V2',
        version: 'v2'
      },
      paths: {},
      components: {
        schemas: {
          Ethscription: {
            type: :object,
            properties: {
              transaction_hash: { type: :string, example: '0x0ef100873db4e3b7446e9a3be0432ab8bc92119d009aa200f70c210ac9dcd4a6', description: 'Hash of the Ethereum transaction.' },
              block_number: { type: :string, example: '19619510', description: 'Block number where the transaction was included.' },
              transaction_index: { type: :string, example: '88', description: 'Transaction index within the block.' },
              block_timestamp: { type: :string, example: '1712682959', description: 'Timestamp for when the block was mined.' },
              block_blockhash: { type: :string, example: '0xa44323fa6404b446665037ec61a09fc8526144154cb3742bcd254c7ef054ab0c', description: 'Hash of the block.' },
              ethscription_number: { type: :string, example: '5853618', description: 'Unique identifier for the ethscription.' },
              creator: { type: :string, example: '0xc27b42d010c1e0f80c6c0c82a1a7170976adb340', description: 'Address of the ethscription creator.' },
              initial_owner: { type: :string, example: '0x00000000000000000000000000000000000face7', description: 'Initial owner of the ethscription.' },
              current_owner: { type: :string, example: '0x00000000000000000000000000000000000face7', description: 'Current owner of the ethscription.' },
              previous_owner: { type: :string, example: '0xc27b42d010c1e0f80c6c0c82a1a7170976adb340', description: 'Previous owner of the ethscription before the current owner.' },
              content_uri: { type: :string, example: 'data:application/vnd.facet.tx+json;rule=esip6,{...}', description: 'URI encoding the data and rule for the ethscription.' },
              content_sha: { type: :string, example: '0xda6dce30c4c09885ed8538c9e33ae43cfb392f5f6d42a62189a446093929e115', description: 'SHA hash of the content.' },
              esip6: { type: :boolean, example: true, description: 'Indicator of whether the ethscription conforms to ESIP-6.' },
              mimetype: { type: :string, example: 'application/vnd.facet.tx+json', description: 'MIME type of the ethscription.' },
              gas_price: { type: :string, example: '37806857216', description: 'Gas price used for the transaction.' },
              gas_used: { type: :string, example: '27688', description: 'Amount of gas used by the transaction.' },
              transaction_fee: { type: :string, example: '1046796262596608', description: 'Total fee of the transaction.' },
              value: { type: :string, example: '0', description: 'Value transferred in the transaction.' },
              attachment_sha: { type: :string, nullable: true, example: '0x0ef100873db4e3b7446e9a3be0432ab8bc92119d009aa200f70c210ac9dcd4a6', description: 'SHA hash of the attachment.' },
              attachment_content_type: { type: :string, nullable: true, example: 'text/plain', description: 'MIME type of the attachment.' }
            },
          },
        },
        EthscriptionTransfer: {
          type: :object,
          properties: {
            ethscription_transaction_hash: { 
              type: :string, 
              example: '0x4c5d41...',
              description: 'Hash of the ethscription associated with the transfer.'
            },
            transaction_hash: { 
              type: :string, 
              example: '0x707bb3...',
              description: 'Hash of the Ethereum transaction that performed the transfer.'
            },
            from_address: { 
              type: :string, 
              example: '0xfb833c...',
              description: 'Address of the sender in the transfer.'
            },
            to_address: { 
              type: :string, 
              example: '0x1f1edb...',
              description: 'Address of the recipient in the transfer.'
            },
            block_number: { 
              type: :integer, 
              example: 19619724, 
              description: 'Block number where the transfer was recorded.'
            },
            block_timestamp: { 
              type: :integer, 
              example: 1712685539, 
              description: 'Timestamp for when the block containing the transfer was mined.'
            },
            block_blockhash: { 
              type: :string, 
              example: '0x0204cb...',
              description: 'Hash of the block containing the transfer.'
            },
            event_log_index: { 
              type: :integer, 
              example: nil, 
              description: 'Index of the event log that recorded the transfer.',
              nullable: true
            },
            transfer_index: { 
              type: :string, 
              example: '51', 
              description: 'Index of the transfer in the transaction.'
            },
            transaction_index: { 
              type: :integer, 
              example: 95, 
              description: 'Transaction index within the block.'
            },
            enforced_previous_owner: { 
              type: :string, 
              example: nil, 
              description: 'Enforced previous owner of the ethscription, if applicable.',
              nullable: true
            }
          },
        },
        PaginationObject: {
          type: :object,
          properties: {
            page_key: { type: :string, example: '18680069-4-1', description: 'Key for the next page of results. Supply this in the page_key query parameter to retrieve the next set of items.' },
            has_more: { type: :boolean, example: true, description: 'Indicates if more items are available beyond the current page.' }
          },
          description: 'Contains pagination details to navigate through the list of records.'
        }
      },
      servers: [
        {
          url: 'https://api.ethscriptions.com/v2'
        }
      ]
    }
  }

  ethscription_object = config.openapi_specs['v1/swagger.yaml'][:components][:schemas][:Ethscription]
  ethscription_properties = ethscription_object[:properties]

  # Defining the additional property for transfers
  transfers_addition = {
    transfers: {
      type: :array,
      items: {
        '$ref': '#/components/schemas/EthscriptionTransfer'
      },
      description: 'Array of transfers associated with the ethscription.',
      example: [{"ethscription_transaction_hash"=>"0x4c5d41acd5de9db720897c1548d49422508e053a6ab6ea9c123b49d0c5322ce9",
        "transaction_hash"=>"0x707bb3f87c719516059c61cab02da680402e97ec5a88827fd00952b7d158894f",
        "from_address"=>"0xfb833cb7df301c045956eabd420691ea3e76b94f",
        "to_address"=>"0x1f1edbdb5d771db208437cfa6e8a3aeac13f544b",
        "block_number"=>"19619724",
        "block_timestamp"=>"1712685539",
        "block_blockhash"=>"0x0204cbc51acb8aae3bc55a5a3f7b26aa843c8b9e3593bc4e6ed21c931347fc23",
        "event_log_index"=>nil,
        "transfer_index"=>"51",
        "transaction_index"=>"95",
        "enforced_previous_owner"=>nil}]
    }
  }

  # Merge the original properties with the new addition
  updated_properties = ethscription_properties.merge(transfers_addition)

  # Create a new component schema that includes the updated properties
  ethscription_with_transfers_component = ethscription_object.merge({
    type: ethscription_object[:type],
    properties: updated_properties
  })

  # Add the new component to the OpenAPI specification
  config.openapi_specs['v1/swagger.yaml'][:components][:schemas][:EthscriptionWithTransfers] = ethscription_with_transfers_component
  
  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end

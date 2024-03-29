class TokenItem < ApplicationRecord
  include FacetRailsCommon::OrderQuery

  initialize_order_query({
    newest_first: [
      [:block_number, :desc],
      [:transaction_index, :desc, unique: true]
    ],
    oldest_first: [
      [:block_number, :asc],
      [:transaction_index, :asc, unique: true]
    ]
  }, page_key_attributes: [:ethscription_transaction_hash])
  
  belongs_to :ethscription,
    foreign_key: :ethscription_transaction_hash,
    primary_key: :transaction_hash,
    inverse_of: :token_item,
    optional: true
    
  belongs_to :token,
    foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :deploy_ethscription_transaction_hash,
    inverse_of: :token_items,
    optional: true
end

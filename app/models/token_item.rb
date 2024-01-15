class TokenItem < ApplicationRecord
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

class TokenState < ApplicationRecord
  belongs_to :token, foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :deploy_ethscription_transaction_hash, inverse_of: :token_states
end

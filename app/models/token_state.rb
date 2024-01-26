class TokenState < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :token_states
  
  belongs_to :token, foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :deploy_ethscription_transaction_hash, inverse_of: :token_states, optional: true
    
  scope :newest_first, -> { order(block_number: :desc) }
  scope :oldest_first, -> { order(block_number: :asc) }
end

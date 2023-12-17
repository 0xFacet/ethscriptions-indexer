class EthscriptionOwnershipVersion < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription_ownership_versions
  belongs_to :eth_transaction,
    foreign_key: :transaction_hash,
    primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_ownership_versions
  belongs_to :ethscription,
    foreign_key: :ethscription_transaction_hash,
    primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_ownership_versions
  
  scope :newest_first, -> { order(
    block_number: :desc,
    transaction_index: :desc,
    transfer_index: :desc
  )}
end
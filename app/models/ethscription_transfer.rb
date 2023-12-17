class EthscriptionTransfer < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription_transfers
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_transfers
  belongs_to :ethscription, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_transfers
    
  after_create :create_ownership_version!, :notify_eth_transaction
  
  def notify_eth_transaction
    if eth_transaction.transfer_index.nil?
      raise "Need eth_transaction.transfer_index"
    end
    
    eth_transaction.transfer_index += 1
  end
  
  def create_ownership_version!
    if is_valid_transfer?
      EthscriptionOwnershipVersion.create!(
        transaction_hash: transaction_hash,
        ethscription_transaction_hash: ethscription_transaction_hash,
        transfer_index: transfer_index,
        block_number: block_number,
        transaction_index: transaction_index,
        block_timestamp: block_timestamp,
        current_owner: to_address,
        previous_owner: from_address,
      )
    end
  end
  
  def is_valid_transfer?
    current_version = ethscription.current_ownership_version
    
    if current_version.nil?
      unless from_address == ethscription.creator &&
        to_address == ethscription.initial_owner
        raise "First transfer must be from creator to initial owner"
      end
      
      return true
    end
    
    current_owner = current_version.current_owner
    current_previous_owner = current_version.previous_owner
    
    return false unless current_owner == from_address
    
    if enforced_previous_owner
      return false unless current_previous_owner == enforced_previous_owner
    end
    
    true
  end
  
  def valid_transfers_of_ethscription
    transfers_to_use = ethscription.reload.ethscription_transfers
    
    sorted = transfers_to_use.sort_by do |transfer|
      [transfer.block_number, transfer.transaction_index, transfer.transfer_index]
    end
    
    sorted.each.with_object([]) do |transfer, valid|
      basic_rule_passes = valid.empty? ||
                          transfer.from == valid.last.to
  
      previous_owner_rule_passes = transfer.enforced_previous_owner.nil? ||
                                   transfer.enforced_previous_owner == valid.last&.from
  
      if basic_rule_passes && previous_owner_rule_passes
        valid << transfer
      end
    end
  end
end

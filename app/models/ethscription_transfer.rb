class EthscriptionTransfer < ApplicationRecord
  include OrderQuery
  order_query :newest_first,
    [:block_number, :desc],
    [:transaction_index, :desc],
    [:transfer_index, :desc, unique: true]
  
  order_query :oldest_first,
    [:block_number, :asc],
    [:transaction_index, :asc],
    [:transfer_index, :asc, unique: true]
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription_transfers
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_transfers
  belongs_to :ethscription, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, optional: true,
    inverse_of: :ethscription_transfers
    
  after_create :create_ownership_version!, :notify_eth_transaction
  
  def is_first_transfer?
    !EthscriptionTransfer.where.not(id: id).exists?(ethscription_transaction_hash: ethscription_transaction_hash)
  end
  
  def page_key
    [block_number, transaction_index, transfer_index].join("-")
  end
  
  def self.find_by_page_key(page_key)
    return if page_key.blank?
    
    block_number, transaction_index, transfer_index = page_key.split("-")
    
    find_by(
      block_number: block_number,
      transaction_index: transaction_index,
      transfer_index: transfer_index
    )
  end
  
  def notify_eth_transaction
    if eth_transaction.transfer_index.nil?
      raise "Need eth_transaction.transfer_index"
    end
    
    eth_transaction.transfer_index += 1
  end
  
  def create_if_valid!
    raise "Already created" if persisted?
    save! if is_valid_transfer?
  end
  
  def create_ownership_version!
    EthscriptionOwnershipVersion.create!(
      transaction_hash: transaction_hash,
      ethscription_transaction_hash: ethscription_transaction_hash,
      transfer_index: transfer_index,
      block_number: block_number,
      transaction_index: transaction_index,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      current_owner: to_address,
      previous_owner: from_address,
    )
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
end

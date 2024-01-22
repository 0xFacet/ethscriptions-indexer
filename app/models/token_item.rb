class TokenItem < ApplicationRecord
  include OrderQuery
  order_query :newest_first,
    [:block_number, :desc],
    [:transaction_index, :desc, unique: true]
  
  order_query :oldest_first,
    [:block_number, :asc],
    [:transaction_index, :asc, unique: true]
  
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
    
  def self.find_by_page_key(...)
    find_by_ethscription_transaction_hash(...)
  end
  
  def page_key
    ethscription_transaction_hash
  end
end

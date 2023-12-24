class CollectionItem < ApplicationRecord
  belongs_to :collection, touch: true
  belongs_to :ethscription,
    primary_key: 'transaction_hash',
    foreign_key: 'ethscription_transaction_hash',
    optional: true
  
  validate :item_attributes_is_array
  
  def item_attributes_is_array
    unless item_attributes.is_a?(Array)
      errors.add(:item_attributes, 'must be an array')
    end
  end
end

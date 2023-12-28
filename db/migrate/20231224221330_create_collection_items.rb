class CreateCollectionItems < ActiveRecord::Migration[7.1]
  def change
    create_table :collection_items do |t|
      t.bigint :collection_id, null: false
      t.string :ethscription_transaction_hash, null: false
      t.jsonb :item_attributes, null: false, default: {}
      t.string :name
      t.string :description
      t.string :external_url
      t.string :background_color
      t.integer :item_index
      
      t.index :item_index
      t.index [:item_index, :collection_id], unique: true
      t.index :collection_id
      t.index :ethscription_transaction_hash
      t.index [:collection_id, :ethscription_transaction_hash]

      t.foreign_key :collections,
        column: :collection_id,
        primary_key: :id,
        on_delete: :cascade
        
      t.foreign_key :ethscriptions,
        column: :ethscription_transaction_hash,
        primary_key: :transaction_hash
      
      t.timestamps
    end
  end
end

class CreateListingCancellations < ActiveRecord::Migration[7.1]
  def change
    create_table :listing_cancellations do |t|
      t.string :marketplace_address, null: false
      t.string :ethscription_transaction_hash
      t.string :listing_id
      t.string :seller, null: false
      t.bigint :cancellation_time
      t.string :eth_transaction_hash, null: false
      t.integer :cancellation_type, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.bigint :log_index, null: false

      t.index [:block_number, :log_index], unique: true
      t.index :block_number
      t.index :cancellation_type
      t.index :eth_transaction_hash
      t.index :ethscription_transaction_hash
      t.index :listing_id
      t.index [:marketplace_address, :seller]
      t.index :marketplace_address
  
      t.foreign_key :eth_transactions,
        column: :eth_transaction_hash,
        primary_key: :transaction_hash
      
      t.foreign_key :ethscriptions,
        column: :ethscription_transaction_hash,
        primary_key: :transaction_hash
        
      t.foreign_key :listings,
        column: :listing_id,
        primary_key: :listing_id
      
      t.check_constraint "seller ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "marketplace_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "NOT (ethscription_transaction_hash IS NOT NULL AND
        listing_id IS NOT NULL)"

      t.timestamps
    end
  end
end

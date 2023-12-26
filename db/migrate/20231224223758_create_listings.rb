class CreateListings < ActiveRecord::Migration[7.1]
  def change
    create_table :listings do |t|
      t.string :listing_id, null: false
      t.string :ethscription_transaction_hash, null: false
      t.string :seller, null: false
      t.decimal :price, null: false
      t.bigint :start_time, null: false
      t.bigint :end_time, null: false
      t.string :domain_name, null: false
      t.string :verifying_contract, null: false
      t.integer :chain_id, null: false
      t.string :domain_version, null: false
      t.text :signature, null: false

      t.index :ethscription_transaction_hash
      t.index :listing_id, unique: true
      t.index :seller
      t.index [:verifying_contract, :end_time]
      t.index [:verifying_contract, :seller]
      t.index [:verifying_contract, :start_time]
      
      t.foreign_key :ethscriptions,
        column: :ethscription_transaction_hash,
        primary_key: :transaction_hash
      
      t.check_constraint "ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "verifying_contract ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "seller ~ '^0x[a-f0-9]{40}$'"

      t.timestamps
    end
  end
end

class CreateEthscriptionTransfers < ActiveRecord::Migration[7.1]
  def change
    create_table :ethscription_transfers do |t|
      t.string :ethscription_transaction_hash, null: false
      t.string :transaction_hash, null: false
      t.string :from_address, null: false
      t.string :to_address, null: false
      t.bigint :block_number, null: false
      t.bigint :block_timestamp, null: false
      t.string :block_blockhash, null: false
      t.bigint :event_log_index
      t.bigint :transfer_index, null: false
      t.bigint :transaction_index, null: false
      t.string :enforced_previous_owner

      t.index :ethscription_transaction_hash
      t.index :block_number
      t.index :block_timestamp
      t.index :block_blockhash
      t.index :from_address
      t.index :to_address
      t.index [:transaction_hash, :event_log_index], unique: true
      t.index [:transaction_hash, :transfer_index], unique: true
      t.index [:block_number, :transaction_index, :event_log_index], unique: true
      t.index [:block_number, :transaction_index, :transfer_index], unique: true
      t.index :transaction_hash
      t.index :updated_at
      t.index :created_at
      
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "enforced_previous_owner ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"

      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      t.foreign_key :ethscriptions, column: :ethscription_transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_transactions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      
      t.timestamps
    end
  end
end

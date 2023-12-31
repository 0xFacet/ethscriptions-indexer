class CreateEthTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_transactions do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :block_timestamp, null: false
      t.string :block_blockhash, null: false
      t.string :from_address, null: false
      t.string :to_address
      t.text :input, null: false
      t.bigint :transaction_index, null: false
      t.integer :status
      t.jsonb :logs, default: [], null: false
      t.string :created_contract_address
      t.numeric :gas_price, null: false
      t.bigint :gas_used, null: false
      t.numeric :transaction_fee, null: false
      t.numeric :value, null: false

      t.index [:block_number, :transaction_index], unique: true
      t.index :block_number
      t.index :block_timestamp
      t.index :block_blockhash
      t.index :from_address
      t.index :status
      t.index :to_address
      t.index :transaction_hash, unique: true
      t.index :logs, using: :gin
      t.index :updated_at
      t.index :created_at
      
      t.check_constraint "block_number <= 4370000 AND status IS NULL OR block_number > 4370000 AND status = 1", name: "status_check"
      t.check_constraint "created_contract_address IS NULL AND to_address IS NOT NULL OR
        created_contract_address IS NOT NULL AND to_address IS NULL", name: "contract_to_check"
        
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "created_contract_address ~ '^0x[a-f0-9]{40}$'"

      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
  end
end

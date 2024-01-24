class CreateTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :tokens do |t|
      t.string :deploy_ethscription_transaction_hash, null: false
      t.bigint :deploy_block_number, null: false
      t.bigint :deploy_transaction_index, null: false
      t.string :protocol, null: false, limit: 1000
      t.string :tick, null: false, limit: 1000
      t.bigint :max_supply, null: false
      t.bigint :total_supply, null: false
      t.bigint :mint_amount, null: false
      t.jsonb :balances_observations, null: false, default: []
      
      t.index :deploy_ethscription_transaction_hash, unique: true
      t.index [:protocol, :tick], unique: true
      t.index [:deploy_block_number, :deploy_transaction_index], unique: true
      
      t.check_constraint "protocol ~ '^[a-z0-9\-]+$'"
      t.check_constraint "tick ~ '^[[:alnum:]\p{Emoji_Presentation}]+$'"
      t.check_constraint 'max_supply > 0'
      t.check_constraint 'total_supply >= 0'
      t.check_constraint 'total_supply <= max_supply'
      t.check_constraint 'mint_amount > 0'
      t.check_constraint 'max_supply % mint_amount = 0'
      t.check_constraint "deploy_ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :ethscriptions,
        column: :deploy_ethscription_transaction_hash,
        primary_key: :transaction_hash,
        on_delete: :cascade
      
      t.timestamps
    end
  end
end

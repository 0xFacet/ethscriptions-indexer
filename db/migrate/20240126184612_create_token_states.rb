class CreateTokenStates < ActiveRecord::Migration[7.1]
  def up
    rename_column :tokens, :balances_snapshot, :balances
    
    change_column_default :tokens, :total_supply, from: nil, to: 0
    
    execute <<-SQL
      DROP TRIGGER IF EXISTS update_total_supply_trigger ON token_items;
      DROP FUNCTION IF EXISTS update_total_supply;
    SQL
    
    create_table :token_states do |t|
      t.bigint :block_number, null: false
      
      t.string :transaction_hash, null: false
      t.bigint :transaction_index, null: false
      t.bigint :transfer_index, null: false

      t.bigint :block_timestamp, null: false
      t.string :block_blockhash, null: false

      t.string :deploy_ethscription_transaction_hash, null: false
      
      t.jsonb :balances, null: false, default: {}
      t.bigint :total_supply, null: false
      
      t.index :deploy_ethscription_transaction_hash
      t.index [:transaction_hash, :transfer_index], unique: true
      t.index [:block_number, :transaction_index, :transfer_index], unique: true
      
      t.check_constraint "deploy_ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      t.foreign_key :tokens, column: :deploy_ethscription_transaction_hash, primary_key: :deploy_ethscription_transaction_hash, on_delete: :cascade
      t.foreign_key :eth_transactions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_token_balances_and_supply() RETURNS TRIGGER AS $$
      DECLARE
        latest_token_state RECORD;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          SELECT INTO latest_token_state *
          FROM token_states
          WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash
          ORDER BY block_number DESC, transaction_index DESC, transfer_index DESC
          LIMIT 1;

          UPDATE tokens
          SET balances = COALESCE(latest_token_state.balances, '{}'::jsonb),
              total_supply = COALESCE(latest_token_state.total_supply, 0),
              updated_at = NOW()
          WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash;
        ELSIF TG_OP = 'DELETE' THEN
          SELECT INTO latest_token_state *
          FROM token_states
          WHERE deploy_ethscription_transaction_hash = OLD.deploy_ethscription_transaction_hash
            AND id != OLD.id
          ORDER BY block_number DESC, transaction_index DESC, transfer_index DESC
          LIMIT 1;

          UPDATE tokens
          SET balances = COALESCE(latest_token_state.balances, '{}'::jsonb),
              total_supply = COALESCE(latest_token_state.total_supply, 0),
              updated_at = NOW()
          WHERE deploy_ethscription_transaction_hash = OLD.deploy_ethscription_transaction_hash;
        END IF;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER update_token_balances_and_supply
      AFTER INSERT OR DELETE ON token_states
      FOR EACH ROW EXECUTE PROCEDURE update_token_balances_and_supply();
    SQL
  end
  
  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS update_token_balances_and_supply ON token_states;
      DROP FUNCTION IF EXISTS update_token_balances_and_supply;
    SQL
    
    drop_table :token_states

    rename_column :tokens, :balances, :balances_snapshot
    
    change_column_default :tokens, :total_supply, from: 0, to: nil

    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_total_supply() RETURNS TRIGGER AS $$
      BEGIN
        UPDATE tokens
        SET total_supply = (
          SELECT COUNT(*) * mint_amount
          FROM token_items
          WHERE deploy_ethscription_transaction_hash = OLD.deploy_ethscription_transaction_hash
        )
        WHERE deploy_ethscription_transaction_hash = OLD.deploy_ethscription_transaction_hash;

        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER update_total_supply_trigger
      AFTER DELETE ON token_items
      FOR EACH ROW EXECUTE PROCEDURE update_total_supply();
    SQL
  end
end

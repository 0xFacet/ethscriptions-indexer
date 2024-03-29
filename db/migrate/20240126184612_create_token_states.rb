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
      t.bigint :block_timestamp, null: false
      t.string :block_blockhash, null: false

      t.string :deploy_ethscription_transaction_hash, null: false
      
      t.jsonb :balances, null: false, default: {}
      t.bigint :total_supply, null: false, default: 0
      
      t.index :deploy_ethscription_transaction_hash
      t.index [:block_number, :deploy_ethscription_transaction_hash], unique: true
      
      t.check_constraint "deploy_ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      t.foreign_key :tokens, column: :deploy_ethscription_transaction_hash, primary_key: :deploy_ethscription_transaction_hash, on_delete: :cascade
      
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
          ORDER BY block_number DESC
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
          ORDER BY block_number DESC
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
    
    Token.find_each do |token|
      token.sync_past_token_items!
      token.save_state_checkpoint!
    end
    
    drop_table :delayed_jobs
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
    
    create_table :delayed_jobs do |table|
      table.integer :priority, default: 0, null: false # Allows some jobs to jump to the front of the queue
      table.integer :attempts, default: 0, null: false # Provides for retries, but still fail eventually.
      table.text :handler,                 null: false # YAML-encoded string of the object that will do work
      table.text :last_error                           # reason for last failure (See Note below)
      table.datetime :run_at                           # When to run. Could be Time.zone.now for immediately, or sometime in the future.
      table.datetime :locked_at                        # Set when a client is working on this object
      table.datetime :failed_at                        # Set when all retries have failed (actually, by default, the record is deleted instead)
      table.string :locked_by                          # Who is working on this object (if locked)
      table.string :queue                              # The name of the queue this job is in
      table.timestamps null: true
    end

    add_index :delayed_jobs, [:priority, :run_at], name: "delayed_jobs_priority"
  end
end

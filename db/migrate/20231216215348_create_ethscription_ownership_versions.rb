class CreateEthscriptionOwnershipVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :ethscription_ownership_versions do |t|
      t.string :transaction_hash, null: false
      t.string :ethscription_transaction_hash, null: false
      t.bigint :transfer_index, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.bigint :block_timestamp, null: false
      
      t.string :current_owner, null: false
      t.string :previous_owner, null: false
      
      t.index :current_owner
      t.index :previous_owner
      t.index [:current_owner, :previous_owner]
      t.index :ethscription_transaction_hash
      t.index :transaction_hash
      t.index :block_number
      t.index [:transaction_hash, :transfer_index], unique: true
      t.index [:block_number, :transaction_index, :transfer_index], unique: true
      t.index [:ethscription_transaction_hash, :block_number, :transaction_index, :transfer_index], unique: true
      t.index :updated_at
      t.index :created_at
      
      t.check_constraint "ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "current_owner ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "previous_owner ~ '^0x[a-f0-9]{40}$'"
      
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      t.foreign_key :ethscriptions, column: :ethscription_transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_transactions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      
      t.timestamps
    end
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
          CREATE OR REPLACE FUNCTION update_current_owner() RETURNS TRIGGER AS $$
          DECLARE
            latest_ownership_version RECORD;
          BEGIN
            IF TG_OP = 'INSERT' THEN
              SELECT INTO latest_ownership_version *
              FROM ethscription_ownership_versions
              WHERE ethscription_transaction_hash = NEW.ethscription_transaction_hash
              ORDER BY block_number DESC, transaction_index DESC
              LIMIT 1;

              UPDATE ethscriptions
              SET current_owner = latest_ownership_version.current_owner,
                  previous_owner = latest_ownership_version.previous_owner,
                  updated_at = NOW()
              WHERE transaction_hash = NEW.ethscription_transaction_hash;
            ELSIF TG_OP = 'DELETE' THEN
              SELECT INTO latest_ownership_version *
              FROM ethscription_ownership_versions
              WHERE ethscription_transaction_hash = OLD.ethscription_transaction_hash
                AND id != OLD.id
              ORDER BY block_number DESC, transaction_index DESC
              LIMIT 1;

              UPDATE ethscriptions
              SET current_owner = latest_ownership_version.current_owner,
                  previous_owner = latest_ownership_version.previous_owner,
                  updated_at = NOW()
              WHERE transaction_hash = OLD.ethscription_transaction_hash;
            END IF;

            RETURN NULL; -- result is ignored since this is an AFTER trigger
          END;
          $$ LANGUAGE plpgsql;
          
          CREATE TRIGGER update_current_owner
          AFTER INSERT OR DELETE ON ethscription_ownership_versions
          FOR EACH ROW EXECUTE PROCEDURE update_current_owner();
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS update_current_owner ON ethscription_ownership_versions;
          DROP FUNCTION IF EXISTS update_current_owner();
        SQL
      end
    end
  end
end

class CreateEthscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :ethscriptions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.bigint :block_timestamp, null: false
      t.bigint :event_log_index
      
      t.bigint :ethscription_number, null: false
      t.string :creator, null: false
      t.string :initial_owner, null: false
      t.string :current_owner, null: false
      t.string :previous_owner, null: false

      t.text :content_uri, null: false
      t.string :content_sha, null: false
      t.boolean :esip6, null: false
      t.string :mimetype, null: false
      t.string :media_type, null: false
      t.string :mime_subtype, null: false
      
      t.numeric :gas_price, null: false
      t.bigint :gas_used, null: false
      t.numeric :transaction_fee, null: false
      t.numeric :value, null: false
      
      t.index [:block_number, :transaction_index], unique: true
      t.index :transaction_hash, unique: true
      t.index [:block_number, :transaction_index, :content_sha]
      t.index :block_number
      t.index :block_timestamp
      t.index :creator
      t.index :current_owner
      t.index :ethscription_number, unique: true
      t.index :content_sha
      t.index :content_sha, unique: true, where: "(esip6 = false)",
        name: :index_ethscriptions_on_content_sha_unique
      t.index :initial_owner
      t.index :media_type
      t.index :mime_subtype
      t.index :mimetype
      t.index :previous_owner
      t.index :transaction_index
      t.index :esip6
      
      t.check_constraint "content_sha ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "creator ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "current_owner ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "initial_owner ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "previous_owner ~ '^0x[a-f0-9]{40}$'"
    
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      t.foreign_key :eth_transactions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      
      t.timestamps
    end
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
          DROP TRIGGER IF EXISTS trigger_check_ethscription_order ON ethscriptions;
          DROP FUNCTION IF EXISTS check_ethscription_order();

          CREATE OR REPLACE FUNCTION check_ethscription_order_and_sequence()
          RETURNS TRIGGER AS $$
          BEGIN
            IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR
            (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
              RAISE EXCEPTION 'Ethscriptions must be created in order';
            END IF;
            NEW.ethscription_number := (SELECT COALESCE(MAX(ethscription_number), -1) + 1 FROM ethscriptions);
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER trigger_check_ethscription_order_and_sequence
          BEFORE INSERT ON ethscriptions
          FOR EACH ROW EXECUTE FUNCTION check_ethscription_order_and_sequence();
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS trigger_check_ethscription_order_and_sequence ON ethscriptions;
          DROP FUNCTION IF EXISTS check_ethscription_order_and_sequence();
        SQL
      end
    end
  end
end

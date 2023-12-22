class CreateEthBlocks < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :eth_blocks, force: :cascade do |t|
      t.bigint :block_number, null: false
      t.bigint :timestamp, null: false
      t.string :blockhash, null: false
      t.string :parent_blockhash, null: false
      t.datetime :imported_at
      t.string :state_hash
      t.string :parent_state_hash
      
      t.boolean :is_genesis_block, null: false
      
      t.index :block_number, unique: true
      t.index :blockhash, unique: true
      t.index :imported_at
      t.index [:imported_at, :block_number]
      t.index :parent_blockhash, unique: true
      t.index :state_hash, unique: true
      t.index :parent_state_hash, unique: true
      t.index :timestamp
    
      t.check_constraint "blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "parent_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "state_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "parent_state_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.timestamps
    end
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
          CREATE OR REPLACE FUNCTION check_block_order()
          RETURNS TRIGGER AS $$
          BEGIN
            IF NEW.is_genesis_block = false AND 
              NEW.block_number <> (SELECT MAX(block_number) + 1 FROM eth_blocks) THEN
              RAISE EXCEPTION 'Block number is not sequential';
            END IF;

            IF NEW.is_genesis_block = false AND 
              NEW.parent_blockhash <> (SELECT blockhash FROM eth_blocks WHERE block_number = NEW.block_number - 1) THEN
              RAISE EXCEPTION 'Parent block hash does not match the parent''s block hash';
            END IF;

            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER trigger_check_block_order
          BEFORE INSERT ON eth_blocks
          FOR EACH ROW EXECUTE FUNCTION check_block_order();
        SQL
        
        execute <<~SQL
          CREATE OR REPLACE FUNCTION check_block_order_on_update()
          RETURNS TRIGGER AS $$
          BEGIN
            IF NEW.imported_at IS NOT NULL AND NEW.state_hash IS NULL THEN
              RAISE EXCEPTION 'state_hash must be set when imported_at is set';
            END IF;
          
            IF NEW.is_genesis_block = false AND 
              NEW.parent_state_hash <> (SELECT state_hash FROM eth_blocks WHERE block_number = NEW.block_number - 1 AND imported_at IS NOT NULL) THEN
              RAISE EXCEPTION 'Parent state hash does not match the state hash of the previous block';
            END IF;
          
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;
          
          CREATE TRIGGER trigger_check_block_order_on_update
          BEFORE UPDATE OF imported_at ON eth_blocks
          FOR EACH ROW WHEN (NEW.imported_at IS NOT NULL)
          EXECUTE FUNCTION check_block_order_on_update();
        SQL
        
        execute <<-SQL
          CREATE OR REPLACE FUNCTION delete_later_blocks()
          RETURNS TRIGGER AS $$
          BEGIN
            DELETE FROM eth_blocks WHERE block_number > OLD.block_number;
            RETURN OLD;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER trigger_delete_later_blocks
          AFTER DELETE ON eth_blocks
          FOR EACH ROW EXECUTE FUNCTION delete_later_blocks();
        SQL
        
        execute <<-SQL
          CREATE OR REPLACE FUNCTION check_block_imported_at()
          RETURNS TRIGGER AS $$
          BEGIN
            IF NEW.imported_at IS NOT NULL THEN
              IF EXISTS (
                SELECT 1
                FROM eth_blocks
                WHERE block_number < NEW.block_number
                  AND imported_at IS NULL
                LIMIT 1
              ) THEN
                RAISE EXCEPTION 'Previous block not yet imported';
              END IF;
            END IF;
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER check_block_imported_at_trigger
          BEFORE UPDATE OF imported_at ON eth_blocks
          FOR EACH ROW EXECUTE FUNCTION check_block_imported_at();
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS trigger_check_block_order ON eth_blocks;
          DROP FUNCTION IF EXISTS check_block_order();
          
          DROP TRIGGER IF EXISTS trigger_delete_later_blocks ON eth_blocks;
          DROP FUNCTION IF EXISTS delete_later_blocks();
          
          DROP TRIGGER IF EXISTS check_block_imported_at_trigger ON eth_blocks;
          DROP FUNCTION IF EXISTS check_block_imported_at();      
        SQL
      end
    end
  end
end

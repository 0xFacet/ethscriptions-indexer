class UpdateCheckBlockOrderOnUpdateTrigger < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL
      DROP TRIGGER IF EXISTS trigger_check_block_order_on_update ON eth_blocks;
      
      CREATE OR REPLACE FUNCTION check_block_order_on_update()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.imported_at IS NOT NULL AND NEW.state_hash IS NULL THEN
          RAISE EXCEPTION 'state_hash must be set when imported_at is set';
        END IF;
      
        IF (SELECT MAX(block_number) FROM eth_blocks) IS NOT NULL THEN
          IF NEW.parent_state_hash <> (SELECT state_hash FROM eth_blocks WHERE block_number = (SELECT MAX(block_number) FROM eth_blocks WHERE block_number < NEW.block_number) AND imported_at IS NOT NULL) THEN
            RAISE EXCEPTION 'Parent state hash does not match the state hash of the previous block';
          END IF;
        END IF;
      
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER trigger_check_block_order_on_update
      BEFORE UPDATE OF imported_at ON eth_blocks
      FOR EACH ROW WHEN (NEW.imported_at IS NOT NULL)
      EXECUTE FUNCTION check_block_order_on_update();
    SQL
  end

  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS trigger_check_block_order_on_update ON eth_blocks;

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
  end
end
class CreateTokenItems < ActiveRecord::Migration[7.1]
  def up
    create_table :token_items do |t|
      t.string :ethscription_transaction_hash, null: false
      t.string :deploy_ethscription_transaction_hash, null: false
      t.bigint :token_item_id, null: false
      
      t.foreign_key :ethscriptions,
        column: :ethscription_transaction_hash,
        primary_key: :transaction_hash,
        on_delete: :cascade
      
      t.foreign_key :tokens,
        column: :deploy_ethscription_transaction_hash,
        primary_key: :deploy_ethscription_transaction_hash,
        on_delete: :cascade
      
      t.index :ethscription_transaction_hash, unique: true
      t.index [:deploy_ethscription_transaction_hash, :token_item_id], unique: true
      t.index [:ethscription_transaction_hash, :deploy_ethscription_transaction_hash, :token_item_id], unique: true
      
      t.check_constraint 'token_item_id > 0'
      t.check_constraint "deploy_ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "ethscription_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_total_supply() RETURNS TRIGGER AS $$
      BEGIN
        UPDATE tokens
        SET total_supply = (
          SELECT COUNT(*) * mint_amount
          FROM token_items
          WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash
        )
        WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER update_total_supply_trigger
      AFTER DELETE ON token_items
      FOR EACH ROW EXECUTE PROCEDURE update_total_supply();
    SQL
  end
  
  def down
    drop_table :token_items
  end
end

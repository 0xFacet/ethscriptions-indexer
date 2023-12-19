class SetEthscriptionNumbersNonNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ethscriptions, :ethscription_number, false

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
            IF NEW.ethscription_number != (SELECT COALESCE(MAX(ethscription_number), -1) + 1 FROM ethscriptions) THEN
              RAISE EXCEPTION 'Ethscription numbers must be added in sequence';
            END IF;
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
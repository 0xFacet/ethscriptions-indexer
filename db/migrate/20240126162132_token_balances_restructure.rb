class TokenBalancesRestructure < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL
      ALTER TABLE tokens
      ADD COLUMN balances_snapshot jsonb NOT NULL DEFAULT '{}';
    SQL

    execute <<-SQL
      UPDATE tokens
      SET balances_snapshot = COALESCE(balances_observations->0, '{}');
    SQL

    execute <<-SQL
      ALTER TABLE tokens
      DROP COLUMN balances_observations;
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE tokens
      ADD COLUMN balances_observations jsonb NOT NULL DEFAULT '[]';
    SQL

    execute <<-SQL
      UPDATE tokens
      SET balances_observations = jsonb_build_array(balances_snapshot);
    SQL

    execute <<-SQL
      ALTER TABLE tokens
      DROP COLUMN balances_snapshot;
    SQL
  end
end

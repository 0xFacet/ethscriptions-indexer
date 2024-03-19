class CreateEthscriptionAttachmentCleanupTrigger < ActiveRecord::Migration[7.1]
  def up
    # Create a function that will be called by the trigger
    execute <<-SQL
      CREATE OR REPLACE FUNCTION clean_up_ethscription_attachments()
      RETURNS TRIGGER AS $$
      BEGIN
        -- Only proceed if the ethscription being deleted has an attachment_sha
        IF OLD.attachment_sha IS NOT NULL THEN
          -- Check if there is another ethscription with the same attachment_sha
          IF NOT EXISTS (
            SELECT 1 FROM ethscriptions
            WHERE attachment_sha = OLD.attachment_sha
            AND id != OLD.id
          ) THEN
            -- If no other ethscription has the same attachment_sha, delete associated attachments
            DELETE FROM ethscription_attachments
            WHERE sha = OLD.attachment_sha;
          END IF;
        END IF;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    # Create the trigger
    execute <<-SQL
      CREATE TRIGGER ethscription_cleanup
      AFTER DELETE ON ethscriptions
      FOR EACH ROW EXECUTE FUNCTION clean_up_ethscription_attachments();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS ethscription_cleanup ON ethscriptions;"
    execute "DROP FUNCTION IF EXISTS clean_up_ethscription_attachments();"
  end
end

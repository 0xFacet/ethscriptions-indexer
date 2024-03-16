class AddAttachmentAndBlobColumns < ActiveRecord::Migration[7.1]
  def change
    # Should always be set when available which is starting after Duncun
    add_column :eth_blocks, :parent_beacon_block_root, :string
    add_check_constraint :eth_blocks, "parent_beacon_block_root ~ '^0x[a-f0-9]{64}$'"
    
    add_column :eth_blocks, :blob_sidecars, :jsonb, default: [], null: false
    
    add_column :eth_transactions, :blob_versioned_hashes, :jsonb, default: [], null: false
    
    add_column :ethscriptions, :attachment_uri, :text
    add_column :ethscriptions, :attachment_sha, :string
    add_index :ethscriptions, :attachment_sha
    
    add_check_constraint :ethscriptions, "attachment_sha ~ '^0x[a-f0-9]{64}$'"
    add_check_constraint :ethscriptions, "attachment_uri IS NULL OR attachment_sha IS NOT NULL"
  end
end

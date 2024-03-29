class AddAttachmentAndBlobColumns < ActiveRecord::Migration[7.1]
  def change
    # Should always be set when available which is starting after Duncun
    add_column :eth_blocks, :parent_beacon_block_root, :string
    add_check_constraint :eth_blocks, "parent_beacon_block_root ~ '^0x[a-f0-9]{64}$'"
    
    add_column :eth_blocks, :blob_sidecars, :jsonb, default: [], null: false
    
    add_column :eth_transactions, :blob_versioned_hashes, :jsonb, default: [], null: false
    
    add_column :ethscriptions, :attachment_sha, :string
    add_index :ethscriptions, :attachment_sha
    
    add_column :ethscriptions, :attachment_content_type, :string,
      limit: EthscriptionAttachment::MAX_CONTENT_TYPE_LENGTH
    add_index :ethscriptions, :attachment_content_type
    
    add_check_constraint :ethscriptions, "attachment_sha ~ '^0x[a-f0-9]{64}$'"
    
    create_table :ethscription_attachments do |t|
      t.binary :content, null: false
      t.string :content_type, null: false
      t.string :sha, null: false
      t.bigint :size, null: false
      
      t.index :sha, unique: true
      t.index :content_type
      t.index :size
      
      t.check_constraint "sha ~ '^0x[a-f0-9]{64}$'"
      
      t.timestamps
    end
  end
end

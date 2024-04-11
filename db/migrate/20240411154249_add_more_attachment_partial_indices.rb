class AddMoreAttachmentPartialIndices < ActiveRecord::Migration[7.1]
  def change
    add_index :ethscriptions, [:attachment_sha, :block_number, :transaction_index],
      name: 'index_ethscriptions_on_sha_blocknum_txindex_desc',
      order: { block_number: :desc, transaction_index: :desc }

    add_index :ethscriptions, [:attachment_sha, :block_number, :transaction_index],
      name: 'index_ethscriptions_on_sha_blocknum_txindex_asc',
      order: { block_number: :asc, transaction_index: :asc }
      
    add_index :ethscriptions, [:block_number, :transaction_index],
      where: "attachment_sha IS NOT NULL",
      name: 'inx_ethscriptions_on_blk_num_tx_index_with_att_not_null_asc',
      order: { block_number: :asc, transaction_index: :asc }
  end
end

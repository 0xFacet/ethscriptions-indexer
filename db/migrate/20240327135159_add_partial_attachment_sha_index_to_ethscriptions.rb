class AddPartialAttachmentShaIndexToEthscriptions < ActiveRecord::Migration[7.1]
  def change
    add_index :ethscriptions, [:block_number, :transaction_index],
      where: "attachment_sha IS NOT NULL",
      name: 'inx_ethscriptions_on_blk_num_tx_index_with_attachment_not_null'
      
    add_index :ethscriptions, :attachment_sha, where: "attachment_sha IS NOT NULL",
      name: 'index_ethscriptions_on_attachment_sha_not_null'
  end
end

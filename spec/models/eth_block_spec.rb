require 'rails_helper'

class OldEthBlock
  def self.sorted_blocknumbers_within_purview
    current_block_number = EthBlock.genesis_blocks.max + 100_000

    largest_genesis_block = EthBlock.genesis_blocks.max

    full_block_range = (largest_genesis_block..current_block_number).to_a

    (EthBlock.genesis_blocks + full_block_range).sort
  end

  def self.next_block_to_import
    no_records = sorted_blocknumbers_within_purview - EthBlock.pluck(:block_number)

    records_but_not_imported = EthBlock.where(imported_at: nil).pluck(:block_number)

    (no_records + records_but_not_imported).min
  end
end

RSpec.describe EthBlock, type: :model do
  def create_eth_block(block_number)
    prev_block = EthBlock.find_by(block_number: block_number - 1)
    parent_blockhash = prev_block&.blockhash || "0x" + SecureRandom.hex(32)
    
    EthBlock.create!(
      block_number: block_number,
      imported_at: Time.now,
      blockhash: "0x" + SecureRandom.hex(32),
      parent_blockhash: parent_blockhash,
      timestamp: Time.zone.now,
      is_genesis_block: EthBlock.genesis_blocks.include?(block_number)
    )
  end
  
  describe '.next_block_to_import' do
    context 'no records at all' do
      it 'returns the same block as the old method' do
        expect(EthBlock.next_block_to_import).to eq(OldEthBlock.next_block_to_import)
      end
    end

    context 'all genesis blocks imported but nothing more' do
      before do
        EthBlock.genesis_blocks.each do |block_number|
          create_eth_block(block_number)
        end
      end

      it 'returns the same block as the old method' do
        expect(EthBlock.next_block_to_import).to eq(OldEthBlock.next_block_to_import)
      end
    end

    context 'midway through importing genesis blocks' do
      before do
        midway_index = EthBlock.genesis_blocks.length / 2
        EthBlock.genesis_blocks[0...midway_index].each do |block_number|
          create_eth_block(block_number)
        end
      end

      it 'returns the same block as the old method' do
        expect(EthBlock.next_block_to_import).to eq(OldEthBlock.next_block_to_import)
      end
    end

    context 'completed importing all genesis blocks, and started importing subsequent blocks' do
      before do
        EthBlock.genesis_blocks.each do |block_number|
          create_eth_block(block_number)
        end

        next_block = EthBlock.genesis_blocks.max + 1
        create_eth_block(next_block)
      end

      it 'returns the same block as the old method' do
        expect(EthBlock.next_block_to_import).to eq(OldEthBlock.next_block_to_import)
      end
    end

    it 'consistently returns the same block number for both old and new methods' do
      100.times do |i|
        expect(OldEthBlock.next_block_to_import).to eq(EthBlock.next_block_to_import)
    
        next_block = EthBlock.next_block_to_import
        create_eth_block(next_block)
      end
    end    
  end
end

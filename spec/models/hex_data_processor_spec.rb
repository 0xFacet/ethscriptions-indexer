require 'rails_helper'

RSpec.describe HexDataProcessor do
  describe '.hex_to_utf8' do
    context 'with non-compressed data' do
      it 'converts hex to utf-8 string correctly' do
        hex_string = "68656c6c6f" # 'hello' in hex
        expect(HexDataProcessor.hex_to_utf8(hex_string, support_gzip: true)).to eq("hello")
      end
    end

    context 'with valid compressed data' do
      it 'decompresses and converts hex to utf-8 string correctly' do
        original_text = "hello" * 20 # Simple text to compress
        compressed_data = Zlib.gzip(original_text)
        hex_string = compressed_data.unpack1('H*')
        expect(HexDataProcessor.hex_to_utf8(hex_string, support_gzip: true)).to eq(original_text)
      end
    end

    context 'with invalid compressed data' do
      it 'returns nil for corrupted compressed data' do
        invalid_compressed_hex = "1f8b0800000000000003666f6f626172" # Altered gzip header, likely invalid
        expect(HexDataProcessor.hex_to_utf8(invalid_compressed_hex, support_gzip: true)).to be_nil
      end
    end

    context 'with compressed data exceeding the size limit' do
      it 'returns nil if decompressed data exceeds 5x the compressed size' do
        large_text = "a" * 50000 # Create a large text to compress
        compressed_data = Zlib.gzip(large_text)
        hex_string = compressed_data.unpack1('H*')
        # Assuming the compression doesn't reduce the size to below 1/5th (adjust as necessary)
        expect(HexDataProcessor.hex_to_utf8(hex_string, support_gzip: true)).to be_nil
      end
    end
  end
end

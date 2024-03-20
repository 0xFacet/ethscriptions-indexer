require 'rails_helper'

RSpec.describe BlobUtils do
  let(:blob_data) { "we are all gonna make it" }

  describe '.to_blobs' do
    context 'with valid data' do
      it 'converts data to blobs and back correctly in hex format' do
        input = blob_data.bytes.pack('C*')
        
        blobs = described_class.to_blobs(data: input)
        described_class.from_blobs(blobs: blobs)
        
        expect(described_class.from_blobs(blobs: blobs)).to eq(input)
      end
    end

    context 'when data is empty' do
      it 'raises an EmptyBlobError' do
        expect { described_class.to_blobs(data: '') }.to raise_error(BlobUtils::EmptyBlobError)
      end
    end

    context 'when data is too big' do
      it 'raises a BlobSizeTooLargeError' do
        large_data = 'we are all gonna make it' * 20000
        expect { described_class.to_blobs(data: large_data) }.to raise_error(BlobUtils::BlobSizeTooLargeError)
      end
    end
  end
end

require 'rails_helper'

RSpec.describe EthscriptionAttachment do
  describe '.from_cbor' do
    context 'with valid CBOR data' do
      it 'creates a new EthscriptionAttachment with decoded data' do
        cbor_encoded_data = CBOR.encode({ 'content' => 'test content', 'contentType' => 'text/plain' })
        attachment = EthscriptionAttachment.from_cbor(cbor_encoded_data)
        expect(attachment.content).to eq('test content')
        expect(attachment.content_type).to eq('text/plain')
        expect(attachment.size).to eq('test content'.bytesize)
        expect(attachment.sha).to eq(attachment.calculate_sha)
      end
    end
  
    context 'with invalid CBOR data' do
      it 'raises an InvalidInputError' do
        expect {
          EthscriptionAttachment.from_cbor("not a cbor")
        }.to raise_error(EthscriptionAttachment::InvalidInputError)
      end
      it 'raises an InvalidInputError for non-hash input' do
        attachment = EthscriptionAttachment.new
        expect {
          attachment.decoded_data = "string"
        }.to raise_error(EthscriptionAttachment::InvalidInputError)
      end
    end
  end
  
  describe '#content_type_with_encoding' do
    it 'appends charset=UTF-8 for text types without a charset' do
      attachment = EthscriptionAttachment.new(content_type: 'text/plain')
      expect(attachment.content_type_with_encoding).to eq('text/plain; charset=UTF-8')
    end
  
    it 'does not modify content_type that already has a charset' do
      attachment = EthscriptionAttachment.new(content_type: 'text/plain; charset=UTF-16')
      expect(attachment.content_type_with_encoding).to eq('text/plain; charset=UTF-16')
    end
  end
  
  describe '#decoded_data=' do
    let(:attachment) { EthscriptionAttachment.new }
  
    context 'when decoded_data is missing the content key' do
      it 'raises an InvalidInputError' do
        expect {
          attachment.decoded_data = { 'contentType' => 'text/plain' }
        }.to raise_error(EthscriptionAttachment::InvalidInputError, /Expected keys to be 'content' and 'contentType'/)
      end
    end
  
    context 'when decoded_data is missing the content_type key' do
      it 'raises an InvalidInputError' do
        expect {
          attachment.decoded_data = { 'content' => 'test content' }
        }.to raise_error(EthscriptionAttachment::InvalidInputError, /Expected keys to be 'content' and 'contentType'/)
      end
    end
    
    context 'when content is not a string' do
      it 'raises an InvalidInputError' do
        expect {
          attachment.decoded_data = { 'content' => 123, 'contentType' => 'text/plain' }
        }.to raise_error(EthscriptionAttachment::InvalidInputError, /Invalid value type/)
      end
    end
  
    context 'when content_type is not a string' do
      it 'raises an InvalidInputError' do
        expect {
          attachment.decoded_data = { 'content' => 'test content', 'contentType' => 123 }
        }.to raise_error(EthscriptionAttachment::InvalidInputError, /Invalid value type/)
      end
    end
  end
  
  describe '.ungzip_if_necessary!' do
    context 'with gzipped data' do
      it 'correctly decompresses the data' do
        original_text = "This is a test string."
        gzipped_text = Zlib.gzip(original_text)
        
        expect(EthscriptionAttachment.ungzip_if_necessary!(gzipped_text)).to eq(original_text)
      end
    end
  
    context 'with non-gzipped data' do
      it 'returns the original data' do
        non_gzipped_text = "This is a test string."
        
        expect(EthscriptionAttachment.ungzip_if_necessary!(non_gzipped_text)).to eq(non_gzipped_text)
      end
    end
  
    context 'with invalid gzipped data' do
      it 'raises an InvalidInputError' do
        invalid_gzipped_text = ["1f8b08a0000000000003666f6f626172"].pack("H*") # Altered gzip header, likely invalid
        
        expect {
          EthscriptionAttachment.ungzip_if_necessary!(invalid_gzipped_text)
        }.to raise_error(EthscriptionAttachment::InvalidInputError, /Failed to decompress content/)
      end
    end
  end
end

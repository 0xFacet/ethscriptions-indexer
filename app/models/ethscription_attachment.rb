class EthscriptionAttachment < ApplicationRecord
  class InvalidInputError < StandardError; end
  
  has_many :ethscriptions,
    foreign_key: :attachment_sha,
    primary_key: :sha,
    inverse_of: :attachment
  
  delegate :ungzip_if_necessary!, to: :class
  attr_accessor :decoded_data
  
  def self.from_cbor(cbor_encoded_data)
    cbor_encoded_data = ungzip_if_necessary!(cbor_encoded_data)
    
    decoded_data = CBOR.decode(cbor_encoded_data)
    
    new(decoded_data: decoded_data)
  rescue EOFError, *cbor_errors => e
    raise InvalidInputError, "Failed to decode CBOR: #{e.message}"
  end
  
  def decoded_data=(new_decoded_data)
    @decoded_data = new_decoded_data
    
    validate_input!
    
    self.content = ungzip_if_necessary!(decoded_data['content'])
    self.content_type = ungzip_if_necessary!(decoded_data['content_type'])
    self.size = content.bytesize
    self.sha = calculate_sha
    
    decoded_data
  end
  
  def calculate_sha
    combined = [
      Digest::SHA256.hexdigest(content_type),
      Digest::SHA256.hexdigest(content),
    ].join
    
    "0x" + Digest::SHA256.hexdigest(combined)
  end
  
  def self.from_eth_transaction(tx)
    blobs = tx.blobs.map{|i| i['blob']}
    
    cbor = BlobUtils.from_blobs(blobs: blobs)

    from_cbor(cbor)
  end
  
  def create_unless_exists!
    save! unless self.class.exists?(sha: sha)
  end
  
  def self.ungzip_if_necessary!(binary)
    HexDataProcessor.ungzip_if_necessary(binary)
  rescue Zlib::Error, CompressionLimitExceededError => e
    raise InvalidInputError, "Failed to decompress content: #{e.message}"
  end
  
  def content_type_with_encoding
    parts = content_type.split(';').map(&:strip)
    mime_type = parts[0]
    
    has_charset = parts.any? { |part| part.downcase.start_with?('charset=') }
  
    text_or_json_types = ['text/', 'application/json', 'application/javascript']
  
    if text_or_json_types.any? { |type| mime_type.downcase.start_with?(type) } && !has_charset
      "#{mime_type}; charset=UTF-8"
    else
      content_type
    end
  end
  
  private
  
  def validate_input!
    unless decoded_data.is_a?(Hash)
      raise InvalidInputError, "Expected data to be a hash, got #{decoded_data.class} instead."
    end
    
    unless decoded_data.keys.to_set == ['content', 'content_type'].to_set
      raise InvalidInputError, "Expected keys to be 'content' and 'content_type', got #{decoded_data.keys} instead."
    end
    
    unless decoded_data.values.all?{|i| i.is_a?(String)}
      raise InvalidInputError, "Invalid value type: #{decoded_data.values.map(&:class).join(', ')}"
    end
  end
  
  def self.cbor_errors
    [CBOR::MalformedFormatError, CBOR::UnpackError, CBOR::StackError, CBOR::TypeError]
  end
end

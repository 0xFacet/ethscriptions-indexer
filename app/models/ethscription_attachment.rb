class EthscriptionAttachment < ApplicationRecord
  class InvalidInputError < StandardError; end
  
  has_many :ethscriptions,
    foreign_key: :attachment_sha,
    primary_key: :sha,
    inverse_of: :attachment
  
  def self.from_cbor(cbor_encoded_data)
    cbor_encoded_data = ungzip_if_necessary!(cbor_encoded_data)
    
    decoded_data = CBOR.decode(cbor_encoded_data)
    validate_input!(decoded_data)
    
    if decoded_data['content'].respond_to?(:encoding)
      is_text = decoded_data['content'].encoding.name == 'UTF-8'
    else
      is_text = false
    end
    
    content = ungzip_if_necessary!(decoded_data['content'])
    mimetype = ungzip_if_necessary!(decoded_data['mimetype'])
    
    sha_input = {
      mimetype: mimetype,
      content: content,
    }.to_canonical_cbor
    sha = "0x" + Digest::SHA256.hexdigest(sha_input)
    
    new(
      content: content,
      is_text: is_text,
      sha: sha,
      mimetype: mimetype,
      size: content.bytesize,
    )
  rescue EOFError, CBOR::MalformedFormatError => e
    raise InvalidInputError, "Failed to decode CBOR: #{e.message}"
  end
  
  def self.from_blobs(blobs)
    return if blobs.blank?
    
    concatenated_hex = blobs.map do |blob|
      hex_blob = blob["blob"].sub(/\A0x/, '')
      
      sections = hex_blob.scan(/.{64}/m)
      
      last_non_empty_section_index = sections.rindex { |section| section != '00' * 32 }
      non_empty_sections = sections.take(last_non_empty_section_index + 1)
      
      last_non_empty_section = non_empty_sections.last
      
      if last_non_empty_section == "0080" + "00" * 30
        non_empty_sections.pop
      else
        last_non_empty_section.gsub!(/80(00)*\z/, '')
      end
      
      non_empty_sections = non_empty_sections.map do |section|
        unless section.start_with?('00')
          raise InvalidInputError, "Expected the first byte to be zero"
        end
        
        section.delete_prefix("00")
      end
      
      non_empty_sections.join
    end.join
    
    cbor = [concatenated_hex].pack("H*")
    
    from_cbor(cbor)
  end
  
  def create_unless_exists!
    save! unless self.class.exists?(sha: sha)
  end
  
  def prepared_content
    is_text ? HexDataProcessor.clean_utf8(content) : content
  end
  
  def self.ungzip_if_necessary!(binary)
    HexDataProcessor.ungzip_if_necessary(binary).tap do |res|
      if res.nil?
        raise InvalidInputError, "Failed to decompress content"
      end
    end
  end
  
  def self.validate_input!(decoded_data)
    if decoded_data['content'].nil? || decoded_data['mimetype'].nil?
      raise InvalidInputError, "Missing required fields: content, mimetype"
    end
  end
end

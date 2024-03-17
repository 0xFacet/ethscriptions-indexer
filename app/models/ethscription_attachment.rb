class EthscriptionAttachment < ApplicationRecord
  class InvalidInputError < StandardError; end
  
  has_many :ethscriptions,
    foreign_key: :attachment_sha,
    primary_key: :sha,
    inverse_of: :attachment
  
  def self.from_cbor(cbor_encoded_data)
    decoded_data = CBOR.decode(cbor_encoded_data)
    validate_input!(decoded_data)
    
    content = decoded_data['content']
    mimetype = decoded_data['mimetype']
    is_text = content.encoding.name == 'UTF-8'
    
    sha_input = mimetype + content
    sha = "0x" + Digest::SHA256.hexdigest(sha_input)
    
    compression = decoded_data['compression'] || ('gzip' if HexDataProcessor.gzip_compressed?(content))
    
    new(
      content: content,
      is_text: is_text,
      sha: sha,
      mimetype: mimetype,
      compression: compression,
      size: content.bytesize,
    )
  rescue EOFError, CBOR::MalformedFormatError => e
    raise InvalidInputError, "Failed to decode CBOR: #{e.message}"
  rescue InvalidInputError => e
    logger.error("#{e.message}")
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
          raise "Expected the first byte to be zero"
        end
        
        section.delete_prefix("00")
      end
      
      non_empty_sections.join
    end.join
    
    cbor = [concatenated_hex].pack("H*")
    
    from_cbor(cbor)
  end
  
  def create_unless_exists!
    save!
  rescue ActiveRecord::RecordNotUnique
  end
  
  def prepared_content
    decompressed_content = HexDataProcessor.ungzip_if_necessary(content)
  
    if is_text
      HexDataProcessor.clean_utf8(decompressed_content)
    else
      decompressed_content
    end
  end
  
  def self.validate_input!(decoded_data)
    if decoded_data['content'].nil? || decoded_data['mimetype'].nil?
      raise InvalidInputError, "Missing required fields: content, mimetype"
    end
    
    if decoded_data['compression'] && !['gzip', 'brotli'].include?(decoded_data['compression'])
      raise InvalidInputError, "Invalid compression type: #{decoded_data['compression']}"
    end
  end
end


module HexDataProcessor
  def self.hex_to_utf8(hex_string, support_gzip:)
    clean_hex_string = hex_string.gsub(/\A0x/, '')
    binary_data = hex_string_to_binary(clean_hex_string)
    
    if support_gzip && gzip_compressed?(binary_data)
      decompressed_data = decompress_with_ratio_limit(binary_data, 10)
    else
      decompressed_data = binary_data
    end
  
    return nil unless decompressed_data
    
    clean_utf8(decompressed_data)
  end

  def self.hex_string_to_binary(hex_string)
    ary = hex_string.scan(/../).map { |pair| pair.to_i(16) }
    ary.pack('C*')
  end

  def self.gzip_compressed?(data)
    data[0..1].bytes == [0x1F, 0x8B]
  end

  def self.ungzip_if_necessary(binary_data)
    if gzip_compressed?(binary_data)
      decompressed_data = decompress_with_ratio_limit(binary_data, 10)
      return decompressed_data if decompressed_data
    end

    binary_data
  end
  
  # def self.brotli_decompress_with_ratio_limit(data, max_ratio)
  #   original_size = data.bytesize
  #   decompressed = StringIO.new
  
  #   # begin
  #     # Create a StringIO object from the Brotli compressed data
  #     compressed_io = StringIO.new(data)
  #     ap compressed_io
  #     # Initialize the Brotli stream reader
  #     BRS::Stream::Reader.new(compressed_io) do |reader|
  #       ap reader.read(16.kilobytes)
  #       while chunk = reader.read(16.kilobytes) # Read in chunks
  #         ap chunk
  #         decompressed.write(chunk)
  #         if decompressed.length > original_size * max_ratio
  #           return nil # Exceeds compression ratio limit
  #         end
  #       end
  #     end
  # raise
  #     decompressed.string
  #   # rescue StandardError # Catch any errors during decompression
  #   #   nil
  #   # end
  # end

  def self.decompress_with_ratio_limit(data, max_ratio)
    original_size = data.bytesize
    decompressed = StringIO.new

    Zlib::GzipReader.wrap(StringIO.new(data)) do |gz|
      while chunk = gz.read(16.kilobytes) # Read in chunks
        decompressed.write(chunk)
        if decompressed.length > original_size * max_ratio
          return nil # Exceeds compression ratio limit
        end
      end
    end

    decompressed.string
  rescue Zlib::Error
    nil
  end

  def self.clean_utf8(binary_data)
    utf8_string = binary_data.force_encoding('UTF-8')
    
    unless utf8_string.valid_encoding?
      utf8_string = utf8_string.encode('UTF-8', invalid: :replace, undef: :replace, replace: "\uFFFD")
    end
    
    utf8_string.delete("\u0000")
  end
end

class DataUri
  REGEXP = %r{
    \Adata:
    (?<mediatype>
      (?<mimetype> .+? / .+? )?
      (?<parameters> (?: ; .+? = .+? )* )
    )?
    (?<extension>;base64)?
    ,
    (?<data>.*)\z
  }x.freeze

  attr_reader :uri, :match

  def initialize(uri)
    match = REGEXP.match(uri)
    raise ArgumentError, 'invalid data URI' unless match

    @uri = uri
    @match = match
    
    validate_base64_content
  end

  def self.valid?(uri)
    begin
      DataUri.new(uri)
      true
    rescue ArgumentError
      false
    end
  end

  def self.esip6?(uri)
    begin
      parameters = DataUri.new(uri).parameters

      parameters.include?("rule=esip6")
    rescue ArgumentError
      false
    end
  end

  def validate_base64_content
    if base64?
      begin
        Base64.strict_decode64(data)
      rescue ArgumentError
        raise ArgumentError, 'malformed base64 content'
      end
    end
  end

  def mediatype
    "#{mimetype}#{parameters}"
  end

  def decoded_data
    return data unless base64?

    Base64.decode64(data)
  end
  
  def base64?
    !String(extension).empty?
  end

  def mimetype
    if String(match[:mimetype]).empty? || uri.starts_with?("data:,")
      return 'text/plain'
    end
    
    match[:mimetype]
  end
  
  def data
    match[:data]
  end

  def parameters
    return [] if String(match[:mimetype]).empty? && String(match[:parameters]).empty?
  
    match[:parameters].split(";").reject(&:empty?)
  end  
  
  def extension
    match[:extension]
  end
end

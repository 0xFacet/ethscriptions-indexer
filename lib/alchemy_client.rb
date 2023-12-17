require 'net/http'

class AlchemyClient
  def self.query_api(method:, params: [], save: false)
    data = {
      id: 1,
      jsonrpc: "2.0",
      method: method,
      params: params
    }
    
    raw_response = make_raw_request(data)
    
    save_raw_response(
      method: method,
      raw_response: raw_response,
      params: params,
      queried_at: Time.zone.now,
    ) if save
    
    raw_response
  end
  
  def self.query_api_batch(method:, batch_body:, save: false)
    raw_response = make_raw_request(batch_body)
  
    api_method = batch_body.map { |req| req[:method] }.uniq.length == 1 ? batch_body.first[:method] : 'batch_request'
    
    save_raw_response(
      method: api_method,
      raw_response: raw_response,
      params: batch_body,
      queried_at: Time.zone.now,
    ) if save
  
    raw_response
  end
  
  def self.save_raw_response(method:, params:, raw_response:, queried_at:)
    RawApiResponse.create!(
      method: method,
      params: params,
      raw_response: raw_response,
      queried_at: queried_at
    )
  end
  
  def self.make_raw_request(body)
    network = ENV.fetch('ETHEREUM_NETWORK')
    api_key = ENV.fetch('ALCHEMY_API_KEY')
    
    url = "https://#{network}.g.alchemy.com/v2/#{api_key}"
    uri = URI(url)
    
    headers = {
      'accept' => 'application/json',
      'content-type' => 'application/json'
    }
    
    body_json = JSON.generate(body)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path, headers)
    request.body = body_json
    
    response = http.request(request)
    JSON.parse(response.body)
  end
end

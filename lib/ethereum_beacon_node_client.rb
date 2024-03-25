class EthereumBeaconNodeClient
  attr_accessor :base_url, :api_key

  def initialize(base_url: ENV['ETHEREUM_BEACON_NODE_API_BASE_URL'], api_key:)
    self.base_url = base_url.chomp('/')
    self.api_key = api_key
  end

  def get_blob_sidecars(block_id)
    base_url_with_key = [base_url, api_key].join('/').chomp('/')
    url = [base_url_with_key, "eth/v1/beacon/blob_sidecars/#{block_id}"].join('/')
    
    HTTParty.get(url).parsed_response['data']
  end
  
  def get_block(block_id)
    base_url_with_key = [base_url, api_key].join('/').chomp('/')
    url = [base_url_with_key, "eth/v2/beacon/blocks/#{block_id}"].join('/')
    
    HTTParty.get(url).parsed_response['data']
  end
  
  def get_genesis
    base_url_with_key = [base_url, api_key].join('/').chomp('/')
    url = [base_url_with_key, "eth/v1/beacon/genesis"].join('/')
    
    HTTParty.get(url).parsed_response['data']
  end
end

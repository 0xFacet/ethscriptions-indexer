class AlchemyClient
  attr_accessor :base_url, :api_key

  def initialize(base_url: ENV['ETHEREUM_CLIENT_BASE_URL'], api_key:)
    self.base_url = base_url.chomp('/')
    self.api_key = api_key
  end

  def get_block(block_number)
    query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), true]
    )
  end

  def get_transaction_receipts(block_number)
    query_api(
      method: 'alchemy_getTransactionReceipts',
      params: [{ blockNumber: "0x" + block_number.to_s(16) }]
    )
  end

  private

  def query_api(method:, params: [])
    data = {
      id: 1,
      jsonrpc: "2.0",
      method: method,
      params: params
    }

    url = "#{base_url}/#{api_key}"

    HTTParty.post(url, body: data.to_json, headers: headers).parsed_response
  end

  def headers
    { 
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end
end

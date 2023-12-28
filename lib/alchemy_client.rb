class AlchemyClient
  attr_accessor :api_key, :network

  def initialize(
    api_key: ENV.fetch('ALCHEMY_API_KEY'),
    network: ENV.fetch('ETHEREUM_NETWORK')
  )
    self.api_key = api_key
    self.network = network
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

    url = "https://#{network}.g.alchemy.com/v2/#{api_key}"

    HTTParty.post(url, body: data.to_json, headers: headers).parsed_response
  end

  def headers
    { 
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end
end

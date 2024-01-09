class UniversalClient
  attr_accessor :base_url, :api_key

  def initialize(base_url: ENV['ETHEREUM_CLIENT_BASE_URL'], api_key: nil)
    self.base_url = base_url.chomp('/')
    self.api_key = api_key
  end

  def headers
    {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def query_api(method:, params: [])
    data = {
      id: 1,
      jsonrpc: '2.0',
      method: method,
      params: params
    }

    url = [base_url, api_key].join('/')
    
    HTTParty.post(url, body: data.to_json, headers: headers).parsed_response
  end

  def get_block(block_number)
    query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), true]
    )
  end

  def get_transactions(block_number)
    block_info = query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), false]
    )
    
    block_info['result']['transactions']
  end

  def get_transaction_receipt(transaction_hash)
    query_api(
      method: 'eth_getTransactionReceipt',
      params: [transaction_hash]
    )
  end

  def get_transaction_receipts(block_number)
    transactions = get_transactions(block_number)
    
    receipts = transactions.map do |transaction|
      get_transaction_receipt(transaction)['result']
    end

    {
      'id' => 1,
      'jsonrpc' => '2.0',
      'result' => {
        'receipts' => receipts
      }
    }
  end
end
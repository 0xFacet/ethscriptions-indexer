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

  def get_transaction_receipts(block_number, blocks_behind: nil)
    use_individual = ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia" &&
      blocks_behind.present? &&
      blocks_behind < 5
      
    if use_individual
      get_transaction_receipts_individually(block_number)
    else
      get_transaction_receipts_batch(block_number)
    end
  end
  
  def get_transaction_receipts_batch(block_number)
    query_api(
      method: 'alchemy_getTransactionReceipts',
      params: [{ blockNumber: "0x" + block_number.to_s(16) }]
    )
  end
  
  def get_transaction_receipts_individually(block_number)
    block_info = query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), false]
    )
    
    transactions = block_info['result']['transactions']
    
    receipts = transactions.map do |transaction|
      Concurrent::Promise.execute do
        get_transaction_receipt(transaction)['result']
      end
    end.map(&:value!)
    
    {
      'id' => 1,
      'jsonrpc' => '2.0',
      'result' => {
        'receipts' => receipts
      }
    }
  end
  
  def get_transaction_receipt(transaction_hash)
    query_api(
      method: 'eth_getTransactionReceipt',
      params: [transaction_hash]
    )
  end
  
  def get_block_number
    query_api(method: 'eth_blockNumber')['result'].to_i(16)
  end

  private

  def query_api(method:, params: [])
    data = {
      id: 1,
      jsonrpc: "2.0",
      method: method,
      params: params
    }

    url = [base_url, api_key].join('/')

    HTTParty.post(url, body: data.to_json, headers: headers).parsed_response
  end

  def headers
    { 
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end
end

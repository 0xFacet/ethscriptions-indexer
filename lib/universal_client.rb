class UniversalClient
    attr_accessor :endpoint_url

    def initialize(endpoint_url: ENV.fetch('UNIVERSAL_ENDPOINT_URL'))
        self.endpoint_url = endpoint_url
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

        url = "#{endpoint_url}"

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
        receipts = []
        for transaction in transactions
            receipt = get_transaction_receipt(transaction)
            receipts << receipt['result']
        end

        result = Hash[
            'id'=> 1,
            'jsonrpc'=> '2.0',
            'result'=> Hash[
                'receipts'=> receipts
            ]
        ]
    end
end
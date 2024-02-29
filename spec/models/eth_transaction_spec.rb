require 'rails_helper'
require 'ethscription_test_helper'

RSpec.describe EthTransaction, type: :model do
  before do
    allow(EthTransaction).to receive(:esip3_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip5_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip2_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip1_enabled?).and_return(true)
  end
  
  describe '#create_ethscription_if_needed!' do
    context 'when both input and logs are empty' do
      it 'does not create an ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
    
        expect(Ethscription.count).to eq(0)
      end
    end
    
    context 'when there are no logs' do
      it 'creates ethscription from input when valid' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )

        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        
        created = Ethscription.first
        expect(created.creator).to eq("0xc2172a6315c1d7f6855768f843c420ebb36eda97")
        expect(created.initial_owner).to eq("0xc2172a6315c1d7f6855768f843c420ebb36eda97")
      end
      
      it 'does not create ethscription with invalid data uri' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
        
        expect(Ethscription.count).to eq(0)
        expect(Ethscription.count).to eq(0)
      end
      
      it 'does not create ethscription with dupe' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
        
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
        
        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
      end
    end
    
    context 'when there are valid logs and dupe input' do
      it 'creates an ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
        
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log']).unpack1('H*'),
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log-2']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )
        
        expect(Ethscription.count).to eq(2)
        
        created = Ethscription.last
        expect(Ethscription.first.content).to eq("test")
        expect(created.content).to eq("test-log")
        expect(created.creator).to eq("0xe7dfe249c262a6a9b57651782d57296d2e4bccc9")
        expect(created.event_log_index).to eq(1)
      end
    end
    
    context 'when there are duplicate logs' do
      it 'creates only one ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "invalid",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log']).unpack1('H*'),
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc4'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )
        
        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        created = Ethscription.last
        expect(created.content).to eq("test-log")
        expect(created.creator).to eq("0xe7dfe249c262a6a9b57651782d57296d2e4bccc4")
        expect(created.event_log_index).to eq(1)
      end
    end
    
    context 'when there are invalid logs' do
      it 'creates only one ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "invalid",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['invalid']).unpack1('H*'),
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc4'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )
    
        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        
        created = Ethscription.last
        expect(created.content).to eq("test-log")
        expect(created.creator).to eq("0xe7dfe249c262a6a9b57651782d57296d2e4bccc9")
        expect(created.event_log_index).to eq(2)
      end
    end
    
    context 'when there are multiple valid logs' do
      it 'does not create multiple ethscriptions' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test1']).unpack1('H*'),
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test2']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )
    
        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        created = Ethscription.last
        expect(created.content).to eq("test")
      end
    end
    
    context 'when there are mixed valid and invalid logs' do
      it 'creates an ethscription for valid logs only' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => ['invalid'],
              'data' => 'invalid',
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )
    
        expect(Ethscription.count).to eq(1)
        created = Ethscription.last
        expect(created.content).to eq("test")
        expect(created.event_log_index).to eq(nil)
      end
    end

    context 'when there are valid logs' do
      it 'creates an ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test-input",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test']).unpack1('H*'),
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )

        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        
        created = Ethscription.first
        expect(created.content).to eq("test-input")
      end
    end

    context 'when there are invalid logs followed by valid ones' do
      it 'creates an ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "data:,test-input",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => ['invalid'],
              'data' => 'invalid',
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )

        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        created = Ethscription.first
        expect(created.content).to eq("test-input")
      end
      
      it 'creates an ethscription' do
        EthscriptionTestHelper.create_eth_transaction(
          input: "invalid",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: [
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'logIndex' => 1.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            },
            {
              'topics' => [
                EthTransaction::CreateEthscriptionEventSig,
                Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              ],
              'data' => Eth::Abi.encode(['string'], ['data:,test-log-2']).unpack1('H*'),
              'logIndex' => 2.to_s(16),
              'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
            }
          ]
        )

        expect(Ethscription.count).to eq(1)
        expect(Ethscription.count).to eq(1)
        created = Ethscription.first
        expect(created.content).to eq("test-log-2")
      end
    end
    
    context 'when input is valid and GZIP-compressed' do
      it 'creates ethscription from GZIP-compressed input when valid' do
        # Generate a GZIP-compressed version of the string "data:,test-gzip"
        compressed_data = Zlib.gzip("data:,test-gzip")
        hex_compressed_data = compressed_data.unpack1('H*')
        
        EthscriptionTestHelper.create_eth_transaction(
          input: "0x#{hex_compressed_data}",
          from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          logs: []
        )
    
        expect(Ethscription.count).to eq(1)
        created = Ethscription.first
        expect(created.content).to eq("test-gzip")
      end
    end
  end
  
  context 'when input is GZIP-compressed but invalid or exceeds decompression ratio' do
    it 'does not create ethscription with invalid or too large GZIP-compressed data' do
      # Example of invalid GZIP-compressed data (you may need to tailor this)
      invalid_compressed_data = "invalidgzipdata"
      hex_invalid_compressed_data = invalid_compressed_data.unpack1('H*')
      
      EthscriptionTestHelper.create_eth_transaction(
        input: "0x#{hex_invalid_compressed_data}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
  
      expect(Ethscription.count).to eq(0)
    end
  end
  
  context 'when input is GZIP-compressed with a high decompression ratio' do
    it 'does not create ethscription if decompressed data exceeds ratio limit' do
      # Create a large string that, when compressed, significantly reduces in size
      large_string = "A" * 100_000 # Adjust size as needed to exceed the ratio limit upon decompression
      compressed_large_string = Zlib::Deflate.deflate(large_string)
      hex_compressed_large_string = compressed_large_string.unpack1('H*')
  
      EthscriptionTestHelper.create_eth_transaction(
        input: "0x#{hex_compressed_large_string}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
  
      expect(Ethscription.count).to eq(0)
    end
  end
end

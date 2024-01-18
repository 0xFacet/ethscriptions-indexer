require 'rails_helper'
require 'ethscription_test_helper'

RSpec.describe EthscriptionTransfer, type: :model do
  before do
    allow(EthTransaction).to receive(:esip3_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip5_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip2_enabled?).and_return(true)
    allow(EthTransaction).to receive(:esip1_enabled?).and_return(true)
  end
  
  context 'when an ethscription is transferred' do
    it 'handles a single transfer' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: "data:,test",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
      
      ethscription = tx.ethscription
  
      EthscriptionTestHelper.create_eth_transaction(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0x104a84b87e1e7054c48b63077b8b7ccd62de9260",
        input: ethscription.transaction_hash,
        logs: [
          {
            'topics' => [
              EthTransaction::Esip1EventSig,
              Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
              Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            ],
            'data' => Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            'logIndex' => 1.to_s(16),
            'address' => '0xe7dfe249c262a6a9b57651782d57296d2e4bccc9'
          }
        ]
      )
      
      ethscription.reload
  
      expect(ethscription.current_owner).to eq("0x104a84b87e1e7054c48b63077b8b7ccd62de9260")
    end
    
    it 'handles chain reorgs' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: 'data:,{"p":"erc-20","op":"mint","tick":"gwei","id":"6359","amt":"1000"}',
        from: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        to: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        tx_hash: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22'
      )
      
      eths = tx.ethscription
      
      current_owner = eths.current_owner
      previous_owner = eths.previous_owner
      
      second_tx = EthscriptionTestHelper.create_eth_transaction(
        input: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22',
        from: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        to: "0x36442bda6780c95113d7c38dd17cdd94be611de8",
      )
      
      EthBlock.where("block_number >= ?", second_tx.block_number).delete_all
      
      eths.reload
      
      expect(eths.current_owner).to eq(current_owner)
      expect(eths.previous_owner).to eq(previous_owner)
    end
    
    it 'handles invalid transfers' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: 'data:,{"p":"erc-20","op":"mint","tick":"gwei","id":"6359","amt":"1000"}',
        from: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        to: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        tx_hash: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22'
      )
      
      eths = tx.ethscription
      
      EthscriptionTestHelper.create_eth_transaction(
        input: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22',
        from: "0xD729A94d6366a4fEac4A6869C8b3573cEe4701A9",
        to: "0x0000000000000000000000000000000000000000",
      )
      
      eths.reload
      
      expect(eths.current_owner).to eq("0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d".downcase)
    end
    
    it 'handles a sequence of transfers' do
      
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: 'data:,{"p":"erc-20","op":"mint","tick":"gwei","id":"6359","amt":"1000"}',
        from: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        to: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        tx_hash: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22'
      )
      
      eths = tx.ethscription
      
      EthscriptionTestHelper.create_eth_transaction(
        input: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22',
        from: "0x9C80cb4b2c8311C3070f62C9e9B4f40C43291E8d",
        to: "0x36442bda6780c95113d7c38dd17cdd94be611de8",
      )
      
      EthscriptionTestHelper.create_eth_transaction(
        input: '0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22',
        from: "0x36442bda6780c95113d7c38dd17cdd94be611de8",
        to: "0xD729A94d6366a4fEac4A6869C8b3573cEe4701A9",
      )
      
      eths.reload

      expect(eths.current_owner).to eq("0xD729A94d6366a4fEac4A6869C8b3573cEe4701A9".downcase)
      expect(eths.previous_owner).to eq("0x36442bda6780c95113d7c38dd17cdd94be611de8".downcase)
      
      EthscriptionTestHelper.create_eth_transaction(
        input: "0xccad70f16a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22",
        from: "0x8558dB5F3f9201492028fad05087B6a1d9C11273",
        to: "0xD729A94d6366a4fEac4A6869C8b3573cEe4701A9",
        logs: [
          {
            'topics' => [
              EthTransaction::Esip1EventSig,
              Eth::Abi.encode(['address'], ['0x8558dB5F3f9201492028fad05087B6a1d9C11273']).unpack1('H*'),
              Eth::Abi.encode(['bytes32'], ['0x6A8F9706637F16C9A93A7BAC072BBB291530D9D59F1EBA43E28FB5BC2CF12A22']).unpack1('H*'),
            ],
            'logIndex' => 214.to_s(16),
            'address' => '0xd729a94d6366a4feac4a6869c8b3573cee4701a9'
          }
        ]
      )
      
      eths.reload
      
      expect(eths.current_owner).to eq("0x8558dB5F3f9201492028fad05087B6a1d9C11273".downcase)
      expect(eths.previous_owner).to eq("0xd729a94d6366a4feac4a6869c8b3573cee4701a9".downcase)
      
      EthscriptionTestHelper.create_eth_transaction(
        input: "0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22",
        from: "0x8558dB5F3f9201492028fad05087B6a1d9C11273",
        to: "0x57b8792c775D34Aa96092400983c3e112fCbC296",
      )

      eths.reload
      
      expect(eths.current_owner).to eq("0x57b8792c775D34Aa96092400983c3e112fCbC296".downcase)
      expect(eths.previous_owner).to eq("0x8558dB5F3f9201492028fad05087B6a1d9C11273".downcase)
      
      EthscriptionTestHelper.create_eth_transaction(
        input: "0x6a8f9706637f16c9a93a7bac072bbb291530d9d59f1eba43e28fb5bc2cf12a22",
        from: "0x8558dB5F3f9201492028fad05087B6a1d9C11273",
        to: "0x57b8792c775D34Aa96092400983c3e112fCbC296",
        logs: [
          {
            'topics' => [
              EthTransaction::Esip2EventSig,
              Eth::Abi.encode(['address'], ['0x8558dB5F3f9201492028fad05087B6a1d9C11273']).unpack1('H*'),
              Eth::Abi.encode(['address'], ['0x8D5b48934c0C408ADC25F14174c7307922F6Aa60']).unpack1('H*'),
              Eth::Abi.encode(['bytes32'], ['6A8F9706637F16C9A93A7BAC072BBB291530D9D59F1EBA43E28FB5BC2CF12A22']).unpack1('H*'),
            ],
            'logIndex' => 543.to_s(16),
            'address' => '0x57b8792c775d34aa96092400983c3e112fcbc296'
          }
        ]
      )

      eths.reload
      
      expect(eths.current_owner).to eq("0x8d5b48934c0c408adc25f14174c7307922f6aa60".downcase)
      expect(eths.previous_owner).to eq("0x57b8792c775D34Aa96092400983c3e112fCbC296".downcase)
    end
    
    it 'ignores logs with incorrect number of topics for Esip1EventSig and Esip2EventSig' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: 'data:,test',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
    
      ethscription = tx.ethscription
      original_owner = ethscription.current_owner
    
      EthscriptionTestHelper.create_eth_transaction(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0x104a84b87e1e7054c48b63077b8b7ccd62de9260",
        input: ethscription.transaction_hash,
        logs: [
          {
            'topics' => [
              EthTransaction::Esip1EventSig,
              Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
            ],
            'data' => Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            'logIndex' => 1.to_s(16),
            'address' => '0x104a84b87e1e7054c48b63077b8b7ccd62de9260'
          },
          {
            'topics' => [
              EthTransaction::Esip2EventSig,
              Eth::Abi.encode(['address'], ['0xc2172a6315c1d7f6855768f843c420ebb36eda97']).unpack1('H*'),
            ],
            'data' => Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            'logIndex' => 1.to_s(16),
            'address' => '0x104a84b87e1e7054c48b63077b8b7ccd62de9260'
          },
          {
            'topics' => [
              EthTransaction::Esip1EventSig,
              Eth::Abi.encode(['address'], ['0x0000000000000000000000000000000000000000']).unpack1('H*'),
              Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            ],
            'data' => Eth::Abi.encode(['bytes32'], [ethscription.transaction_hash]).unpack1('H*'),
            'logIndex' => 1.to_s(16),
            'address' => '0x104a84b87e1e7054c48b63077b8b7ccd62de9260'
          },
        ]
      )
    
      ethscription.reload
    
      expect(ethscription.current_owner).to eq("0x0000000000000000000000000000000000000000")
    end
  end
end

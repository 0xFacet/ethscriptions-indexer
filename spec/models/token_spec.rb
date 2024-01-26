# spec/models/token_spec.rb
require 'rails_helper'

RSpec.describe Token, type: :model do
  describe '.process_ethscription_transfer' do
    it 'processes a transfer as the first transfer' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: "data:,{\"p\":\"erc-20\",\"op\":\"deploy\",\"tick\":\"nodes\",\"max\":\"10000000000\",\"lim\":\"10000\"}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
      
      token = Token.create_from_token_details!(
        tick: "nodes",
        p: "erc-20",
        max: 10000000000,
        lim: 10000
      )
      
      initial_balances = token.balances
      initial_total_supply = token.total_supply
      
      transfer_tx = nil
      
      expect { transfer_tx = EthscriptionTestHelper.create_eth_transaction(
        input: "data:,{\"p\":\"erc-20\",\"op\":\"mint\",\"tick\":\"nodes\",\"id\":\"335997\",\"amt\":\"10000\"}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      ) }.to change { TokenState.count }.by(1)

      transfer = transfer_tx.ethscription_transfers.first

      expect(token.reload.total_supply).to eq(initial_total_supply + token.mint_amount)

      expect(token.reload.balances).to eq({ transfer.to_address => token.mint_amount })
    end
  end
  
  describe 'TokenState destruction' do
    it 'reverts the token back to its original state upon TokenState destruction' do
      tx = EthscriptionTestHelper.create_eth_transaction(
        input: "data:,{\"p\":\"erc-20\",\"op\":\"deploy\",\"tick\":\"nodes\",\"max\":\"10000000000\",\"lim\":\"10000\"}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
      # Set up the initial token and token state
      token = Token.create_from_token_details!(
        tick: "nodes",
        p: "erc-20",
        max: 10000000000,
        lim: 10000
      )
      
      initial_balances = token.balances.deep_dup
      initial_total_supply = token.total_supply

      # Create a transaction that would alter the token state
      transfer_tx = EthscriptionTestHelper.create_eth_transaction(
        input: "data:,{\"p\":\"erc-20\",\"op\":\"mint\",\"tick\":\"nodes\",\"id\":\"335997\",\"amt\":\"10000\"}",
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        logs: []
      )
      
      expect { transfer_tx.delete }.to change { TokenState.count }.by(-1)

      # Reload the token to get the updated state
      token.reload

      # Check that the token's state has been reverted
      expect(token.total_supply).to eq(initial_total_supply)
      expect(token.balances).to eq(initial_balances)
    end
  end
  
  it 'correctly processes the transfer and updates the token state' do
    tx = EthscriptionTestHelper.create_eth_transaction(
      input: "data:,{\"p\":\"erc-20\",\"op\":\"deploy\",\"tick\":\"nodes\",\"max\":\"10000000000\",\"lim\":\"10000\"}",
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      logs: []
    )
    # Set up the initial token and token state
    token = Token.create_from_token_details!(
      tick: "nodes",
      p: "erc-20",
      max: 10000000000,
      lim: 10000
    )
    
    initial_count = TokenState.count
    
    first_transfer_tx = EthscriptionTestHelper.create_eth_transaction(
      input: "data:,{\"p\":\"erc-20\",\"op\":\"mint\",\"tick\":\"nodes\",\"id\":\"335997\",\"amt\":\"10000\"}",
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      logs: []
    )
    first_transfer = first_transfer_tx.ethscription_transfers.first
    # binding.pry
    expect(TokenState.count).to eq(initial_count + 1)
    initial_count = TokenState.count

    expect(token.reload.total_supply).to eq(token.mint_amount)
    
    expect(token.reload.balances).to eq({
      first_transfer.to_address => token.mint_amount
    })
    
    # Create the second transfer
    second_transfer_tx = EthscriptionTestHelper.create_eth_transaction(
      input: first_transfer.transaction_hash,
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      to: "0xf0c2d5DD70C26e34f5fB4AC1BC4EA5B2eDF8137A",
      logs: []
    )
    second_transfer = second_transfer_tx.ethscription_transfers.first
    expect(TokenState.count).to eq(initial_count + 1)

    # Expect the TokenState count to increase by 1 after the second transfer
    # Reload the token to get the updated state
    token.reload

    # Check that the token's total supply has been updated correctly
    expect(token.total_supply).to eq(token.mint_amount)

    expect(token.balances).to eq({
      first_transfer.to_address => 0,
      second_transfer.to_address => token.mint_amount
    })
    
    second_transfer_tx.delete
    
    expect(token.reload.total_supply).to eq(token.mint_amount)
    
    expect(token.reload.balances).to eq({
      first_transfer.to_address => token.mint_amount
    })
  end
end

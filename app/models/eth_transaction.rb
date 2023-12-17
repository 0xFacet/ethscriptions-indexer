
class EthTransaction < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :eth_transaction
  has_one :ethscription, foreign_key: :transaction_hash, primary_key: :transaction_hash,
    inverse_of: :eth_transaction, dependent: :destroy

  has_many :ethscription_transfers, foreign_key: :transaction_hash,
    primary_key: :transaction_hash, dependent: :destroy, inverse_of: :eth_transaction

  attr_accessor :transfer_index, :already_created_ethscription
  
  def possibly_relevant?
    status != 0 &&
    (possibly_creates_ethscription? || possibly_transfers_ethscription?)
  end
  
  def possibly_creates_ethscription?
    (DataUri.valid?(utf8_input) && to_address.present?) ||
    ethscription_creation_events.present?
  end
  
  def possibly_transfers_ethscription?
    transfers_ethscription_via_input? ||
    ethscription_transfer_events.present?
  end
  
  def utf8_input
    EthTransaction.hex_to_utf8(input)
  end
  
  def ethscription_attrs
    {
      transaction_hash: transaction_hash,
      block_number: block_number,
      block_timestamp: block_timestamp,
      transaction_index: transaction_index,
      gas_price: gas_price,
      gas_used: gas_used,
      transaction_fee: transaction_fee,
      value: value,
    }
  end
  
  # def get_and_consume_transfer_index
  #   if @transfer_index.nil?
  #     raise "Must initialize @transfer_index"
  #   end
    
  #   @transfer_index.tap do
  #     @transfer_index += 1
  #   end
  # end

  def process!
    self.transfer_index = 0
    self.already_created_ethscription = false
    
    create_ethscription_from_input!
    create_ethscription_from_events!
    create_ethscription_transfers_from_input!
    create_ethscription_transfers_from_events!
  end

  def create_ethscription_from_input!
    potentially_valid = build_ethscription(
      {
        creator: from_address,
        previous_owner: from_address,
        current_owner: to_address,
        initial_owner: to_address,
        content_uri: utf8_input,
      }.merge(ethscription_attrs)
    )
    
    save_if_valid_and_no_ethscription_created!(potentially_valid)
  end
  
  def create_ethscription_from_events!
    ethscription_creation_events.each do |creation_event|
      next if creation_event['topics'].length != 2
    
      begin
        initial_owner = Eth::Abi.decode(['address'], creation_event['topics'].second).first
        fixed_uri = Eth::Abi.decode(['string'], creation_event['data']).first
      rescue Eth::Abi::DecodingError
        next
      end
          
      potentially_valid = build_ethscription(
        {
          creator: creation_event['address'],
          previous_owner: creation_event['address'],
          current_owner: initial_owner,
          initial_owner: initial_owner,
          content_uri: fixed_uri,
          event_log_index: creation_event['logIndex'].to_i(16),
        }.merge(ethscription_attrs)
      )
      
      save_if_valid_and_no_ethscription_created!(potentially_valid)
    end
  end
  
  def save_if_valid_and_no_ethscription_created!(ethscription)
    # if @already_created_ethscription.nil?
    #   raise "Must initialize @already_created_ethscription"
    # end
    
    # if !@already_created_ethscription && ethscription.valid_ethscription?
    #   ethscription.save!
    #   @already_created_ethscription = true
    # end
    # binding.pry
    if ethscription.valid_ethscription?
      ethscription.save!
    end
  end
  
  def ethscription_creation_events
    return [] unless EthTransaction.contracts_create_ethscriptions?(block_number)
    
    ordered_events.select do |log|
      EthTransaction.contracts_create_ethscription_event_sig == log['topics'].first
    end
  end
  
  def transfer_attrs
    {
      block_number: block_number,
      block_timestamp: block_timestamp,
      transaction_index: transaction_index,
    }
  end
  
  def create_ethscription_transfers_from_input!
    return unless transfers_ethscription_via_input?
    
    concatenated_hashes = input_no_prefix.scan(/.{64}/).map { |hash| "0x#{hash}" }
    matching_ethscriptions = Ethscription.where(transaction_hash: concatenated_hashes)

    sorted_ethscriptions = concatenated_hashes.map do |hash|
      matching_ethscriptions.detect { |e| e.transaction_hash == hash }
    end.compact
  
    sorted_ethscriptions.each_with_index do |ethscription, index|
      ethscription_transfers.create!(
        {
          ethscription_transaction_hash: ethscription.transaction_hash,
          from_address: from_address,
          to_address: to_address,
          transfer_index: transfer_index,
          # creation_method: :input
        }.merge(transfer_attrs)
      )
    end
  end
  
  def create_ethscription_transfers_from_events!
    ethscription_transfer_events.each do |log|
      topics = log['topics']
      event_type = topics.first
      
      if event_type == EthTransaction.esip1_transfer_event_signature
        begin
          event_to = Eth::Abi.decode(['address'], topics.third).first
          ethscription_transaction_hash = Eth::Abi.decode(['bytes32'], topics.third).first
        rescue Eth::Abi::DecodingError
          next
        end
      
        target_ethscription = Ethscription.find_by(transaction_hash: ethscription_transaction_hash)
  
        if target_ethscription.present?
          ethscription_transfers.create!(
            {
              ethscription_transaction_hash: target_ethscription.transaction_hash,
              from_address: log['address'],
              to_address: event_to,
              event_log_index: log['logIndex'].to_i(16),
              transfer_index: transfer_index, #get_and_consume_transfer_index,
            }.merge(transfer_attrs)
          )
        end
      elsif event_type == EthTransaction.esip2_transfer_event_signature
        begin
          event_previous_owner = Eth::Abi.decode(['address'], topics.second).first
          event_to = Eth::Abi.decode(['address'], topics.third).first
          ethscription_transaction_hash = Eth::Abi.decode(['bytes32'], topics.fourth).first
        rescue Eth::Abi::DecodingError
          next
        end
        
        target_ethscription = Ethscription.find_by(transaction_hash: ethscription_transaction_hash)
  
        if target_ethscription.present?
          ethscription_transfers.create!(
            {
              ethscription_transaction_hash: target_ethscription.transaction_hash,
              from_address: log['address'],
              to_address: event_to,
              event_log_index: log['logIndex'].to_i(16),
              transfer_index: transfer_index, #get_and_consume_transfer_index,
              enforced_previous_owner: event_previous_owner,
            }.merge(transfer_attrs)
          )
        end
      end
    end
  end
  
  def transfers_ethscription_via_input?
    valid_length = if EthTransaction.esip5_enabled?(block_number)
      input_no_prefix.length > 0 && input_no_prefix.length % 64 == 0
    else
      input_no_prefix.length == 64
    end
    
    to_address.present? && valid_length
  end  
  
  def transfers_ethscription_via_event?
    ethscription_transfer_events.present?
  end
  
  def ethscription_transfer_events
    ordered_events.select do |log|
      EthTransaction.contract_transfer_event_signatures(block_number).include?(log['topics'].first)
    end
  end
  
  def ordered_events
    logs.select do |log|
      !log['removed']
    end.sort_by do |log|
      log['logIndex'].to_i(16)
    end
  end
  
  def input_no_prefix
    hex_string = input.dup
    hex_string.slice!(0, 2) if hex_string.start_with?("0x")
    hex_string
  end
  
  def essential_attributes
    attributes.slice(
      "transaction_hash",
      "block_number",
      "from_address",
      "to_address",
      "input",
      "status",
      "logs",
      "created_contract_address",
      "transaction_index",
      "gas_price",
      "gas_used",
      "transaction_fee",
      "value"
    )
  end
  
  def self.hex_to_utf8(hex_string)
    clean_hex_string = hex_string.gsub(/\A0x/, '')

    ary = clean_hex_string.scan(/../).map { |pair| pair.to_i(16) }
    
    utf8_string = ary.pack('C*').force_encoding('utf-8')
    
    unless utf8_string.valid_encoding?
      utf8_string = utf8_string.encode('UTF-8', invalid: :replace, undef: :replace, replace: "\uFFFD")
    end
    
    utf8_string.delete("\u0000")
  end
  
  def self.contracts_create_ethscriptions?(block_number)
    ENV['ETHEREUM_NETWORK'] == "eth-goerli" ||
    block_number >= 18130000
  end
  
  def self.esip5_enabled?(block_number)
    ENV['ETHEREUM_NETWORK'] == "eth-goerli" ||
    block_number >= 18330000
  end
  
  def self.esip2_enabled?(block_number)
    ENV['ETHEREUM_NETWORK'] == "eth-goerli" ||
    block_number >= 17764910
  end
  
  def self.esip1_enabled?(block_number)
    ENV['ETHEREUM_NETWORK'] == "eth-goerli" ||
    block_number >= 17672762
  end
  
  def self.contract_transfer_event_signatures(block_number)
    [].tap do |res|
      res << esip1_transfer_event_signature if esip1_enabled?(block_number)
      res << esip2_transfer_event_signature if esip2_enabled?(block_number)
    end
  end
  
  class << self
    extend Memoist
    
    def contracts_create_ethscription_event_sig
      "0x" + Digest::Keccak256.hexdigest(
        "ethscriptions_protocol_CreateEthscription(address,string)"
      )
    end
    memoize :contracts_create_ethscription_event_sig
    
    def esip2_transfer_event_signature
      "0x" + Digest::Keccak256.hexdigest(
        "ethscriptions_protocol_TransferEthscriptionForPreviousOwner(address,address,bytes32)"
      )
    end
    memoize :esip2_transfer_event_signature
    
    def esip1_transfer_event_signature
      "0x" + Digest::Keccak256.hexdigest(
        "ethscriptions_protocol_TransferEthscription(address,bytes32)"
      )
    end
    memoize :esip1_transfer_event_signature
  end
end

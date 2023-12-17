class Ethscription < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :ethscription
  
  has_many :ethscription_transfers, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_many :ethscription_ownership_versions, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  after_create :create_initial_transfer!, :notify_eth_transaction
  
  MAX_MIMETYPE_LENGTH = 1000
  
  def notify_eth_transaction
    if eth_transaction.already_created_ethscription.nil?
      raise "Need eth_transaction.already_created_ethscription"
    end
    
    eth_transaction.already_created_ethscription = true
  end
  
  def create_initial_transfer!
    eth_transaction.ethscription_transfers.create!(
      {
        ethscription_transaction_hash: transaction_hash,
        from_address: creator,
        to_address: initial_owner,
        transfer_index: 0
      }.merge(eth_transaction.transfer_attrs)
    )
  end
  
  def current_ownership_version
    ethscription_ownership_versions.newest_first.first
  end
  
  def content
    parsed_data_uri&.decoded_data
  end
  
  def valid_data_uri?
    DataUri.valid?(content_uri)
  end
  
  def parsed_data_uri
    return unless valid_data_uri?
    DataUri.new(content_uri)
  end
  
  def content_uri=(input)
    super(input)
    
    if input.nil?
      self.valid_data_uri = false
      self.esip6 = nil
      self.content_sha = nil
      return
    end
    
    if valid_data_uri?
      self.content_sha = "0x" + Digest::SHA256.hexdigest(input)
      self.esip6 = DataUri.esip6?(input)
      set_mimetype
    end
  end
  
  def set_mimetype
    # TODO: Do we still need this?
    self.mimetype = parsed_data_uri.mimetype.first(MAX_MIMETYPE_LENGTH)
    
    media_type, mime_subtype = self.mimetype.split('/')
    
    self.media_type = media_type
    self.mime_subtype = mime_subtype
  end
  
  def valid_ethscription?
    raise "Need content_uri" if content_uri.nil?
    if eth_transaction.already_created_ethscription.nil?
      binding.pry
      raise "Need eth_transaction.already_created_ethscription"
    end
    # 
    eth_transaction.already_created_ethscription == false &&
    # [creator, current_owner, initial_owner].all?(&:present?) &&
    initial_owner.present? &&
    valid_data_uri? &&
    (esip6 || content_is_unique?)
  end
  
  def content_is_unique?
    !Ethscription.exists?([
      '(block_number < :block_number OR ' +
      '(block_number = :block_number AND transaction_index < :transaction_index)) AND ' +
      'content_sha = :content_sha',
      block_number: block_number,
      transaction_index: transaction_index,
      content_sha: content_sha
    ])
  end
end

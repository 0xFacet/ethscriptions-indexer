class Ethscription < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :ethscription
  
  has_many :ethscription_transfers, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_many :ethscription_ownership_versions, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_one :token_item,
    foreign_key: :ethscription_transaction_hash,
    primary_key: :transaction_hash,
    inverse_of: :ethscription
  
  has_one :token,
    foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :transaction_hash,
    inverse_of: :deploy_ethscription
    
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  before_validation :set_derived_attributes, on: :create
  after_create :create_initial_transfer!
  
  MAX_MIMETYPE_LENGTH = 1000
  
  def create_initial_transfer!
    ethscription_transfers.create!(
      {
        from_address: creator,
        to_address: initial_owner,
        transfer_index: eth_transaction.transfer_index,
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
  
  def content_sha
    "0x" + Digest::SHA256.hexdigest(content_uri)
  end

  def esip6
    DataUri.esip6?(content_uri)
  end
  
  def mimetype
    parsed_data_uri&.mimetype&.first(MAX_MIMETYPE_LENGTH)
  end

  def media_type
    mimetype&.split('/')&.first
  end

  def mime_subtype
    mimetype&.split('/')&.last
  end
  
  def valid_ethscription?
    initial_owner.present? &&
    valid_data_uri? &&
    (esip6 || content_is_unique?)
  end
  
  def content_is_unique?
    !Ethscription.exists?(content_sha: content_sha)
  end
  
  def self.scope_checksum(scope)
    subquery = scope.select(:transaction_hash)
    hash_value = Ethscription.from(subquery, :ethscriptions)
      .select("encode(digest(array_to_string(array_agg(transaction_hash), ''), 'sha256'), 'hex')
        as hash_value")
      .take
      .hash_value
  end
  
  def as_json(options = {})
    if options[:include_transfers]
      super(options.merge(include: :ethscription_transfers))
    else
      super(options)
    end
  end
  
  private
  
  def set_derived_attributes
    self[:content_sha] = content_sha
    self[:esip6] = esip6
    self[:mimetype] = mimetype
    self[:media_type] = media_type
    self[:mime_subtype] = mime_subtype
  end
end

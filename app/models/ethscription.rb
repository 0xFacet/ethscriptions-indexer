class Ethscription < ApplicationRecord
  include DataValidationHelper
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscription
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :ethscription
  
  has_many :ethscription_transfers, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_many :ethscription_ownership_versions, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  before_validation :set_derived_attributes, on: :create
  after_create :create_initial_transfer!
  
  MAX_MIMETYPE_LENGTH = 1000
  
  def create_initial_transfer!
    eth_transaction.ethscription_transfers.create!(
      {
        ethscription_transaction_hash: transaction_hash,
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
    # TODO: Do we still need this?
    parsed_data_uri&.mimetype&.first(MAX_MIMETYPE_LENGTH)
  end

  def media_type
    mimetype&.split('/')&.first
  end

  def mime_subtype
    mimetype&.split('/')&.last
  end
  
  def valid_ethscription?
    raise "Need content_uri" if content_uri.nil?
    # [creator, current_owner, initial_owner].all?(&:present?) &&
    initial_owner.present? &&
    valid_data_uri? &&
    (esip6 || content_is_unique?)
  end
  
  def content_is_unique?
    !Ethscription.exists?(content_sha: content_sha)
  end
  
  def essential_attributes
    attributes.slice(
      "transaction_hash",
      "block_number",
      "from_address",
      "to_address",
      "creator",
      "initial_owner",
      "current_owner",
      "previous_owner",
      "content_sha",
    )
  end
  
  def self.set_ethscription_numbers_no_duplicate_jobs(since = nil)
    return if Delayed::Job.where("handler LIKE ?", "%set_ethscription_numbers%").exists?
          
    Ethscription.delay(priority: 1).set_ethscription_numbers(since)
  end
  
  def self.set_ethscription_numbers(since = nil)
    ActiveRecord::Base.transaction do
      range_condition = since ? "created_at > ?" : "1=1"
      
      Ethscription.where(range_condition, since).update_all(ethscription_number: nil)
      
      ActiveRecord::Base.connection.execute <<-SQL
        WITH max_num AS (
          SELECT COALESCE(MAX(ethscription_number), 0) AS max_val FROM ethscriptions
        ), cte AS (
          SELECT 
            id, 
            ROW_NUMBER() OVER (
              ORDER BY block_number, transaction_index
            ) - 1 + max_val AS new_ethscription_number
          FROM 
            ethscriptions, max_num
          WHERE
          ethscription_number IS NULL
        )
        UPDATE
          ethscriptions
        SET
          ethscription_number = cte.new_ethscription_number
        FROM
          cte
        WHERE
          ethscriptions.id = cte.id;
      SQL
      
      Rails.cache.clear
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

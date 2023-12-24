class Collection < ApplicationRecord
  store_accessor :stats,
    :daily_volume,
    :all_time_volume,
    :daily_sale_count,
    :all_time_sale_count,
    :unique_holder_count,
    :number_listed,
    :floor_price
  
  extend FriendlyId
  friendly_id :name, use: :slugged
  
  has_many :collection_items, dependent: :destroy
  has_many :ethscriptions, through: :collection_items
  
  def self.update_all_stats
    find_each do |collection|
      collection.delay(priority: 10).update_stats!
    end
  end
  
  def update_stats!
    with_lock do
      self.daily_volume = calculate_volume(since: 1.day.ago).to_i.to_s
      self.all_time_volume = calculate_volume(since: 100.years.ago).to_i.to_s
      self.daily_sale_count = calculate_sale_count(since: 1.day.ago)
      self.all_time_sale_count = calculate_sale_count(since: 100.years.ago)
      self.unique_holder_count = compute_unique_holder_count
      self.number_listed = compute_number_listed
      self.floor_price = compute_floor_price_for_json
      
      save!
    end
  end
  
  def calculate_volume(since:)
    EthscriptionTransfer.where(
      from: Listing.current_valid_marketplaces,
      ethscription_id: collection_ethscriptions.select(:id)
    ).joins(:eth_block).where("eth_blocks.timestamp > ?", since).sum(:sale_price)
  end
  
  def calculate_sale_count(since:)
    EthscriptionTransfer.where(
      from: Listing.current_valid_marketplaces,
      ethscription_id: collection_ethscriptions.select(:id)
    ).joins(:eth_block).where("eth_blocks.timestamp > ? AND sale_price > 0", since).count
  end
  
  def collection_ethscriptions
    Ethscription.joins(:collection_items).where(collection_items: { collection_id: id })
  end
  
  def collection_listings
    Listing.valid.where(ethscription_id: collection_ethscriptions.select(:transaction_hash))
  end
  
  def compute_unique_holder_count
    escrowed = collection_ethscriptions.where(current_owner: Listing.current_valid_marketplaces).distinct.count(:previous_owner)
    owned = collection_ethscriptions.where.not(current_owner: Listing.current_valid_marketplaces).distinct.count(:current_owner)
    
    owned + escrowed
  end
  
  def compute_number_listed
    collection_listings.count
  end
  
  def compute_floor_price_for_json
    collection_listings.minimum(:price)&.to_i&.to_s
  end
  
  def self.sample
    collection = Collection.first

    if collection
      item_json = collection.collection_items.limit(2).map do |item|
        {
          ethscription_id: item.ethscription_id.to_s,
          name: item.name.to_s,
          description: item.description.to_s,
          external_url: item.external_url.to_s,
          background_color: item.background_color.to_s,
          item_index: item.item_index,
          item_attributes: item.item_attributes
        }
      end
      
      json_response = {
        name: collection.name,
        description: collection.description.to_s,
        total_supply: collection.total_supply.to_s,
        logo_image_uri: collection.logo_image_uri.to_s,
        banner_image_uri: collection.banner_image_uri.to_s,
        background_color: collection.background_color.to_s,
        twitter_link: collection.twitter_link.to_s,
        website_link: collection.website_link.to_s,
        discord_link: collection.discord_link.to_s,
        collection_items: item_json
      }
    end

    JSON.pretty_generate(json_response)
  end
  
  def self.import_generic(url)
    response = HTTParty.get(url)
    obj = JSON.parse(response.body)
    
    ActiveRecord::Base.transaction do
      collection = create_or_find_by!(
        name: obj['name']
      )
      
      collection.update!(
        total_supply: obj['collection_items'].length,
        description: obj['description'],
        background_color: obj['background_color'],
        logo_image_uri: obj['logo_image_uri'],
        banner_image_uri: obj['banner_image_uri'],
        website_link: obj['website_link'],
        twitter_link: obj['twitter_link'],
        discord_link: obj['discord_link'],
      )
      
      collection_items_attributes = obj['collection_items'].map do |ethscription|
        {
          collection_id: collection.id,
          ethscription_id: ethscription['ethscription_id'],
          name: ethscription['name'],
          item_attributes: ethscription['item_attributes'],
          item_index: Integer(ethscription['item_index']),
          description: ethscription['description'],
          external_url: ethscription['external_url'],
          background_color: ethscription['background_color']
        }
      end
      
      id_dupes = collection_items_attributes.group_by{|i| i[:ethscription_id]}.select{|k,v| v.size > 1}.map(&:first)
      
      unless id_dupes.blank?
        raise "Not unique: #{id_dupes}"
      end
      
      valid_id_count = Ethscription.where(transaction_hash: collection_items_attributes.map{|i| i[:ethscription_id]}).count
      
      unless valid_id_count == collection_items_attributes.length
        raise "Invalid ids"
      end
      
      CollectionItem.import!(collection_items_attributes,
        batch_size: 1_000,
        on_duplicate_key_update: {
        conflict_target: [:ethscription_id, :collection_id],
        columns: [
          :name,
          :item_attributes,
          :item_index,
          :description,
          :external_url,
          :background_color
        ]
      })
      
      collection.update_stats!
    end
  end
end

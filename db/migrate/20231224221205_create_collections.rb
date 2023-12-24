class CreateCollections < ActiveRecord::Migration[7.1]
  def change
    create_table :collections do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :logo_image_uri
      t.string :banner_image_uri
      t.integer :total_supply
      t.text :description
      t.string :twitter_link
      t.string :discord_link
      t.string :website_link
      t.string :background_color
      t.jsonb :stats, default: {}, null: false
      
      t.index :name, unique: true
      t.index :slug, unique: true
      
      t.timestamps
    end
  end
end

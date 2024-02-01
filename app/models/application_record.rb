class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  if Rails.env.production? && ENV['FOLLOWER_DATABASE_URL'].present?
    connects_to database: { writing: :primary, reading: :primary_replica }
  end
end

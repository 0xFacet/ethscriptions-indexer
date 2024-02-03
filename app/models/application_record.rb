class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  def self.use_replica_database?
    Rails.env.test? ?
      ENV['TEST_REPLICA_DATABASE_URL'].present? :
      ENV['REPLICA_DATABASE_URL'].present?
  end
  
  if use_replica_database?
    connects_to database: { writing: :primary, reading: :primary_replica }
  else
    connects_to database: { writing: :primary }
  end
end

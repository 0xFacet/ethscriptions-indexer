module DataValidationHelper
  def self.validate_transfers(old_db)
    field_mapping = {
      transaction_hash: "transaction_hash",
      from_address: "from",
      to_address: "to",
      block_number: "block_number",
    }
  
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql',
      host:     'localhost',
      database: old_db,
      username: `whoami`.chomp,
      password: ''
    )
  
    remote_records = OldEthscription.where("(fixed_content_unique = true OR esip6 = true) AND fixed_valid_data_uri = true").select(:transaction_hash).includes(:ethscription_transfers).to_a
  
    ActiveRecord::Base.establish_connection
  
    local_transfers = EthscriptionTransfer.all.select(*field_mapping.keys).index_by(&:transaction_hash)
  
    remote_records.each do |ethscription|
      transfers = ethscription.valid_transfers
  
      transfers.each do |transfer|
        local_transfer = local_transfers[transfer.transaction_hash]
  
        checks = field_mapping.each_with_object({}) do |(local_field, remote_field), checks|
          checks[local_field.to_s] = local_transfer.send(local_field) == transfer.send(remote_field)
        end
  
        failed_checks = checks.select { |_, result| !result }
  
        if failed_checks.any?
          binding.pry
          puts "Checks failed for transaction_hash #{local_transfer.transaction_hash}: #{failed_checks.keys.join(', ')}"
        end
      end
    end
    nil
  ensure
    ActiveRecord::Base.establish_connection
  end
  
  def bulk_validate(old_db)
    field_mapping = {
      transaction_hash: "transaction_hash",
      current_owner: "current_owner",
      creator: "creator",
      initial_owner: "initial_owner",
      previous_owner: "previous_owner",
      content_uri: "content_uri_unicode_fixed",
      content_sha: "fixed_sha",
      ethscription_number: "ethscription_number"
    }
    
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql',
      host:     'localhost',
      database: old_db,
      username: `whoami`.chomp,
      password: ''
    )
  
    remote_records = Ethscription.select(field_mapping.values).all.index_by(&:transaction_hash)
    
    ActiveRecord::Base.establish_connection
  
    local_records = Ethscription.all.select(field_mapping.keys)
  
    local_records.each do |local_record|
      remote_record = remote_records[local_record.transaction_hash]
  
      checks = field_mapping.each_with_object({}) do |(local_field, remote_field), checks|
        if local_field == :previous_owner
          checks[local_field.to_s] = remote_record.send(remote_field).nil? || local_record.send(local_field) == remote_record.send(remote_field)
        elsif local_field == :content_sha
          checks[local_field.to_s] = local_record.send(local_field) == "0x" + remote_record.send(remote_field)
        elsif local_field == :ethscription_number
          checks[local_field.to_s] = remote_record.send(remote_field).nil? || local_record.send(local_field) == remote_record.send(remote_field)
        else
          checks[local_field.to_s] = local_record.send(local_field) == remote_record.send(remote_field)
        end
      end
  
      failed_checks = checks.select { |_, result| !result }
  
      if failed_checks.any?
        binding.pry
        puts "Checks failed for transaction_hash #{local_record.transaction_hash}: #{failed_checks.keys.join(', ')}"
      else
        puts "Checks passed for transaction_hash #{local_record.transaction_hash}"
      end
    end
    
    nil
  ensure
    ActiveRecord::Base.establish_connection
  end
  
  def validate_with_old_indexer
    url = "https://api.ethscriptions.com/api/ethscriptions/#{transaction_hash}"
    response = HTTParty.get(url).parsed_response
  
    return true if response['image_removed_by_request_of_rights_holder']
    
    checks = {
      'current_owner' => current_owner == response['current_owner'],
      'creator' => creator == response['creator'],
      'initial_owner' => initial_owner == response['initial_owner'],
      'previous_owner' => (!response['previous_owner'] || previous_owner == response['previous_owner']),
      'content_uri' => content_uri == response['content_uri'],
      'content_sha' => content_sha == "0x" + response['sha'],
      'ethscription_number' => ethscription_number == response['ethscription_number']
    }
  
    failed_checks = checks.select { |_, result| !result }
  
    if failed_checks.any?
      puts "Checks failed for transaction_hash #{transaction_hash}: #{failed_checks.keys.join(', ')}"
      return false
    end
  
    true
  end
  
  class OldEthscription < ApplicationRecord
    self.table_name = "ethscriptions"
    has_many :ethscription_transfers,
      primary_key: 'id',
      foreign_key: 'ethscription_id'
      
    def valid_transfers
      sorted = ethscription_transfers.sort_by do |transfer|
        [transfer.block_number, transfer.transaction_index, transfer.event_log_index]
      end
      
      sorted.each.with_object([]) do |transfer, valid|
        basic_rule_passes = valid.empty? ||
                            transfer.from == valid.last.to
    
        previous_owner_rule_passes = transfer.enforced_previous_owner.nil? ||
                                      transfer.enforced_previous_owner == valid.last&.from
    
        if basic_rule_passes && previous_owner_rule_passes
          valid << transfer
        end
      end
    end
  end
end

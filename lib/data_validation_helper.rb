module DataValidationHelper
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
end
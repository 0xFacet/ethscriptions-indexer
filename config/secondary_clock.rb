require 'clockwork'
require './config/boot'
require './config/environment'
require 'active_support/time'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  error_handler do |error|
    report_exception_every = 15.minutes
    
    exception_key = ["clockwork-airbrake", error.class, error.message, error.backtrace[0]].to_cache_key
    
    last_reported_at = Rails.cache.read(exception_key)

    if last_reported_at.blank? || (Time.zone.now - last_reported_at > report_exception_every)
      Airbrake.notify(error)
      Rails.cache.write(exception_key, Time.zone.now)
    end
  end

  # every(15.seconds, 'handle_short_reorgs') do
  #   EthBlock.handle_short_reorgs
  # end
  
  # every(1.minute, 'handle_medium_reorgs') do
  #   EthBlock.delay.handle_medium_reorgs
  # end
  
  # every(5.minutes, 'handle_long_reorgs') do
  #   EthBlock.delay.handle_long_reorgs
  # end
  
  every(5.minutes, 'set_ethscription_numbers') do
    EthTransaction.delay.prune_transactions(priority: 1)
  end
  
  every(20.minutes, 'set_ethscription_numbers') do
    Ethscription.set_ethscription_numbers_no_duplicate_jobs(1.hour.ago)
  end
end

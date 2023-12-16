def no_ar_logging
  ActiveRecord::Base::logger.level = 1
end

def run_job(id)
  Delayed::Worker.new.run( Delayed::Job.find(id) )
end

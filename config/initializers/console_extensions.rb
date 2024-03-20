if defined?(Rails::Console)
  def no_ar_logging
    ActiveRecord::Base::logger.level = 1
  end
  
  def run_job(id)
    Delayed::Worker.new.run( Delayed::Job.find(id) )
  end
  
  class Object
    def gzip
      Zlib.gzip(self)
    end
    
    def unzip
      Zlib.gunzip(self)
    end
    
    def sha
      "0x" + Digest::SHA256.hexdigest(self)
    end
  end
end


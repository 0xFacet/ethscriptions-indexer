class ApplicationController < ActionController::API
  private
  
  def parse_param_array(param, limit: 100)
    Array(param).map(&:to_s).map(&:downcase).uniq.take(limit)
  end
end

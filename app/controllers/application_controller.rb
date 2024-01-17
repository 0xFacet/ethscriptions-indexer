class ApplicationController < ActionController::API
  private
  
  def parse_param_array(param, limit: 100)
    Array(param).map(&:to_s).map(&:downcase).uniq.take(limit)
  end
  
  def filter_by_params(scope, *param_names)
    param_names.each do |param_name|
      param_values = parse_param_array(params[param_name])
      scope = param_values.present? ? scope.where(param_name => param_values) : scope
    end
    scope
  end
  
  def pagination_params(default_page: 1, default_per_page: 25, max_page: 10, max_per_page: 50)
    page = (params[:page] || default_page).to_i.clamp(1, max_page)
    per_page = (params[:per_page] || default_per_page).to_i.clamp(1, max_per_page)

    if authorized?
      page = params[:page].to_i if params[:page].present?
      per_page = params[:per_page].to_i if params[:per_page].present?
    end

    [page, per_page]
  end

  def authorized?
    authorization_header = request.headers['Authorization']
    return false if authorization_header.blank?
  
    token = authorization_header.remove('Bearer ').strip
    stored_tokens = JSON.parse(ENV.fetch('API_AUTH_TOKEN', "[]"))
    
    stored_tokens.include?(token)
  rescue JSON::ParserError
    Airbrake.notify("Invalid API_AUTH_TOKEN format: #{ENV.fetch('API_AUTH_TOKEN', "[]")}")
    false
  end
  
  def numbers_to_strings(result)
    result = result.as_json

    case result
    when String
      format_decimal_or_string(result)
    when Numeric
      result.to_s
    when Hash
      result.deep_transform_values { |value| numbers_to_strings(value) }
    when Array
      result.map { |value| numbers_to_strings(value) }
    else
      result
    end
  end
  
  def big_decimal?(num)
    BigDecimal(num)
  rescue ArgumentError
    false
  end
  
  def format_decimal_or_string(str)
    return str unless dec = big_decimal?(str)
    
    (dec.to_i == dec ? dec.to_i : dec).to_s
  end
end

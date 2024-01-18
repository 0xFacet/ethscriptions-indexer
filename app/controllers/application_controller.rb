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
  
  def paginate(scope)
    sort_order = params[:sort_order]&.downcase == "asc" ? :oldest_first : :newest_first

    max_results = (params[:max_results] || 25).to_i.clamp(1, 50)

    if authorized? && params[:max_results].present?
      max_results = params[:max_results]
    end
    
    scope = scope.public_send(sort_order)
    
    starting_item = scope.model.find_by_page_key(params[:page_key])

    if starting_item
      scope = starting_item.public_send(sort_order, scope).after
    end

    results = scope.limit(max_results + 1).to_a
    
    has_more = results.size > max_results
    results.pop if has_more
    
    page_key = results.last&.page_key
    pagination_response = {
      page_key: page_key,
      has_more: has_more
    }
    
    [results, pagination_response]
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

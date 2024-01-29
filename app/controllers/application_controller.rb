class ApplicationController < ActionController::API
  class RequestedRecordNotFound < StandardError; end
  
  rescue_from RequestedRecordNotFound, with: :record_not_found
  
  private
  
  delegate :expand_cache_key, to: ActiveSupport::Cache
  
  def parse_param_array(param, limit: 100)
    Array(param).map(&:to_s).map do |param|
      param =~ /\A0x([a-f0-9]{2})+\z/i ? param.downcase : param
    end.uniq.take(limit)
  end
  
  def filter_by_params(scope, *param_names)
    param_names.each do |param_name|
      param_values = parse_param_array(params[param_name])
      scope = param_values.present? ? scope.where(param_name => param_values) : scope
    end
    scope
  end
  
  def paginate(scope, results_limit: 50)
    sort_order = params[:sort_order]&.downcase == "asc" ? :oldest_first : :newest_first

    max_results = (params[:max_results] || 25).to_i.clamp(1, results_limit)

    if authorized? && params[:max_results].present?
      max_results = params[:max_results].to_i
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
    
    [results, pagination_response, sort_order]
  end

  def authorized?
    authorization_header = request.headers['Authorization']
    return false if authorization_header.blank?
  
    token = authorization_header.remove('Bearer ').strip
    stored_tokens = JSON.parse(ENV.fetch('API_AUTH_TOKENS', "[]"))
    
    stored_tokens.include?(token)
  rescue JSON::ParserError
    Airbrake.notify("Invalid API_AUTH_TOKEN format: #{ENV.fetch('API_AUTH_TOKENS', "[]")}")
    false
  end
  
  def cache_on_block(etag: nil, max_age: 6.seconds, cache_forever_with: nil, &block)
    if cache_forever_with
      current = EthBlock.cached_global_block_number
      diff = current - cache_forever_with
      max_age = [max_age, 1.day].max if diff > 64
    end
    
    etag_components = [EthBlock.most_recently_imported_blockhash, etag]
    
    set_cache_control_headers(max_age: max_age, etag: etag_components, &block)
  end
  
  def set_cache_control_headers(max_age:, etag: nil)
    version = Rails.cache.fetch("etag-version") { rand }
    addition = ActionController::Base.perform_caching ? '' : rand
    versioned_etag = expand_cache_key([etag, version, addition])
    
    expires_in(max_age, public: true)
    response.headers['Vary'] = 'Authorization'
    
    yield if stale?(etag: versioned_etag, public: true)
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
  
  def record_not_found
    render json: { error: "Not found" }, status: 404
  end
end

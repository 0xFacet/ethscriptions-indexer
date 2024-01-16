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

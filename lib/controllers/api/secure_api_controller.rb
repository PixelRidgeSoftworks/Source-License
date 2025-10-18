# frozen_string_literal: true

require 'json'
require 'rack/attack'
require_relative '../../services/secure_license_service'
require_relative '../../license_generator'

# Secure API Controller with rate limiting and security enhancements
class SecureApiController < Sinatra::Base
  configure do
    use Rack::Attack

    # Configure rate limiting with Redis if available, otherwise disable Rack::Attack
    if ENV['REDIS_URL'] && defined?(Redis)
      begin
        redis = Redis.new(url: ENV['REDIS_URL'])
        Rack::Attack.cache.store = redis
        puts '✓ Rack::Attack configured with Redis for rate limiting'
      rescue StandardError => e
        puts "Warning: Redis connection failed: #{e.message}"
        puts 'Warning: Rack::Attack rate limiting disabled - install Redis for production use'
        # Disable Rack::Attack if no Redis available
        Rack::Attack.enabled = false
      end
    else
      puts 'Warning: Redis not available - Rack::Attack rate limiting disabled'
      puts 'Note: Install Redis and set REDIS_URL environment variable for production rate limiting'
      # Disable Rack::Attack if no Redis available
      Rack::Attack.enabled = false
    end

    # Enable logging for production debugging
    enable :logging if ENV['APP_ENV'] == 'production'
  end

  before do
    content_type :json

    # Security headers
    headers 'X-Content-Type-Options' => 'nosniff',
            'X-Frame-Options' => 'DENY',
            'X-XSS-Protection' => '1; mode=block',
            'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'

    # CORS headers for API endpoints
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => %w[GET POST OPTIONS],
            'Access-Control-Allow-Headers' => 'Content-Type, Authorization'

    # Extract request info for security logging
    @request_info = {
      ip_address: request.ip,
      user_agent: request.user_agent,
      endpoint: request.path_info,
      method: request.request_method,
    }
  end

  # Custom exception for batch validation errors
  class BatchValidationError < StandardError; end

  # Batch operation helper methods

  # Parse and validate batch request body
  def parse_batch_request_body
    request_body = request.body.read
    request.body.rewind
    JSON.parse(request_body)
  end

  # Validate batch data structure and constraints
  def validate_batch_data(batch_data)
    raise BatchValidationError, 'Invalid batch request format' unless batch_data['operations'].is_a?(Array)

    raise BatchValidationError, 'Batch size exceeds maximum (10 operations)' if batch_data['operations'].length > 10

    return unless batch_data['operations'].empty?

    raise BatchValidationError, 'Batch cannot be empty'
  end

  # Process all operations in the batch
  def process_batch_operations(operations)
    results = []

    operations.each_with_index do |operation, index|
      result = process_single_batch_operation(operation, index)

      results << {
        index: index,
        operation: operation['type'],
        license_key: SecureLicenseService.partial_license_key(operation['license_key']),
        result: result,
      }
    end

    results
  end

  # Process a single batch operation
  def process_single_batch_operation(operation, index)
    request_info_with_index = @request_info.merge(batch_index: index)

    case operation['type']
    when 'validate'
      SecureLicenseService.validate_license(
        license_key: operation['license_key'],
        machine_fingerprint: operation['machine_fingerprint'],
        machine_id: operation['machine_id'],
        request_info: request_info_with_index
      )
    when 'activate'
      SecureLicenseService.activate_license(
        license_key: operation['license_key'],
        machine_fingerprint: operation['machine_fingerprint'],
        machine_id: operation['machine_id'],
        request_info: request_info_with_index
      )
    when 'deactivate'
      SecureLicenseService.deactivate_license(
        license_key: operation['license_key'],
        machine_fingerprint: operation['machine_fingerprint'],
        machine_id: operation['machine_id'],
        request_info: request_info_with_index
      )
    when 'status'
      SecureLicenseService.get_license_status(
        license_key: operation['license_key'],
        request_info: request_info_with_index
      )
    else
      { success: false, error: 'Invalid operation type' }
    end
  rescue StandardError
    { success: false, error: 'Operation failed' }
  end

  # Build the final batch response
  def build_batch_response(batch_data, results)
    {
      success: true,
      batch_id: SecureRandom.hex(8),
      operations_count: batch_data['operations'].length,
      results: results,
      timestamp: Time.now.iso8601,
    }.to_json
  end

  # Log batch operation errors
  def log_batch_error(error)
    SecureLicenseService.log_security_incident(
      event_type: 'batch_operation_error',
      request_info: @request_info,
      details: { error: error.message }
    )
  end

  # Rate limiting helper
  def check_rate_limit(key_type, key_value, max_requests = 60)
    rate_limit = SecureLicenseService.check_rate_limit(
      key_type: key_type,
      key_value: key_value,
      endpoint: @request_info[:endpoint],
      max_requests: max_requests,
      window_minutes: 1
    )

    unless rate_limit[:allowed]
      status 429
      headers 'Retry-After' => '60'
      return {
        error: 'Rate limit exceeded',
        retry_after: 60,
        timestamp: Time.now.iso8601,
      }.to_json
    end

    # Add rate limit headers
    headers 'X-RateLimit-Limit' => max_requests.to_s,
            'X-RateLimit-Remaining' => rate_limit[:remaining].to_s,
            'X-RateLimit-Reset' => rate_limit[:reset_at].to_i.to_s

    nil
  end

  # Handle preflight requests
  options '*' do
    200
  end

  # Secure license validation endpoint
  get '/:key/validate' do
    # Rate limiting by IP and license key
    rate_limit_response = check_rate_limit('ip', request.ip, 100)
    return rate_limit_response if rate_limit_response

    rate_limit_response = check_rate_limit('license', params[:key], 60)
    return rate_limit_response if rate_limit_response

    # Extract request parameters
    machine_fingerprint = params[:machine_fingerprint]
    machine_id = params[:machine_id]

    # Use secure license service for validation
    result = SecureLicenseService.validate_license(
      license_key: params[:key],
      machine_fingerprint: machine_fingerprint,
      machine_id: machine_id,
      request_info: @request_info
    )

    # Set appropriate HTTP status
    unless result[:valid]
      status 400 if result[:error] && result[:error] != 'License not found'
      status 404 if result[:error] == 'License not found'
      status 429 if result[:error]&.include?('Rate limit')
    end

    result.to_json
  rescue StandardError => e
    # Log security incident
    SecureLicenseService.log_security_incident(
      event_type: 'validation_error',
      license_key: params[:key],
      request_info: @request_info,
      details: { error: e.message }
    )

    status 500
    { valid: false, error: 'Internal server error', timestamp: Time.now.iso8601 }.to_json
  end

  # Secure license activation endpoint
  post '/:key/activate' do
    # Rate limiting by IP and license key
    rate_limit_response = check_rate_limit('ip', request.ip, 50)
    return rate_limit_response if rate_limit_response

    rate_limit_response = check_rate_limit('license', params[:key], 30)
    return rate_limit_response if rate_limit_response

    # Parse request body for machine_id and other data
    request_body = request.body.read
    request.body.rewind

    activation_data = {}
    activation_data = JSON.parse(request_body) unless request_body.empty?

    machine_fingerprint = activation_data['machine_fingerprint'] || params[:machine_fingerprint]
    machine_id = activation_data['machine_id'] || params[:machine_id]

    # Use secure license service for activation
    result = SecureLicenseService.activate_license(
      license_key: params[:key],
      machine_fingerprint: machine_fingerprint,
      machine_id: machine_id,
      request_info: @request_info
    )

    # Set appropriate HTTP status
    unless result[:success]
      status 404 if result[:error] == 'Invalid license'
      status 400 if result[:error] && !result[:error].include?('Rate limit') && result[:error] != 'Invalid license'
      status 429 if result[:error]&.include?('Rate limit')
    end

    result.to_json
  rescue JSON::ParserError
    status 400
    { success: false, error: 'Invalid JSON in request body', timestamp: Time.now.iso8601 }.to_json
  rescue StandardError => e
    # Log security incident
    SecureLicenseService.log_security_incident(
      event_type: 'activation_error',
      license_key: params[:key],
      request_info: @request_info,
      details: { error: e.message }
    )

    status 500
    { success: false, error: 'Internal server error', timestamp: Time.now.iso8601 }.to_json
  end

  # Secure license deactivation endpoint
  post '/:key/deactivate' do
    # Rate limiting by IP and license key
    rate_limit_response = check_rate_limit('ip', request.ip, 50)
    return rate_limit_response if rate_limit_response

    rate_limit_response = check_rate_limit('license', params[:key], 30)
    return rate_limit_response if rate_limit_response

    # Parse request body for machine_id and other data
    request_body = request.body.read
    request.body.rewind

    deactivation_data = {}
    deactivation_data = JSON.parse(request_body) unless request_body.empty?

    machine_fingerprint = deactivation_data['machine_fingerprint'] || params[:machine_fingerprint]
    machine_id = deactivation_data['machine_id'] || params[:machine_id]

    # Use secure license service for deactivation
    result = SecureLicenseService.deactivate_license(
      license_key: params[:key],
      machine_fingerprint: machine_fingerprint,
      machine_id: machine_id,
      request_info: @request_info
    )

    # Set appropriate HTTP status
    unless result[:success]
      status 404 if result[:error] == 'Invalid license'
      status 400 if result[:error] && !result[:error].include?('Rate limit') && result[:error] != 'Invalid license'
      status 429 if result[:error]&.include?('Rate limit')
    end

    result.to_json
  rescue JSON::ParserError
    status 400
    { success: false, error: 'Invalid JSON in request body', timestamp: Time.now.iso8601 }.to_json
  rescue StandardError => e
    # Log security incident
    SecureLicenseService.log_security_incident(
      event_type: 'deactivation_error',
      license_key: params[:key],
      request_info: @request_info,
      details: { error: e.message }
    )

    status 500
    { success: false, error: 'Internal server error', timestamp: Time.now.iso8601 }.to_json
  end

  # Secure license status endpoint
  get '/:key/status' do
    # Rate limiting by IP and license key
    rate_limit_response = check_rate_limit('ip', request.ip, 100)
    return rate_limit_response if rate_limit_response

    rate_limit_response = check_rate_limit('license', params[:key], 60)
    return rate_limit_response if rate_limit_response

    # Use secure license service for status check
    result = SecureLicenseService.get_license_status(
      license_key: params[:key],
      request_info: @request_info
    )

    # Set appropriate HTTP status
    unless result[:success]
      status 404 if result[:error] == 'License not found'
      status 400 if result[:error] && result[:error] != 'License not found'
    end

    result.to_json
  rescue StandardError => e
    # Log security incident
    SecureLicenseService.log_security_incident(
      event_type: 'status_error',
      license_key: params[:key],
      request_info: @request_info,
      details: { error: e.message }
    )

    status 500
    { success: false, error: 'Internal server error', timestamp: Time.now.iso8601 }.to_json
  end

  # Health check endpoint
  get '/health' do
    {
      status: 'ok',
      version: '2.0',
      timestamp: Time.now.iso8601,
      secure: true,
    }.to_json
  end

  # Enhanced JWT-based license validation (v2 feature)
  get '/:key/validate/jwt' do
    # Rate limiting by IP and license key
    rate_limit_response = check_rate_limit('ip', request.ip, 50)
    return rate_limit_response if rate_limit_response

    rate_limit_response = check_rate_limit('license', params[:key], 30)
    return rate_limit_response if rate_limit_response

    # Extract request parameters
    machine_fingerprint = params[:machine_fingerprint]
    machine_id = params[:machine_id]

    # Use secure license service for validation
    result = SecureLicenseService.validate_license(
      license_key: params[:key],
      machine_fingerprint: machine_fingerprint,
      machine_id: machine_id,
      request_info: @request_info
    )

    # If valid, generate JWT token with the result
    if result[:valid]
      jwt_token = SecureLicenseService.generate_license_jwt(result)
      result[:jwt_token] = jwt_token
    end

    # Set appropriate HTTP status
    unless result[:valid]
      status 400 if result[:error] && result[:error] != 'License not found'
      status 404 if result[:error] == 'License not found'
      status 429 if result[:error]&.include?('Rate limit')
    end

    result.to_json
  rescue StandardError => e
    # Log security incident
    SecureLicenseService.log_security_incident(
      event_type: 'jwt_validation_error',
      license_key: params[:key],
      request_info: @request_info,
      details: { error: e.message }
    )

    status 500
    { valid: false, error: 'Internal server error', timestamp: Time.now.iso8601 }.to_json
  end

  # Batch license operations (v2 feature)
  post '/licenses/batch' do
    # Enhanced rate limiting for batch operations
    rate_limit_response = check_rate_limit('ip', request.ip, 10)
    return rate_limit_response if rate_limit_response

    begin
      batch_data = parse_batch_request_body
      validate_batch_data(batch_data)

      results = process_batch_operations(batch_data['operations'])

      build_batch_response(batch_data, results)
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON in request body' }.to_json
    rescue BatchValidationError => e
      status 400
      { success: false, error: e.message }.to_json
    rescue StandardError => e
      log_batch_error(e)
      status 500
      { success: false, error: 'Batch operation failed' }.to_json
    end
  end

  # 404 handler for unmatched routes
  not_found do
    content_type :json
    status 404
    {
      error: 'Endpoint not found',
      timestamp: Time.now.iso8601,
      path: request.path_info,
    }.to_json
  end

  # Error handler
  error do
    content_type :json
    status 500
    {
      error: 'Internal server error',
      timestamp: Time.now.iso8601,
    }.to_json
  end
end

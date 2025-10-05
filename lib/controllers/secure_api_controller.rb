# frozen_string_literal: true

require 'json'
require 'rack/attack'
require_relative '../services/secure_license_service'
require_relative '../license_generator'

# Secure API Controller with rate limiting and security enhancements
class SecureApiController < Sinatra::Base
  configure do
    use Rack::Attack
    
    # Configure rate limiting
    Rack::Attack.cache.store = Rack::Attack::StoreProxy::RedisStoreProxy.new(Redis.new) if defined?(Redis)
    
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
            'Access-Control-Allow-Methods' => ['GET', 'POST', 'OPTIONS'],
            'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
    
    # Extract request info for security logging
    @request_info = {
      ip_address: request.ip,
      user_agent: request.user_agent,
      endpoint: request.path_info,
      method: request.request_method
    }
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
        timestamp: Time.now.iso8601
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
  get '/api/v2/license/:key/validate' do

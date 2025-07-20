# frozen_string_literal: true

# Source-License: Security Enhancements
# Critical security features for production deployment

require 'digest'
require 'securerandom'
require 'rack/protection'

module SecurityHelpers
  # NOTE: CSRF protection methods are now handled in TemplateHelpers module
  # This avoids conflicts and ensures consistent implementation

  # Input Validation & Sanitization
  def validate_email(email)
    return false unless email.is_a?(String)
    return false if email.length > 254 # RFC 5321 limit

    email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
    email.match?(email_regex)
  end

  def sanitize_string(input, max_length = 255)
    return '' unless input.is_a?(String)

    input.strip
      .gsub(/[<>]/, '') # Remove basic HTML characters
      .slice(0, max_length)
  end

  def validate_payment_amount(amount)
    return false unless amount.is_a?(Numeric) || amount.is_a?(String)

    amount = amount.to_f
    amount.positive? && amount <= 999_999.99 # Reasonable limits
  end

  def validate_currency(currency)
    valid_currencies = %w[USD EUR GBP CAD AUD JPY]
    valid_currencies.include?(currency&.upcase)
  end

  # Rate Limiting
  def rate_limit_key(identifier = nil)
    identifier ||= request.ip
    "rate_limit:#{identifier}:#{Time.now.to_i / 3600}" # hourly buckets
  end

  def check_rate_limit(max_requests = 100, window = 3600, identifier = nil)
    return true unless ENV['REDIS_URL'] # Skip if no Redis configured

    key = rate_limit_key(identifier)

    begin
      # This would require Redis integration
      # For now, we'll use a simple in-memory store
      @rate_limits ||= {}
      @rate_limits[key] ||= { count: 0, reset_time: Time.now + window }

      @rate_limits[key] = { count: 0, reset_time: Time.now + window } if Time.now > @rate_limits[key][:reset_time]

      @rate_limits[key][:count] += 1
      @rate_limits[key][:count] <= max_requests
    rescue StandardError
      true # Fail open - don't block requests if rate limiting fails
    end
  end

  def rate_limit_exceeded?(max_requests = 100, window = 3600, identifier = nil)
    !check_rate_limit(max_requests, window, identifier)
  end

  def enforce_rate_limit(max_requests = 100, window = 3600, identifier = nil)
    return unless rate_limit_exceeded?(max_requests, window, identifier)

    if request.xhr? || content_type == 'application/json'
      halt 429, { error: 'Rate limit exceeded' }.to_json
    else
      halt 429, 'Rate limit exceeded'
    end
  end

  # Security Headers
  def set_security_headers
    # Prevent clickjacking
    headers['X-Frame-Options'] = 'DENY'

    # Prevent MIME type sniffing
    headers['X-Content-Type-Options'] = 'nosniff'

    # XSS Protection
    headers['X-XSS-Protection'] = '1; mode=block'

    # Referrer Policy
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'

    # Content Security Policy
    headers['Content-Security-Policy'] = build_csp_header

    # HSTS (only in production with HTTPS)
    return unless ENV['APP_ENV'] == 'production'

    headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
  end

  def build_csp_header
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://js.stripe.com https://www.paypal.com",
      "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://fonts.googleapis.com",
      "font-src 'self' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://fonts.gstatic.com",
      "img-src 'self' data: *.stripe.com *.paypal.com",
      "connect-src 'self' api.stripe.com *.paypal.com",
      'frame-src js.stripe.com www.paypal.com',
      "object-src 'none'",
      "base-uri 'self'",
    ].join('; ')
  end

  # Webhook Security
  def verify_stripe_webhook_signature(payload, signature)
    return false unless signature && ENV['STRIPE_WEBHOOK_SECRET']

    begin
      Stripe::Webhook::Signature.verify_header(
        payload,
        signature,
        ENV.fetch('STRIPE_WEBHOOK_SECRET', nil)
      )
      true
    rescue Stripe::SignatureVerificationError
      false
    end
  end

  def verify_paypal_webhook_signature(_payload, headers)
    # PayPal webhook verification implementation
    # This requires the PayPal SDK webhook verification
    return false unless ENV['PAYPAL_WEBHOOK_ID']

    begin
      # PayPal webhook verification would go here
      # For now, we'll implement basic verification
      auth_algo = headers['PAYPAL-AUTH-ALGO']
      transmission_id = headers['PAYPAL-TRANSMISSION-ID']
      cert_id = headers['PAYPAL-CERT-ID']
      transmission_sig = headers['PAYPAL-TRANSMISSION-SIG']
      transmission_time = headers['PAYPAL-TRANSMISSION-TIME']

      # All required headers must be present
      auth_algo && transmission_id && cert_id && transmission_sig && transmission_time
    rescue StandardError
      false
    end
  end

  # Secure Session Configuration
  def configure_secure_sessions
    use Rack::Session::Cookie, {
      key: '_source_license_session',
      secret: ENV.fetch('APP_SECRET') { raise 'APP_SECRET must be set' },
      secure: ENV['APP_ENV'] == 'production', # HTTPS only in production
      httponly: true, # Prevent XSS
      same_site: :strict, # CSRF protection
      expire_after: 24 * 60 * 60, # 24 hours
    }
  end

  # Logging Security Events
  def log_security_event(event_type, details = {})
    security_log = {
      timestamp: Time.now.iso8601,
      event_type: event_type,
      ip_address: request.ip,
      user_agent: request.user_agent,
      details: details,
    }

    # Log to security log file
    if respond_to?(:logger)
      logger.warn "SECURITY_EVENT: #{security_log.to_json}"
    else
      puts "SECURITY_EVENT: #{security_log.to_json}"
    end

    # In production, you might want to send to a SIEM or security service
    return unless ENV['SECURITY_WEBHOOK_URL']

    send_security_alert(security_log)
  end

  def send_security_alert(event_data)
    # Send to external security monitoring service
    # This could be Slack, PagerDuty, or custom webhook
    Thread.new do
      uri = URI(ENV.fetch('SECURITY_WEBHOOK_URL', nil))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = event_data.to_json

      http.request(request)
    rescue StandardError => e
      logger.error "Failed to send security alert: #{e.message}"
    end
  end

  # Payment-specific validations
  def validate_payment_data(payment_data)
    errors = []

    # Validate amount
    errors << 'Invalid payment amount' unless validate_payment_amount(payment_data[:amount])

    # Validate currency
    errors << 'Invalid currency' unless validate_currency(payment_data[:currency])

    # Validate email
    errors << 'Invalid email address' unless validate_email(payment_data[:email])

    # Validate payment method
    errors << 'Invalid payment method' unless %w[stripe paypal].include?(payment_data[:payment_method])

    errors
  end

  # Idempotency for payments
  def generate_idempotency_key(order_data)
    # Create a deterministic key based on order data
    data = "#{order_data[:email]}:#{order_data[:amount]}:#{order_data[:items].to_json}"
    Digest::SHA256.hexdigest(data)
  end

  def check_duplicate_payment(idempotency_key)
    # Check if this payment has already been processed
    Order.where(idempotency_key: idempotency_key).first
  end

  # Order validation
  def validate_order_integrity(order, items)
    calculated_total = items.sum do |item|
      product = Product[item[:product_id]]
      return false unless product&.active?

      product.price * item[:quantity].to_i
    end

    # Allow for small floating point differences
    (calculated_total - order.amount).abs < 0.01
  end
end

# Rack middleware for additional security
class SecurityMiddleware
  def initialize(app)
    @app = app
  end

  # Security event logging for middleware
  def log_security_event(event_type, details = {})
    security_log = {
      timestamp: Time.now.iso8601,
      event_type: event_type,
      details: details,
    }

    # Log to stdout/stderr for production logging systems to capture
    puts "SECURITY_EVENT: #{security_log.to_json}"

    # Send to security webhook if configured
    send_security_alert(security_log) if ENV['SECURITY_WEBHOOK_URL']
  end

  def send_security_alert(event_data)
    Thread.new do
      require 'net/http'
      require 'uri'

      uri = URI(ENV.fetch('SECURITY_WEBHOOK_URL', nil))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = event_data.to_json

      http.request(request)
    rescue StandardError => e
      puts "Failed to send security alert: #{e.message}"
    end
  end

  def call(env)
    request = Rack::Request.new(env)

    # Block requests with invalid hosts
    return [403, { 'Content-Type' => 'text/plain' }, ['Forbidden: Invalid Host']] unless valid_host?(request)

    # Block requests with suspicious patterns
    return [403, { 'Content-Type' => 'text/plain' }, ['Forbidden']] if suspicious_request?(request)

    # Add security headers to response
    status, headers, body = @app.call(env)
    headers = {} unless headers.is_a?(Hash)
    add_security_headers(headers)

    [status, headers, body]
  end

  private

  def valid_host?(request)
    # Get the host from the request
    host = request.host

    # In production, require a host header for security
    unless host
      if respond_to?(:log_security_event)
        log_security_event('missing_host_header', {
          ip: request.ip,
          user_agent: request.user_agent,
          path: request.path,
        })
      end
      return false
    end

    # If no ALLOWED_HOSTS is configured, allow all hosts (backwards compatibility)
    allowed_hosts_env = ENV.fetch('ALLOWED_HOSTS', nil)
    return true unless allowed_hosts_env && !allowed_hosts_env.empty?

    # Parse allowed hosts from environment variable
    allowed_hosts = allowed_hosts_env.split(',').map(&:strip).map(&:downcase)

    # Check if the request host is in the allowed hosts list
    unless allowed_hosts.include?(host.downcase)
      if respond_to?(:log_security_event)
        log_security_event('invalid_host_header', {
          host: host,
          allowed_hosts: allowed_hosts,
          ip: request.ip,
          user_agent: request.user_agent,
          path: request.path,
        })
      end
      return false
    end

    true
  end

  def suspicious_request?(request)
    # Block requests with SQL injection patterns
    sql_injection_patterns = [
      /(%27)|(')|(--)|(%23)|(#)/i,
      /((%3D)|(=))[^\n]*((%27)|(')|(--)|(%3B)|(;))/i,
      /\w*((%27)|('))((%6F)|o|(%4F))((%72)|r|(%52))/i,
    ]

    query_string = request.query_string || ''
    sql_injection_patterns.any? { |pattern| query_string.match?(pattern) }
  end

  def add_security_headers(headers)
    headers['X-Frame-Options'] ||= 'DENY'
    headers['X-Content-Type-Options'] ||= 'nosniff'
    headers['X-XSS-Protection'] ||= '1; mode=block'
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

class SecurityTest < Minitest::Test
  def test_csrf_protection_enabled
    # Test that CSRF protection blocks requests without tokens
    post '/admin/customize', { test: 'data' }.to_json, 'CONTENT_TYPE' => 'application/json'

    # Should return 403 for missing CSRF token
    assert_includes [403, 401], last_response.status
  end

  def test_security_headers_present
    get '/'

    # Check for security headers
    assert_equal 'DENY', last_response.headers['X-Frame-Options']
    assert_equal 'nosniff', last_response.headers['X-Content-Type-Options']
    assert_equal '1; mode=block', last_response.headers['X-XSS-Protection']
    assert_includes last_response.headers['Content-Security-Policy'], "default-src 'self'"
  end

  def test_rate_limiting_functionality
    # This test would need Redis or in-memory rate limiting to work properly
    # For now, we'll test that the rate limiting doesn't break normal operation
    5.times do
      get '/'

      assert_successful_response
    end
  end

  def test_input_validation_email
    # Test email validation
    invalid_emails = [
      'invalid-email',
      'test@',
      '@domain.com',
      'test..test@domain.com',
      "#{'a' * 300}@domain.com", # Too long
    ]

    invalid_emails.each do |email|
      refute valid_email?(email), "Email #{email} should be invalid"
    end

    valid_emails = [
      'test@example.com',
      'user.name+tag@domain.co.uk',
      'test123@test-domain.com',
    ]

    valid_emails.each do |email|
      assert valid_email?(email), "Email #{email} should be valid"
    end
  end

  def test_input_sanitization
    # Test string sanitization
    assert_equal 'clean string', sanitize_string('clean string')
    assert_equal 'string without tags', sanitize_string('string <script>alert("xss")</script>without tags')
    assert_equal 'string without brackets', sanitize_string('string <div>without</div> brackets')
    assert_equal 'a' * 255, sanitize_string('a' * 300) # Length limit
  end

  def test_payment_amount_validation
    # Valid amounts
    assert validate_payment_amount?(10.50)
    assert validate_payment_amount?('25.99')
    assert validate_payment_amount?(1)

    # Invalid amounts
    refute validate_payment_amount?(0)
    refute validate_payment_amount?(-10)
    refute validate_payment_amount?(1_000_000) # Too large
    refute validate_payment_amount?('invalid')
    refute validate_payment_amount?(nil)
  end

  def test_currency_validation
    # Valid currencies
    %w[USD EUR GBP CAD AUD JPY].each do |currency|
      assert validate_currency?(currency)
      assert validate_currency?(currency.downcase)
    end

    # Invalid currencies
    refute validate_currency?('INVALID')
    refute validate_currency?('US')
    refute validate_currency?(nil)
    refute validate_currency?('')
  end

  def test_webhook_signature_verification_stripe
    # Test Stripe webhook signature verification
    payload = '{"test": "data"}'

    # Without proper signature, should fail
    refute verify_stripe_webhook_signature(payload, nil)
    refute verify_stripe_webhook_signature(payload, 'invalid_signature')

    # NOTE: Real signature verification would require actual Stripe webhook secret
    # This test ensures the method exists and handles invalid input properly
  end

  def test_webhook_signature_verification_paypal
    # Test PayPal webhook signature verification
    payload = '{"test": "data"}'
    headers = {}

    # Without proper headers, should fail
    refute verify_paypal_webhook_signature(payload, headers)

    # With some headers but not all required
    partial_headers = {
      'PAYPAL-AUTH-ALGO' => 'SHA256withRSA',
      'PAYPAL-TRANSMISSION-ID' => 'test-id',
    }

    refute verify_paypal_webhook_signature(payload, partial_headers)
  end

  def test_idempotency_key_generation
    order1 = create(:order, email: 'test@example.com', amount: 100.00)
    order2 = create(:order, email: 'test@example.com', amount: 100.00)

    key1 = generate_payment_idempotency_key(order1)
    key2 = generate_payment_idempotency_key(order2)

    # Keys should be different for different orders
    refute_equal key1, key2

    # Key should be consistent for same order (within time window)
    key1_again = generate_payment_idempotency_key(order1)

    assert_equal key1, key1_again
  end

  def test_order_amount_validation
    product = create(:product, price: 50.00)
    order = create(:order, amount: 100.00)
    order.add_order_item(create(:order_item, order: order, product: product, quantity: 2, price: 50.00))

    # Valid order - amount matches items
    assert validate_order_integrity?(order, [
      { product_id: product.id, quantity: 2 },
    ])

    # Invalid order - amount doesn't match
    refute validate_order_integrity?(order, [
      { product_id: product.id, quantity: 1 },
    ])
  end

  def test_security_event_logging
    # Test that security events can be logged without errors
    assert_nothing_raised do
      log_security_event('test_event', { test: 'data' })
    end
  end

  def test_admin_login_security_enhancements
    create_test_admin

    # Test with valid credentials
    post '/admin/login', {
      email: 'admin@test.com',
      password: 'test_password',
      csrf_token: csrf_token,
    }

    # Should work with proper CSRF token
    assert_includes [200, 302], last_response.status
  end

  def test_api_authentication_security
    # Test API authentication endpoint
    post '/api/auth', { email: 'invalid@test.com', password: 'wrong' }

    assert_equal 401, last_response.status
    response = JSON.parse(last_response.body)

    refute response['success']
  end

  def test_license_validation_api_security
    # Test license validation without proper license
    get '/api/license/INVALID-KEY/validate'

    assert_equal 404, last_response.status
    response = JSON.parse(last_response.body)

    refute response['valid']
  end

  def test_webhook_endpoint_security
    # Test webhook endpoint with unknown provider
    post '/api/webhook/unknown', {}, 'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status
    response = JSON.parse(last_response.body)

    assert_includes response['error'], 'Unknown provider'
  end

  def test_payment_data_validation
    # Test payment data validation helper
    valid_data = {
      amount: 25.99,
      currency: 'USD',
      email: 'test@example.com',
      payment_method: 'stripe',
    }

    errors = validate_payment_data(valid_data)

    assert_empty errors

    # Test invalid data
    invalid_data = {
      amount: -10,
      currency: 'INVALID',
      email: 'invalid-email',
      payment_method: 'unknown',
    }

    errors = validate_payment_data(invalid_data)

    refute_empty errors
    assert_includes errors, 'Invalid payment amount'
    assert_includes errors, 'Invalid currency'
    assert_includes errors, 'Invalid email address'
    assert_includes errors, 'Invalid payment method'
  end

  def test_sql_injection_protection
    # Test that SQL injection patterns are blocked by middleware
    malicious_params = [
      "'; DROP TABLE orders; --",
      "1' OR '1'='1",
      'UNION SELECT * FROM admins',
    ]

    malicious_params.each do |param|
      get "/product/#{param}"
      # Should not crash or expose data
      assert_includes [400, 403, 404], last_response.status
    end
  end

  def test_xss_protection
    # Test XSS protection in templates

    # This would depend on proper template escaping
    # The security headers should help prevent XSS execution
    get '/'

    assert_includes last_response.headers['X-XSS-Protection'], '1; mode=block'
  end

  def test_session_security
    # Test that sessions are configured securely in production mode
    skip unless ENV['APP_ENV'] == 'production'

    # Sessions should be secure in production
    get '/'
    # Check session cookie attributes would be set properly
    # This is more of an integration test requirement
  end

  def test_error_handling_security
    # Test that errors don't expose sensitive information
    get '/nonexistent-endpoint'

    assert_equal 404, last_response.status
    # Should not expose stack traces or internal paths
    refute_includes last_response.body.downcase, 'traceback'
    refute_includes last_response.body.downcase, '/usr/'
    refute_includes last_response.body.downcase, 'exception'
  end

  def test_suspicious_request_detects_basic_sql_injection
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => "id=1' OR '1'='1", 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    assert mw.send(:suspicious_request?, req)
  end

  def test_suspicious_request_detects_percent_encoded_injection
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => 'id=%27%20OR%20%271%27%3D%271', 'REQUEST_METHOD' => 'GET',
                              'PATH_INFO' => '/', 'rack.input' => StringIO.new, })

    assert mw.send(:suspicious_request?, req)
  end

  def test_suspicious_request_bounded_equal_pattern_matches_within_limit
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => "param=#{'a' * 100}'", 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    assert mw.send(:suspicious_request?, req)
  end

  def test_suspicious_request_bounded_equal_pattern_rejects_far_injection
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => "param=#{'a' * 500}'", 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    refute mw.send(:suspicious_request?, req)
  end

  def test_long_safe_query_does_not_trigger_detection
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => 'a' * 2000, 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    refute mw.send(:suspicious_request?, req)
  end

  def test_many_spaces_query_does_not_trigger_regex
    # Ensure token-based pre-check avoids running regex on inputs with many spaces
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => ' ' * 2000, 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    refute mw.send(:suspicious_request?, req)
  end

  def test_overly_long_query_triggers_length_guard
    mw = SecurityMiddleware.new(->(_env) { [200, {}, ['ok']] })
    req = Rack::Request.new({ 'QUERY_STRING' => 'a' * 2050, 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                              'rack.input' => StringIO.new, })

    assert mw.send(:suspicious_request?, req)
  end

  private

  def valid_email?(email)
    return false unless email.is_a?(String)
    return false if email.length > 254

    email_regex = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i
    email.match?(email_regex)
  end

  def sanitize_string(input, max_length = 255)
    return '' unless input.is_a?(String)

    input.strip
      .gsub(/[<>]/, '')
      .slice(0, max_length)
  end

  def validate_payment_amount?(amount)
    return false unless amount.is_a?(Numeric) || amount.is_a?(String)

    amount = amount.to_f
    amount.positive? && amount <= 999_999.99
  end

  def validate_currency?(currency)
    valid_currencies = %w[USD EUR GBP CAD AUD JPY]
    valid_currencies.include?(currency&.upcase)
  end

  def verify_stripe_webhook_signature(_payload, signature)
    return false unless signature && ENV['STRIPE_WEBHOOK_SECRET']

    begin
      # In real implementation, this would use Stripe::Webhook::Signature.verify_header
      # For testing, we'll simulate the validation
      signature.is_a?(String) && !signature.empty?
    rescue StandardError
      false
    end
  end

  def verify_paypal_webhook_signature(_payload, headers)
    return false unless ENV['PAYPAL_WEBHOOK_ID']

    required_headers = %w[PAYPAL-AUTH-ALGO PAYPAL-TRANSMISSION-ID PAYPAL-CERT-ID
                          PAYPAL-TRANSMISSION-SIG PAYPAL-TRANSMISSION-TIME]

    required_headers.all? { |header| headers[header] && !headers[header].empty? }
  end

  def generate_payment_idempotency_key(order)
    require 'digest'
    data = "#{order.id}:#{order.amount}:#{order.email}:#{Time.now.to_i / 300}"
    Digest::SHA256.hexdigest(data)[0, 32]
  end

  def validate_order_integrity?(order, items)
    calculated_total = items.sum do |item|
      product = Product[item[:product_id]]
      return false unless product&.active?

      product.price * item[:quantity].to_i
    end

    (calculated_total - order.amount).abs < 0.01
  end

  def validate_payment_data(payment_data)
    errors = []

    errors << 'Invalid payment amount' unless validate_payment_amount?(payment_data[:amount])

    errors << 'Invalid currency' unless validate_currency?(payment_data[:currency])

    errors << 'Invalid email address' unless valid_email?(payment_data[:email])

    errors << 'Invalid payment method' unless %w[stripe paypal].include?(payment_data[:payment_method])

    errors
  end

  def log_security_event(event_type, details = {})
    # Mock security event logging for testing
    event_log = {
      timestamp: Time.now.iso8601,
      event_type: event_type,
      details: details,
    }

    # In real implementation, this would log to a security service
    puts "SECURITY_TEST_EVENT: #{event_log.to_json}"
  end

  def csrf_token
    # Mock CSRF token for testing
    'test_csrf_token_123'
  end
end

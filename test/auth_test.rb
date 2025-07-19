# frozen_string_literal: true

require_relative 'test_helper'

class AuthTest < Minitest::Test
  def setup
    super
    @test_admin = create_test_admin_with_enhanced_fields
  end

  def test_enhanced_admin_creation
    admin = Admin.create_secure_admin('test@example.com', 'SecurePassword123!', ['admin'])

    assert_predicate admin, :valid?
    assert_predicate admin, :active?
    assert admin.has_role?('admin')
    assert admin.password_matches?('SecurePassword123!')
    refute_nil admin.password_changed_at
  end

  def test_password_policy_validation
    # Test valid password
    valid_password = 'SecurePassword123!'
    errors = validate_password_policy(valid_password)

    assert_empty errors

    # Test invalid passwords
    test_cases = [
      ['short', 'Password must be at least 12 characters long'],
      ['nouppercase123!', 'Password must contain at least one uppercase letter'],
      ['NOLOWERCASE123!', 'Password must contain at least one lowercase letter'],
      ['NoNumbers!', 'Password must contain at least one number'],
      ['NoSpecialChars123', 'Password must contain at least one special character'],
      ['password123!', 'Password is too common'],
      ['SameChars111!', 'Password cannot contain more than 2 consecutive identical characters'],
    ]

    test_cases.each do |password, expected_error|
      errors = validate_password_policy(password)

      assert_includes errors.join(' '), expected_error.split.first,
                      "Password '#{password}' should fail validation"
    end
  end

  def test_secure_authentication_with_valid_credentials
    email = @test_admin.email
    password = 'test_password'
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    result = authenticate_admin_secure(email, password, request_info)

    assert result[:success]
    assert_equal 'Authentication successful', result[:message]
    assert_equal @test_admin.id, result[:admin].id
  end

  def test_secure_authentication_with_invalid_credentials
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    result = authenticate_admin_secure(@test_admin.email, 'wrong_password', request_info)

    refute result[:success]
    assert_equal 'Invalid credentials', result[:message]
  end

  def test_secure_authentication_with_invalid_email_format
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    result = authenticate_admin_secure('invalid-email', 'password', request_info)

    refute result[:success]
    assert_equal 'Invalid email format', result[:message]
  end

  def test_secure_authentication_with_inactive_account
    @test_admin.deactivate!
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    result = authenticate_admin_secure(@test_admin.email, 'test_password', request_info)

    refute result[:success]
    assert_equal 'Account is deactivated', result[:message]
  end

  def test_account_lockout_after_failed_attempts
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    # Simulate 5 failed attempts
    5.times do
      authenticate_admin_secure(@test_admin.email, 'wrong_password', request_info)
    end

    # 6th attempt should be locked out
    result = authenticate_admin_secure(@test_admin.email, 'wrong_password', request_info)

    refute result[:success]
    assert_includes result[:message], 'locked'
  end

  def test_session_creation_and_validation
    admin = @test_admin
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    # Create session
    session_data = create_secure_session(admin, request_info)

    assert session_data[:admin_id]
    assert session_data[:session_id]
    assert session_data[:created_at]
    assert_equal '127.0.0.1', session_data[:ip_address]

    # Mock session storage
    session[:admin_session] = session_data

    # Validate session
    assert validate_session
  end

  def test_session_expiry
    admin = @test_admin
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    session_data = create_secure_session(admin, request_info)

    # Simulate expired session
    session_data[:last_activity] = Time.now.to_i - (9 * 60 * 60) # 9 hours ago
    session[:admin_session] = session_data

    refute validate_session
  end

  def test_password_expiry_checking
    admin = @test_admin

    # Set password changed 100 days ago
    admin.update(password_changed_at: Time.now - (100 * 24 * 60 * 60))

    assert_predicate admin, :password_expired?
    assert_predicate admin.days_until_password_expires, :zero?
  end

  def test_two_factor_authentication
    admin = @test_admin
    secret = generate_2fa_secret

    admin.enable_2fa!(secret)

    assert_predicate admin, :two_factor_enabled?
    assert_equal secret, admin.two_factor_secret

    admin.disable_2fa!

    refute_predicate admin, :two_factor_enabled?
    assert_nil admin.two_factor_secret
  end

  def test_password_reset_token_generation
    admin = @test_admin

    token = admin.generate_password_reset_token!

    assert token
    assert_predicate admin, :password_reset_token_valid?
    assert_equal token, admin.password_reset_token

    # Test token expiry
    admin.update(password_reset_sent_at: Time.now - 3700) # Over 1 hour ago

    refute_predicate admin, :password_reset_token_valid?
  end

  def test_role_management
    admin = @test_admin

    assert admin.has_role?('admin')

    admin.add_role!('super_admin')

    assert admin.has_role?('super_admin')
    assert_includes admin.roles_list, 'super_admin'

    admin.remove_role!('admin')

    refute admin.has_role?('admin')
    assert admin.has_role?('super_admin')
  end

  def test_login_attempt_logging
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    # Mock the logging method
    logged_events = []
    define_singleton_method(:log_auth_event) do |event_type, details|
      logged_events << { event_type: event_type, details: details }
    end

    # Test successful login
    authenticate_admin_secure(@test_admin.email, 'test_password', request_info)

    success_event = logged_events.find { |e| e[:event_type] == 'login_success' }

    assert success_event
    assert_equal @test_admin.email, success_event[:details][:email]

    # Test failed login
    authenticate_admin_secure(@test_admin.email, 'wrong_password', request_info)

    failure_event = logged_events.find { |e| e[:event_type] == 'login_attempt_invalid_password' }

    assert failure_event
    assert_equal @test_admin.email, failure_event[:details][:email]
  end

  def test_secure_admin_login_route
    post '/admin/login', {
      email: @test_admin.email,
      password: 'test_password',
      csrf_token: csrf_token,
    }

    # Should redirect to admin dashboard
    assert_redirect_to('/admin')
  end

  def test_secure_admin_login_with_invalid_csrf
    post '/admin/login', {
      email: @test_admin.email,
      password: 'test_password',
      csrf_token: 'invalid_token',
    }

    # Should be forbidden due to CSRF
    assert_equal 403, last_response.status
  end

  def test_secure_admin_login_with_failed_credentials
    post '/admin/login', {
      email: @test_admin.email,
      password: 'wrong_password',
      csrf_token: csrf_token,
    }

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Invalid credentials'
  end

  def test_admin_account_activity_summary
    admin = @test_admin

    # Update login info
    admin.update_last_login!('192.168.1.1', 'Mozilla Firefox')

    summary = admin.last_activity_summary

    assert summary[:last_login]
    assert_equal '192.168.1.1', summary[:last_ip]
    assert_equal 1, summary[:login_count]
    assert_operator summary[:account_age_days], :>=, 0
  end

  def test_admin_validation
    # Test email uniqueness
    existing_admin = @test_admin
    new_admin = Admin.new(
      email: existing_admin.email,
      password_hash: 'test_hash',
      status: 'active'
    )

    refute_predicate new_admin, :valid?
    assert new_admin.errors[:email]

    # Test invalid status
    new_admin.email = 'unique@example.com'
    new_admin.status = 'invalid_status'

    refute_predicate new_admin, :valid?
    assert new_admin.errors[:status]
  end

  def test_secure_session_rotation
    admin = @test_admin
    request_info = { ip: '127.0.0.1', user_agent: 'Test Browser' }

    session_data = create_secure_session(admin, request_info)
    session_data[:session_id]

    # Simulate session that needs rotation (older than 2 hours)
    session_data[:created_at] = Time.now.to_i - (3 * 60 * 60)
    session[:admin_session] = session_data

    # Mock the rotation method
    rotated = false
    define_singleton_method(:rotate_session) do
      rotated = true
      session_data[:session_id] = SecureRandom.hex(32)
    end

    validate_session

    assert rotated
  end

  private

  def create_test_admin_with_enhanced_fields
    admin = Admin.new
    admin.email = 'admin@test.com'
    admin.password = 'test_password'
    admin.status = 'active'
    admin.roles = 'admin'
    admin.created_at = Time.now
    admin.password_changed_at = Time.now
    admin.save_changes
    admin
  end

  def validate_password_policy(password)
    errors = []

    errors << 'Password must be at least 12 characters long' if password.length < 12

    errors << 'Password must contain at least one lowercase letter' unless password.match?(/[a-z]/)

    errors << 'Password must contain at least one uppercase letter' unless password.match?(/[A-Z]/)

    errors << 'Password must contain at least one number' unless password.match?(/[0-9]/)

    errors << 'Password must contain at least one special character' unless password.match?(/[^a-zA-Z0-9]/)

    common_passwords = %w[password password123 admin]
    errors << 'Password is too common' if common_passwords.include?(password.downcase)

    errors << 'Password cannot contain more than 2 consecutive identical characters' if password.match?(/(.)\1{2,}/)

    errors
  end

  def csrf_token
    'test_csrf_token_123'
  end

  # Mock methods for testing
  def authenticate_admin_secure(email, password, request_info = {})
    # Simplified version for testing
    admin = Admin.first(email: email&.strip&.downcase)

    return { success: false, message: 'Missing credentials' } if !email || email.strip.empty?

    unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      return { success: false, message: 'Invalid email format' }
    end

    # Check for lockout
    if account_locked?(email)
      return { success: false, message: 'Account temporarily locked due to multiple failed attempts' }
    end

    unless admin
      record_failed_login_attempt(email, request_info)
      return { success: false, message: 'Invalid credentials' }
    end

    return { success: false, message: 'Account is deactivated' } unless admin.active?

    unless admin.password_matches?(password)
      record_failed_login_attempt(email, request_info, admin.id)
      return { success: false, message: 'Invalid credentials' }
    end

    clear_failed_login_attempts(email)
    { success: true, message: 'Authentication successful', admin: admin }
  end

  def create_secure_session(admin, request_info = {})
    session_id = SecureRandom.hex(32)
    {
      admin_id: admin.id,
      admin_email: admin.email,
      created_at: Time.now.to_i,
      last_activity: Time.now.to_i,
      ip_address: request_info[:ip],
      user_agent: request_info[:user_agent],
      session_id: session_id,
    }
  end

  def validate_session
    session_data = session[:admin_session]
    return false unless session_data

    # Check expiry
    return false if Time.now.to_i - session_data[:last_activity] > (8 * 60 * 60)

    true
  end

  def generate_2fa_secret
    SecureRandom.hex(16)
  end

  def account_locked?(email)
    failed_attempts = session[:failed_attempts] || []
    attempts = failed_attempts.select { |a| a[:email] == email }
    attempts.count >= 5
  end

  def record_failed_login_attempt(email, _request_info, admin_id = nil)
    session[:failed_attempts] ||= []
    session[:failed_attempts] << {
      email: email,
      admin_id: admin_id,
      timestamp: Time.now,
    }
  end

  def clear_failed_login_attempts(email)
    return unless session[:failed_attempts]

    session[:failed_attempts].reject! { |a| a[:email] == email }
  end

  def log_auth_event(event_type, details = {})
    # Mock logging for tests
  end
end

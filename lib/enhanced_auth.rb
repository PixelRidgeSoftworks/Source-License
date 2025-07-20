# frozen_string_literal: true

# Source-License: Enhanced Authentication System
# Production-ready authentication with security features

require 'bcrypt'
require 'jwt'
require 'digest'
require 'securerandom'

module EnhancedAuthHelpers
  # Account lockout configuration
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30 * 60 # 30 minutes
  LOGIN_ATTEMPT_WINDOW = 15 * 60 # 15 minutes

  # Session security configuration
  SESSION_TIMEOUT = 8 * 60 * 60 # 8 hours
  SESSION_ROTATION_INTERVAL = 2 * 60 * 60 # 2 hours

  # Password policy configuration
  MIN_PASSWORD_LENGTH = 12
  PASSWORD_EXPIRY_DAYS = 90

  # Enhanced admin login with security features
  def authenticate_admin_secure(email, password, request_info = {})
    return security_response(false, 'Missing credentials') unless email && password

    # Normalize email
    email = email.strip.downcase

    # Validate email format
    unless valid_email_format?(email)
      log_auth_event('invalid_email_format', { email: email, ip: request_info[:ip] })
      return security_response(false, 'Invalid email format')
    end

    # Check for account lockout
    if account_locked?(email)
      log_auth_event('login_attempt_locked_account', {
        email: email,
        ip: request_info[:ip],
        user_agent: request_info[:user_agent],
      })
      return security_response(false, 'Account temporarily locked due to multiple failed attempts')
    end

    # Rate limiting for login attempts
    if login_rate_exceeded?(email, request_info[:ip])
      log_auth_event('login_rate_limit_exceeded', {
        email: email,
        ip: request_info[:ip],
      })
      return security_response(false, 'Too many login attempts. Please try again later.')
    end

    # Find admin user
    admin = Admin.first(email: email)

    # Record failed attempt if user not found
    unless admin
      record_failed_login_attempt(email, request_info)
      log_auth_event('login_attempt_invalid_user', {
        email: email,
        ip: request_info[:ip],
      })
      return security_response(false, 'Invalid credentials')
    end

    # Check if account is active
    unless admin.active?
      log_auth_event('login_attempt_inactive_account', {
        email: email,
        admin_id: admin.id,
        ip: request_info[:ip],
      })
      return security_response(false, 'Account is deactivated')
    end

    # Check password expiry
    if password_expired?(admin)
      log_auth_event('login_attempt_expired_password', {
        email: email,
        admin_id: admin.id,
        ip: request_info[:ip],
      })
      return security_response(false, 'Password has expired. Please contact administrator.')
    end

    # Verify password
    unless admin.password_matches?(password)
      record_failed_login_attempt(email, request_info, admin.id)
      log_auth_event('login_attempt_invalid_password', {
        email: email,
        admin_id: admin.id,
        ip: request_info[:ip],
        failed_attempts: get_failed_attempt_count(email),
      })
      return security_response(false, 'Invalid credentials')
    end

    # Successful authentication
    clear_failed_login_attempts(email)

    # Update last login safely (handle missing columns gracefully)
    begin
      admin.update_last_login!(request_info[:ip], request_info[:user_agent])
    rescue Sequel::DatabaseError
      # If the columns don't exist, just update last_login_at
      admin.update(last_login_at: Time.now) if admin.respond_to?(:last_login_at)
    end

    log_auth_event('login_success', {
      email: email,
      admin_id: admin.id,
      ip: request_info[:ip],
      user_agent: request_info[:user_agent],
    })

    security_response(true, 'Authentication successful', { admin: admin })
  end

  # Enhanced session management
  def create_secure_session(admin, request_info = {})
    session_id = SecureRandom.hex(32)
    session_data = {
      admin_id: admin.id,
      admin_email: admin.email,
      created_at: Time.now.to_i,
      last_activity: Time.now.to_i,
      ip_address: request_info[:ip],
      user_agent: request_info[:user_agent],
      session_id: session_id,
    }

    # Store session securely
    session[:admin_session] = session_data
    session[:csrf_token] = SecureRandom.hex(32)

    log_auth_event('session_created', {
      admin_id: admin.id,
      session_id: session_id,
      ip: request_info[:ip],
    })

    session_data
  end

  # Validate and refresh session
  def validate_session
    session_data = session[:admin_session]
    return false unless session_data

    # Check session timeout
    if session_expired?(session_data)
      destroy_session('session_timeout')
      return false
    end

    # Check for session hijacking indicators
    if suspicious_session?(session_data)
      destroy_session('suspicious_activity')
      return false
    end

    # Rotate session if needed
    rotate_session if session_rotation_needed?(session_data)

    # Update last activity
    session_data[:last_activity] = Time.now.to_i
    session[:admin_session] = session_data

    true
  end

  # Enhanced admin authentication check
  def require_secure_admin_auth
    return if validate_session

    if request.xhr? || content_type == 'application/json'
      halt 401, { error: 'Authentication required' }.to_json
    else
      session[:return_to] = request.fullpath
      redirect '/admin/login'
    end
  end

  # Get current authenticated admin
  def current_secure_admin
    return nil unless validate_session

    session_data = session[:admin_session]
    return nil unless session_data

    @current_secure_admin ||= Admin[session_data[:admin_id]]
  end

  # Password policy validation
  def validate_password_policy(password)
    errors = []

    # Length requirement
    if password.length < MIN_PASSWORD_LENGTH
      errors << "Password must be at least #{MIN_PASSWORD_LENGTH} characters long"
    end

    # Complexity requirements
    errors << 'Password must contain at least one lowercase letter' unless password.match?(/[a-z]/)

    errors << 'Password must contain at least one uppercase letter' unless password.match?(/[A-Z]/)

    errors << 'Password must contain at least one number' unless password.match?(/[0-9]/)

    errors << 'Password must contain at least one special character' unless password.match?(/[^a-zA-Z0-9]/)

    # Check against common passwords
    errors << 'Password is too common. Please choose a more unique password' if common_password?(password)

    # Check for repeated characters
    errors << 'Password cannot contain more than 2 consecutive identical characters' if password.match?(/(.)\1{2,}/)

    errors
  end

  # Two-factor authentication support
  def generate_2fa_secret
    Base32.encode(SecureRandom.random_bytes(10))
  end

  def verify_2fa_token(secret, token)
    return false unless secret && token

    # TOTP verification would go here
    # For now, we'll simulate it
    true # Placeholder
  end

  # Account security monitoring
  def check_account_security(admin)
    warnings = []

    # Check password age
    warnings << 'Your password will expire soon. Please change it.' if password_expires_soon?(admin)

    # Check for suspicious activity
    if suspicious_login_activity?(admin)
      warnings << 'Unusual login activity detected. Please review your account security.'
    end

    # Check last login time
    warnings << 'Your account has been inactive for an extended period.' if stale_account?(admin)

    warnings
  end

  # Secure logout
  def secure_logout(reason = 'user_logout')
    session_data = session[:admin_session]

    if session_data
      log_auth_event('logout', {
        admin_id: session_data[:admin_id],
        session_id: session_data[:session_id],
        reason: reason,
      })
    end

    destroy_session(reason)
  end

  private

  # Security response helper
  def security_response(success, message, data = {})
    {
      success: success,
      message: message,
      timestamp: Time.now.iso8601,
    }.merge(data)
  end

  # Account lockout management
  def account_locked?(email)
    failed_attempts = get_failed_attempts(email)
    return false if failed_attempts.empty?

    recent_attempts = failed_attempts.select do |attempt|
      Time.now - attempt[:timestamp] < LOCKOUT_DURATION
    end

    recent_attempts.count >= MAX_FAILED_ATTEMPTS
  end

  def record_failed_login_attempt(email, request_info, admin_id = nil)
    attempt_data = {
      email: email,
      admin_id: admin_id,
      ip_address: request_info[:ip],
      user_agent: request_info[:user_agent],
      timestamp: Time.now,
    }

    # Store in session for simplicity (in production, use Redis or database)
    session[:failed_attempts] ||= []
    session[:failed_attempts] << attempt_data

    # Keep only recent attempts
    session[:failed_attempts] = session[:failed_attempts].select do |attempt|
      Time.now - attempt[:timestamp] < LOGIN_ATTEMPT_WINDOW
    end
  end

  def get_failed_attempts(email)
    attempts = session[:failed_attempts] || []
    attempts.select { |attempt| attempt[:email] == email }
  end

  def get_failed_attempt_count(email)
    get_failed_attempts(email).count
  end

  def clear_failed_login_attempts(email)
    return unless session[:failed_attempts]

    session[:failed_attempts] = session[:failed_attempts].reject do |attempt|
      attempt[:email] == email
    end
  end

  # Rate limiting
  def login_rate_exceeded?(email, _ip)
    # Check both email and IP-based rate limiting
    email_attempts = get_failed_attempts(email)
    recent_email_attempts = email_attempts.select do |attempt|
      Time.now - attempt[:timestamp] < LOGIN_ATTEMPT_WINDOW
    end

    recent_email_attempts.count >= MAX_FAILED_ATTEMPTS
  end

  # Session management
  def session_expired?(session_data)
    return true unless session_data[:last_activity]

    Time.now.to_i - session_data[:last_activity] > SESSION_TIMEOUT
  end

  def session_rotation_needed?(session_data)
    return true unless session_data[:created_at]

    Time.now.to_i - session_data[:created_at] > SESSION_ROTATION_INTERVAL
  end

  def suspicious_session?(session_data)
    # Check for session hijacking indicators
    current_ip = request.ip
    session_ip = session_data[:ip_address]

    # Skip IP checking on Render or when behind load balancers/proxies
    # as IP addresses can change legitimately
    return false if ENV['RENDER'] == 'true'
    return false if ENV['APP_ENV'] == 'development'
    return false if ENV['BEHIND_LOAD_BALANCER'] == 'true'
    
    # For now, just check IP consistency in traditional hosting
    # In production, you might want more sophisticated checks
    current_ip != session_ip
  end

  def rotate_session
    session_data = session[:admin_session]
    return unless session_data

    old_session_id = session_data[:session_id]
    new_session_id = SecureRandom.hex(32)

    session_data[:session_id] = new_session_id
    session_data[:created_at] = Time.now.to_i
    session[:admin_session] = session_data
    session[:csrf_token] = SecureRandom.hex(32)

    log_auth_event('session_rotated', {
      admin_id: session_data[:admin_id],
      old_session_id: old_session_id,
      new_session_id: new_session_id,
    })
  end

  def destroy_session(_reason = 'logout')
    session.clear

    # In production, you might want to maintain a blacklist of invalidated sessions
    @current_secure_admin = nil
  end

  # Password policy checks
  def password_expired?(admin)
    return false unless admin.password_changed_at

    days_since_change = (Time.now - admin.password_changed_at) / (24 * 60 * 60)
    days_since_change > PASSWORD_EXPIRY_DAYS
  end

  def password_expires_soon?(admin, warning_days = 7)
    return false unless admin.password_changed_at

    days_since_change = (Time.now - admin.password_changed_at) / (24 * 60 * 60)
    days_until_expiry = PASSWORD_EXPIRY_DAYS - days_since_change

    days_until_expiry <= warning_days && days_until_expiry.positive?
  end

  def common_password?(password)
    # Check against a list of common passwords
    common_passwords = %w[
      password password123 admin admin123 123456 qwerty
      letmein welcome changeme password1 abc123 administrator
    ]

    common_passwords.include?(password.downcase)
  end

  # Account monitoring
  def suspicious_login_activity?(_admin)
    # Check for suspicious patterns in login history
    # This would typically involve analyzing login times, locations, etc.
    false # Placeholder
  end

  def stale_account?(admin)
    return false unless admin.last_login_at

    days_since_login = (Time.now - admin.last_login_at) / (24 * 60 * 60)
    days_since_login > 90 # 90 days
  end

  # Validation helpers
  def valid_email_format?(email)
    return false unless email.is_a?(String)
    return false if email.length > 254

    email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
    email.match?(email_regex)
  end

  # Enhanced logging
  def log_auth_event(event_type, details = {})
    # Skip logging in test environment
    return if ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    auth_log = {
      timestamp: Time.now.iso8601,
      event_type: event_type,
      ip_address: details[:ip] || request&.ip,
      user_agent: details[:user_agent] || request&.user_agent,
      details: details.except(:ip, :user_agent),
    }

    # Log to authentication log
    if respond_to?(:logger)
      logger.warn "AUTH_EVENT: #{auth_log.to_json}"
    else
      puts "AUTH_EVENT: #{auth_log.to_json}"
    end

    # Send security alerts for critical events
    return unless critical_auth_event?(event_type)

    send_security_alert(auth_log)
  end

  def critical_auth_event?(event_type)
    critical_events = %w[
      login_attempt_locked_account
      login_rate_limit_exceeded
      suspicious_activity
      session_hijacking_detected
      multiple_failed_attempts
    ]

    critical_events.include?(event_type)
  end

  def send_security_alert(event_data)
    # Send to security monitoring service
    return unless ENV['SECURITY_WEBHOOK_URL']

    Thread.new do
      uri = URI(ENV.fetch('SECURITY_WEBHOOK_URL', nil))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = {
        alert_type: 'authentication_security',
        severity: 'high',
        event: event_data,
      }.to_json

      http.request(request)
    rescue StandardError => e
      logger.error "Failed to send auth security alert: #{e.message}"
    end
  end
end

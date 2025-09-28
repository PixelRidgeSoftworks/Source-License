# frozen_string_literal: true

# Source-License: Secure Authentication Module
# Enhanced authentication with security features

module Auth::SecureAuth
  include BaseAuth

  #
  # ENHANCED AUTHENTICATION METHODS
  #

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

    # Check for progressive ban
    if account_locked?(email)
      ban_info = get_current_ban(email)
      time_remaining = get_ban_time_remaining(email)
      duration_text = format_ban_duration(time_remaining)

      log_auth_event('login_attempt_banned_account', {
        email: email,
        ip: request_info[:ip],
        user_agent: request_info[:user_agent],
        ban_count: ban_info[:ban_count],
        time_remaining: time_remaining,
      })

      return security_response(false,
                               "Account is temporarily banned for #{duration_text} due to multiple failed login attempts")
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

  # Enhanced user login with security features
  def authenticate_user_secure(email, password, request_info = {})
    return security_response(false, 'Missing credentials') unless email && password

    # Normalize email
    email = email.strip.downcase

    # Validate email format
    unless valid_email_format?(email)
      log_auth_event('invalid_email_format', { email: email, ip: request_info[:ip] })
      return security_response(false, 'Invalid email format')
    end

    # Check for progressive ban
    if account_locked?(email)
      ban_info = get_current_ban(email)
      time_remaining = get_ban_time_remaining(email)
      duration_text = format_ban_duration(time_remaining)

      log_auth_event('login_attempt_banned_account', {
        email: email,
        ip: request_info[:ip],
        user_agent: request_info[:user_agent],
        ban_count: ban_info[:ban_count],
        time_remaining: time_remaining,
      })

      return security_response(false,
                               "Account is temporarily banned for #{duration_text} due to multiple failed login attempts")
    end

    # Rate limiting for login attempts
    if login_rate_exceeded?(email, request_info[:ip])
      log_auth_event('login_rate_limit_exceeded', {
        email: email,
        ip: request_info[:ip],
      })
      return security_response(false, 'Too many login attempts. Please try again later.')
    end

    # Find user
    user = Customer.first(email: email)

    # Record failed attempt if user not found
    unless user
      record_failed_login_attempt(email, request_info)
      log_auth_event('login_attempt_invalid_user', {
        email: email,
        ip: request_info[:ip],
      })
      return security_response(false, 'Invalid credentials')
    end

    # Check if account is active
    unless user.active?
      log_auth_event('login_attempt_inactive_account', {
        email: email,
        user_id: user.id,
        ip: request_info[:ip],
      })
      return security_response(false, 'Account is deactivated')
    end

    # Verify password (assuming users have a password_matches? method similar to Admin)
    unless user.respond_to?(:password_matches?) && user.password_matches?(password)
      record_failed_login_attempt(email, request_info, user.id)
      log_auth_event('login_attempt_invalid_password', {
        email: email,
        user_id: user.id,
        ip: request_info[:ip],
        failed_attempts: get_failed_attempt_count(email),
      })
      return security_response(false, 'Invalid credentials')
    end

    # Successful authentication
    clear_failed_login_attempts(email)

    # Update last login safely
    begin
      user.update(last_login_at: Time.now, last_login_ip: request_info[:ip])
    rescue StandardError
      # Handle gracefully if columns don't exist
    end

    log_auth_event('user_login_success', {
      email: email,
      user_id: user.id,
      ip: request_info[:ip],
      user_agent: request_info[:user_agent],
    })

    security_response(true, 'Authentication successful', { user: user })
  end

  private

  # Enhanced rate limiting
  def login_rate_exceeded?(email, ip)
    # Check both email and IP-based rate limiting
    email_attempts = get_failed_attempts(email)
    recent_email_attempts = email_attempts.select do |attempt|
      Time.now - attempt[:timestamp] < LOGIN_ATTEMPT_WINDOW
    end

    # If max attempts reached, apply progressive ban
    if recent_email_attempts.count >= MAX_FAILED_ATTEMPTS
      # Find admin_id from the failed attempts if available
      admin_id = recent_email_attempts.find { |attempt| attempt[:admin_id] }&.dig(:admin_id)

      # Apply the progressive ban
      apply_progressive_ban(email, admin_id, { ip: ip, user_agent: request&.user_agent })

      # Clear failed attempts since we're applying a ban
      clear_failed_login_attempts(email)

      return true
    end

    false
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
end

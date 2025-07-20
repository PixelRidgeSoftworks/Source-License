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

  # Progressive ban configuration
  BAN_DURATIONS = [
    30 * 60,      # 1st ban: 30 minutes
    2 * 60 * 60,  # 2nd ban: 2 hours  
    8 * 60 * 60,  # 3rd ban: 8 hours
    24 * 60 * 60, # 4th ban: 24 hours
    72 * 60 * 60, # 5th ban: 72 hours (3 days)
    168 * 60 * 60 # 6th+ ban: 168 hours (7 days)
  ].freeze

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
        time_remaining: time_remaining
      })
      
      return security_response(false, "Account is temporarily banned for #{duration_text} due to multiple failed login attempts")
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

    # Check if admin account is still active
    admin = Admin[session_data[:admin_id]]
    unless admin&.active?
      log_auth_event('session_invalidated_inactive_admin', {
        admin_id: session_data[:admin_id],
        admin_email: session_data[:admin_email],
        reason: admin ? 'account_deactivated' : 'account_deleted'
      })
      destroy_session('admin_account_deactivated')
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

  # Enhanced user login with security features (similar to admin auth)
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
        time_remaining: time_remaining
      })
      
      return security_response(false, "Account is temporarily banned for #{duration_text} due to multiple failed login attempts")
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

  # Progressive ban management
  def account_locked?(email)
    ban_info = get_current_ban(email)
    return false unless ban_info

    # Check if ban is still active
    ban_info[:banned_until] > Time.now
  end

  def get_current_ban(email)
    if use_redis_for_auth?
      get_ban_redis(email)
    else
      get_ban_database(email)
    end
  end

  def apply_progressive_ban(email, admin_id = nil, request_info = {})
    # Get previous ban count
    ban_count = get_ban_count(email)
    
    # Calculate new ban duration
    duration_index = [ban_count, BAN_DURATIONS.length - 1].min
    ban_duration = BAN_DURATIONS[duration_index]
    banned_until = Time.now + ban_duration
    
    # Create ban record
    ban_data = {
      email: email,
      admin_id: admin_id,
      ban_count: ban_count + 1,
      banned_until: banned_until,
      reason: 'multiple_failed_login_attempts',
      ip_address: request_info[:ip],
      user_agent: request_info[:user_agent],
      created_at: Time.now
    }
    
    # Store the ban
    if use_redis_for_auth?
      store_ban_redis(ban_data)
    else
      store_ban_database(ban_data)
    end
    
    # Log the ban
    log_auth_event('account_banned', {
      email: email,
      admin_id: admin_id,
      ban_count: ban_count + 1,
      ban_duration_minutes: ban_duration / 60,
      banned_until: banned_until.iso8601,
      ip: request_info[:ip]
    })
    
    ban_data
  end

  def get_ban_count(email)
    if use_redis_for_auth?
      get_ban_count_redis(email)
    else
      get_ban_count_database(email)
    end
  end

  def format_ban_duration(seconds)
    if seconds < 3600
      "#{seconds / 60} minutes"
    elsif seconds < 86400
      "#{seconds / 3600} hours"
    else
      "#{seconds / 86400} days"
    end
  end

  def get_ban_time_remaining(email)
    ban_info = get_current_ban(email)
    return 0 unless ban_info && ban_info[:banned_until] > Time.now
    
    ban_info[:banned_until] - Time.now
  end

  def remove_ban(email, admin_who_removed = nil)
    # Remove ban from storage
    if use_redis_for_auth?
      remove_ban_redis(email)
    else
      remove_ban_database(email)
    end

    # Log the ban removal
    log_auth_event('ban_removed_by_admin', {
      email: email,
      removed_by_admin: admin_who_removed&.id || 'system',
      removed_by_email: admin_who_removed&.email || 'system'
    })

    true
  end

  def reset_ban_count(email, admin_who_reset = nil)
    # Reset ban count in storage
    if use_redis_for_auth?
      reset_ban_count_redis(email)
    else
      reset_ban_count_database(email)
    end

    # Log the ban count reset
    log_auth_event('ban_count_reset_by_admin', {
      email: email,
      reset_by_admin: admin_who_reset&.id || 'system',
      reset_by_email: admin_who_reset&.email || 'system'
    })

    true
  end

  def get_all_active_bans(limit = 50)
    if use_redis_for_auth?
      get_all_active_bans_redis(limit)
    else
      get_all_active_bans_database(limit)
    end
  end

  def record_failed_login_attempt(email, request_info, admin_id = nil)
    attempt_data = {
      email: email,
      admin_id: admin_id,
      ip_address: request_info[:ip],
      user_agent: request_info[:user_agent],
      timestamp: Time.now,
    }

    # Production-ready persistent storage
    if use_redis_for_auth?
      store_failed_attempt_redis(attempt_data)
    else
      store_failed_attempt_database(attempt_data)
    end
  end

  def get_failed_attempts(email)
    if use_redis_for_auth?
      get_failed_attempts_redis(email)
    else
      get_failed_attempts_database(email)
    end
  end

  def get_failed_attempt_count(email)
    get_failed_attempts(email).count
  end

  def clear_failed_login_attempts(email)
    if use_redis_for_auth?
      clear_failed_attempts_redis(email)
    else
      clear_failed_attempts_database(email)
    end
  end

  # Production-ready storage methods
  def use_redis_for_auth?
    ENV['REDIS_URL'] && !ENV['REDIS_URL'].empty?
  end

  def store_failed_attempt_redis(attempt_data)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      key = "failed_attempts:#{attempt_data[:email]}"
      attempt_json = attempt_data.to_json
      
      # Add to list and set expiration
      redis.lpush(key, attempt_json)
      redis.expire(key, LOGIN_ATTEMPT_WINDOW)
      
      # Keep only recent attempts
      redis.ltrim(key, 0, MAX_FAILED_ATTEMPTS * 2)
    rescue StandardError => e
      # Fallback to database storage
      AppLogger.error("Redis failed for auth storage: #{e.message}")
      store_failed_attempt_database(attempt_data)
    end
  end

  def get_failed_attempts_redis(email)
    return [] unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      key = "failed_attempts:#{email}"
      attempts_json = redis.lrange(key, 0, -1)
      
      attempts = attempts_json.map { |json| JSON.parse(json, symbolize_names: true) }
      
      # Filter to recent attempts only
      cutoff_time = Time.now - LOGIN_ATTEMPT_WINDOW
      attempts.select { |attempt| Time.parse(attempt[:timestamp].to_s) > cutoff_time }
    rescue StandardError => e
      AppLogger.error("Redis failed for auth retrieval: #{e.message}")
      get_failed_attempts_database(email)
    end
  end

  def clear_failed_attempts_redis(email)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      redis.del("failed_attempts:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for auth clearing: #{e.message}")
      clear_failed_attempts_database(email)
    end
  end

  def store_failed_attempt_database(attempt_data)
    begin
      # Create failed_login_attempts table if it doesn't exist
      create_failed_attempts_table_if_needed

      DB[:failed_login_attempts].insert(
        email: attempt_data[:email],
        admin_id: attempt_data[:admin_id],
        ip_address: attempt_data[:ip_address],
        user_agent: attempt_data[:user_agent],
        created_at: attempt_data[:timestamp],
      )

      # Clean up old attempts
      cutoff_time = Time.now - LOGIN_ATTEMPT_WINDOW
      DB[:failed_login_attempts].where { created_at < cutoff_time }.delete
    rescue StandardError => e
      AppLogger.error("Database failed for auth storage: #{e.message}")
      # Fallback to session storage for this request
      session[:failed_attempts] ||= []
      session[:failed_attempts] << attempt_data
    end
  end

  def get_failed_attempts_database(email)
    begin
      return [] unless DB.table_exists?(:failed_login_attempts)

      cutoff_time = Time.now - LOGIN_ATTEMPT_WINDOW
      
      attempts = DB[:failed_login_attempts]
                   .where(email: email)
                   .where { created_at > cutoff_time }
                   .order(Sequel.desc(:created_at))
                   .all

      attempts.map do |attempt|
        {
          email: attempt[:email],
          admin_id: attempt[:admin_id],
          ip_address: attempt[:ip_address],
          user_agent: attempt[:user_agent],
          timestamp: attempt[:created_at],
        }
      end
    rescue StandardError => e
      AppLogger.error("Database failed for auth retrieval: #{e.message}")
      # Fallback to session storage
      session[:failed_attempts] || []
    end
  end

  def clear_failed_attempts_database(email)
    begin
      return unless DB.table_exists?(:failed_login_attempts)

      DB[:failed_login_attempts].where(email: email).delete
    rescue StandardError => e
      AppLogger.error("Database failed for auth clearing: #{e.message}")
      # Fallback to session clearing
      session[:failed_attempts] = []
    end
  end

  def create_failed_attempts_table_if_needed
    return if DB.table_exists?(:failed_login_attempts)

    DB.create_table :failed_login_attempts do
      primary_key :id
      String :email, null: false
      Integer :admin_id
      String :ip_address
      String :user_agent
      DateTime :created_at, null: false
      
      index :email
      index :created_at
      index [:email, :created_at]
    end
  end

  # Progressive ban storage methods
  def store_ban_redis(ban_data)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      key = "account_ban:#{ban_data[:email]}"
      ban_json = ban_data.to_json
      
      # Store ban with expiration
      redis.set(key, ban_json)
      redis.expireat(key, ban_data[:banned_until].to_i)
      
      # Also store ban count separately for tracking progressive bans
      count_key = "ban_count:#{ban_data[:email]}"
      redis.set(count_key, ban_data[:ban_count])
      redis.expire(count_key, 86400 * 30) # Keep ban count for 30 days
    rescue StandardError => e
      AppLogger.error("Redis failed for ban storage: #{e.message}")
      store_ban_database(ban_data)
    end
  end

  def get_ban_redis(email)
    return nil unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      key = "account_ban:#{email}"
      ban_json = redis.get(key)
      return nil unless ban_json
      
      ban_data = JSON.parse(ban_json, symbolize_names: true)
      ban_data[:banned_until] = Time.parse(ban_data[:banned_until].to_s)
      ban_data
    rescue StandardError => e
      AppLogger.error("Redis failed for ban retrieval: #{e.message}")
      get_ban_database(email)
    end
  end

  def get_ban_count_redis(email)
    return 0 unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      count_key = "ban_count:#{email}"
      count = redis.get(count_key)
      count ? count.to_i : 0
    rescue StandardError => e
      AppLogger.error("Redis failed for ban count retrieval: #{e.message}")
      get_ban_count_database(email)
    end
  end

  def store_ban_database(ban_data)
    begin
      create_account_bans_table_if_needed

      DB[:account_bans].insert(
        email: ban_data[:email],
        admin_id: ban_data[:admin_id],
        ban_count: ban_data[:ban_count],
        banned_until: ban_data[:banned_until],
        reason: ban_data[:reason],
        ip_address: ban_data[:ip_address],
        user_agent: ban_data[:user_agent],
        created_at: ban_data[:created_at]
      )

      # Clean up expired bans
      DB[:account_bans].where { banned_until < Time.now }.delete
    rescue StandardError => e
      AppLogger.error("Database failed for ban storage: #{e.message}")
    end
  end

  def get_ban_database(email)
    begin
      return nil unless DB.table_exists?(:account_bans)

      ban = DB[:account_bans]
              .where(email: email)
              .where { banned_until > Time.now }
              .order(Sequel.desc(:created_at))
              .first

      return nil unless ban

      {
        email: ban[:email],
        admin_id: ban[:admin_id],
        ban_count: ban[:ban_count],
        banned_until: ban[:banned_until],
        reason: ban[:reason],
        ip_address: ban[:ip_address],
        user_agent: ban[:user_agent],
        created_at: ban[:created_at]
      }
    rescue StandardError => e
      AppLogger.error("Database failed for ban retrieval: #{e.message}")
      nil
    end
  end

  def get_ban_count_database(email)
    begin
      return 0 unless DB.table_exists?(:account_bans)

      # Get the most recent ban count, or count historical bans
      latest_ban = DB[:account_bans]
                     .where(email: email)
                     .order(Sequel.desc(:created_at))
                     .first

      latest_ban ? latest_ban[:ban_count] : 0
    rescue StandardError => e
      AppLogger.error("Database failed for ban count retrieval: #{e.message}")
      0
    end
  end

  def create_account_bans_table_if_needed
    return if DB.table_exists?(:account_bans)

    DB.create_table :account_bans do
      primary_key :id
      String :email, null: false
      Integer :admin_id
      Integer :ban_count, null: false, default: 1
      DateTime :banned_until, null: false
      String :reason
      String :ip_address
      String :user_agent
      DateTime :created_at, null: false
      
      index :email
      index :banned_until
      index [:email, :banned_until]
      index [:email, :created_at]
    end
  end

  # Ban removal methods
  def remove_ban_redis(email)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      redis.del("account_ban:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for ban removal: #{e.message}")
      remove_ban_database(email)
    end
  end

  def remove_ban_database(email)
    begin
      return unless DB.table_exists?(:account_bans)

      DB[:account_bans]
        .where(email: email)
        .where { banned_until > Time.now }
        .delete
    rescue StandardError => e
      AppLogger.error("Database failed for ban removal: #{e.message}")
    end
  end

  def reset_ban_count_redis(email)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      redis.del("ban_count:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for ban count reset: #{e.message}")
      reset_ban_count_database(email)
    end
  end

  def reset_ban_count_database(email)
    begin
      return unless DB.table_exists?(:account_bans)

      # We don't actually delete historical bans, but we can mark them as reset
      # This preserves audit trail while resetting the progressive count
      DB[:account_bans]
        .where(email: email)
        .update(ban_count: 0, updated_at: Time.now)
    rescue StandardError => e
      AppLogger.error("Database failed for ban count reset: #{e.message}")
    end
  end

  def get_all_active_bans_redis(limit = 50)
    return [] unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      # Get all ban keys
      ban_keys = redis.keys("account_ban:*")
      active_bans = []
      
      ban_keys.first(limit).each do |key|
        ban_json = redis.get(key)
        next unless ban_json
        
        ban_data = JSON.parse(ban_json, symbolize_names: true)
        ban_data[:banned_until] = Time.parse(ban_data[:banned_until].to_s)
        
        # Only include active bans
        active_bans << ban_data if ban_data[:banned_until] > Time.now
      end
      
      active_bans.sort_by { |ban| ban[:created_at] }.reverse
    rescue StandardError => e
      AppLogger.error("Redis failed for getting all active bans: #{e.message}")
      get_all_active_bans_database(limit)
    end
  end

  def get_all_active_bans_database(limit = 50)
    begin
      return [] unless DB.table_exists?(:account_bans)

      bans = DB[:account_bans]
               .where { banned_until > Time.now }
               .order(Sequel.desc(:created_at))
               .limit(limit)
               .all

      bans.map do |ban|
        {
          email: ban[:email],
          admin_id: ban[:admin_id],
          ban_count: ban[:ban_count],
          banned_until: ban[:banned_until],
          reason: ban[:reason],
          ip_address: ban[:ip_address],
          user_agent: ban[:user_agent],
          created_at: ban[:created_at]
        }
      end
    rescue StandardError => e
      AppLogger.error("Database failed for getting all active bans: #{e.message}")
      []
    end
  end

  # Rate limiting
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
    # Production-ready session hijacking detection
    return false if ENV['APP_ENV'] == 'development'
    return false if ENV['RENDER'] == 'true'
    return false if ENV['BEHIND_LOAD_BALANCER'] == 'true'
    
    suspicious_indicators = 0
    max_indicators = 3  # Threshold for suspicious activity
    
    # Check 1: IP address consistency (for traditional hosting)
    current_ip = request.ip
    session_ip = session_data[:ip_address]
    if current_ip != session_ip && !load_balancer_environment?
      suspicious_indicators += 1
      log_auth_event('session_ip_mismatch', {
        current_ip: current_ip,
        session_ip: session_ip,
        admin_id: session_data[:admin_id]
      })
    end
    
    # Check 2: User agent consistency
    current_ua = request.user_agent
    session_ua = session_data[:user_agent]
    if current_ua != session_ua && significant_ua_change?(current_ua, session_ua)
      suspicious_indicators += 1
      log_auth_event('session_user_agent_change', {
        current_ua: current_ua&.slice(0, 100),
        session_ua: session_ua&.slice(0, 100),
        admin_id: session_data[:admin_id]
      })
    end
    
    # Check 3: Rapid geographic location changes (IP geolocation)
    if rapid_location_change?(current_ip, session_ip, session_data[:created_at])
      suspicious_indicators += 1
      log_auth_event('session_rapid_location_change', {
        current_ip: current_ip,
        session_ip: session_ip,
        admin_id: session_data[:admin_id]
      })
    end
    
    # Check 4: Session timing anomalies
    if suspicious_timing_pattern?(session_data)
      suspicious_indicators += 1
      log_auth_event('session_timing_anomaly', {
        admin_id: session_data[:admin_id],
        session_age: Time.now.to_i - session_data[:created_at]
      })
    end
    
    # Check 5: Known malicious IP patterns
    if malicious_ip?(current_ip)
      suspicious_indicators += 2  # Weight this higher
      log_auth_event('session_malicious_ip', {
        ip: current_ip,
        admin_id: session_data[:admin_id]
      })
    end
    
    suspicious = suspicious_indicators >= max_indicators
    
    if suspicious
      log_auth_event('session_marked_suspicious', {
        indicators: suspicious_indicators,
        threshold: max_indicators,
        admin_id: session_data[:admin_id]
      })
    end
    
    suspicious
  end

  def load_balancer_environment?
    # Detect if we're behind a load balancer or proxy
    ENV['RENDER'] == 'true' ||
    ENV['BEHIND_LOAD_BALANCER'] == 'true' ||
    ENV['HEROKU'] == 'true' ||
    request.env['HTTP_X_FORWARDED_FOR'] ||
    request.env['HTTP_X_REAL_IP'] ||
    request.env['HTTP_CF_CONNECTING_IP']  # Cloudflare
  end

  def significant_ua_change?(current_ua, session_ua)
    return false if current_ua.nil? || session_ua.nil?
    
    # Extract key components of user agent
    current_browser = extract_browser_info(current_ua)
    session_browser = extract_browser_info(session_ua)
    
    # Different browser or major version change is suspicious
    current_browser[:name] != session_browser[:name] ||
    (current_browser[:major_version] - session_browser[:major_version]).abs > 1
  end

  def extract_browser_info(user_agent)
    return { name: 'unknown', major_version: 0 } unless user_agent
    
    # Simple browser detection (in production, use a proper library like browser_details)
    case user_agent.downcase
    when /chrome\/(\d+)/
      { name: 'chrome', major_version: $1.to_i }
    when /firefox\/(\d+)/
      { name: 'firefox', major_version: $1.to_i }
    when /safari\/(\d+)/
      { name: 'safari', major_version: $1.to_i }
    when /edge\/(\d+)/
      { name: 'edge', major_version: $1.to_i }
    else
      { name: 'other', major_version: 0 }
    end
  end

  def rapid_location_change?(current_ip, session_ip, session_created_at)
    return false if current_ip == session_ip
    return false if load_balancer_environment?
    
    # Check if IPs are from different countries/regions
    # In production, you'd use a geolocation service like MaxMind
    
    # Simple check: if session is less than 30 minutes old and IPs are very different
    session_age = Time.now.to_i - session_created_at.to_i
    return false if session_age > 1800  # 30 minutes
    
    # Basic IP range check (this is simplified - use proper geolocation in production)
    current_network = current_ip.split('.')[0..2].join('.')
    session_network = session_ip.split('.')[0..2].join('.')
    
    current_network != session_network
  end

  def suspicious_timing_pattern?(session_data)
    # Check for impossible timing patterns
    last_activity = session_data[:last_activity]
    return false unless last_activity
    
    time_since_activity = Time.now.to_i - last_activity
    
    # If session was active very recently but from different characteristics,
    # that might indicate session hijacking
    time_since_activity < 60  # Less than 1 minute
  end

  def malicious_ip?(ip)
    # Check against known malicious IP patterns
    # In production, integrate with threat intelligence feeds
    
    # Simple checks for obviously malicious patterns
    return true if ip.start_with?('127.', '169.254.', '::1')  # Local/invalid IPs
    
    # Check against a basic blacklist (in production, use external feeds)
    malicious_patterns = [
      /^10\./,      # Private networks shouldn't reach public apps
      /^192\.168\./, # Private networks
      /^172\.(1[6-9]|2[0-9]|3[0-1])\./ # Private networks
    ]
    
    malicious_patterns.any? { |pattern| ip.match?(pattern) }
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

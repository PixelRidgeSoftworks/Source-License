# frozen_string_literal: true

# Source-License: Security Features Module
# Handles account bans, failed attempts tracking, and security monitoring

module Auth::SecurityFeatures
  include BaseAuth

  #
  # ACCOUNT SECURITY MONITORING
  #

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

  #
  # TWO-FACTOR AUTHENTICATION
  #

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

  #
  # RATE LIMITING
  #

  # Rate limiting helpers
  def rate_limit_key(identifier = nil)
    identifier ||= request.ip
    "rate_limit:#{identifier}"
  end

  def rate_limit_exceeded?(_max_requests = 100, _window = 3600, _identifier = nil)
    # This is a basic implementation - might want to use Redis
    # For now, we'll just return false (no rate limiting - not exceeded)
    false
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
      created_at: Time.now,
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
      ip: request_info[:ip],
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
    elsif seconds < 86_400
      "#{seconds / 3600} hours"
    else
      "#{seconds / 86_400} days"
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
      removed_by_email: admin_who_removed&.email || 'system',
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
      reset_by_email: admin_who_reset&.email || 'system',
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

  private

  # Production-ready storage methods
  def store_failed_attempt_redis(attempt_data)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

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
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

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
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))
      redis.del("failed_attempts:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for auth clearing: #{e.message}")
      clear_failed_attempts_database(email)
    end
  end

  def store_failed_attempt_database(attempt_data)
    # Create failed_login_attempts table if it doesn't exist
    create_failed_attempts_table_if_needed

    DB[:failed_login_attempts].insert(
      email: attempt_data[:email],
      admin_id: attempt_data[:admin_id],
      ip_address: attempt_data[:ip_address],
      user_agent: attempt_data[:user_agent],
      created_at: attempt_data[:timestamp]
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

  def get_failed_attempts_database(email)
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

  def clear_failed_attempts_database(email)
    return unless DB.table_exists?(:failed_login_attempts)

    DB[:failed_login_attempts].where(email: email).delete
  rescue StandardError => e
    AppLogger.error("Database failed for auth clearing: #{e.message}")
    # Fallback to session clearing
    session[:failed_attempts] = []
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
      index %i[email created_at]
    end
  end

  # Progressive ban storage methods
  def store_ban_redis(ban_data)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

      key = "account_ban:#{ban_data[:email]}"
      ban_json = ban_data.to_json

      # Store ban with expiration
      redis.set(key, ban_json)
      redis.expireat(key, ban_data[:banned_until].to_i)

      # Also store ban count separately for tracking progressive bans
      count_key = "ban_count:#{ban_data[:email]}"
      redis.set(count_key, ban_data[:ban_count])
      redis.expire(count_key, 86_400 * 30) # Keep ban count for 30 days
    rescue StandardError => e
      AppLogger.error("Redis failed for ban storage: #{e.message}")
      store_ban_database(ban_data)
    end
  end

  def get_ban_redis(email)
    return nil unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

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
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

      count_key = "ban_count:#{email}"
      count = redis.get(count_key)
      count ? count.to_i : 0
    rescue StandardError => e
      AppLogger.error("Redis failed for ban count retrieval: #{e.message}")
      get_ban_count_database(email)
    end
  end

  def store_ban_database(ban_data)
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

  def get_ban_database(email)
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
      created_at: ban[:created_at],
    }
  rescue StandardError => e
    AppLogger.error("Database failed for ban retrieval: #{e.message}")
    nil
  end

  def get_ban_count_database(email)
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
      index %i[email banned_until]
      index %i[email created_at]
    end
  end

  # Ban removal methods
  def remove_ban_redis(email)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))
      redis.del("account_ban:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for ban removal: #{e.message}")
      remove_ban_database(email)
    end
  end

  def remove_ban_database(email)
    return unless DB.table_exists?(:account_bans)

    DB[:account_bans]
      .where(email: email)
      .where { banned_until > Time.now }
      .delete
  rescue StandardError => e
    AppLogger.error("Database failed for ban removal: #{e.message}")
  end

  def reset_ban_count_redis(email)
    return unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))
      redis.del("ban_count:#{email}")
    rescue StandardError => e
      AppLogger.error("Redis failed for ban count reset: #{e.message}")
      reset_ban_count_database(email)
    end
  end

  def reset_ban_count_database(email)
    return unless DB.table_exists?(:account_bans)

    # We don't actually delete historical bans, but we can mark them as reset
    # This preserves audit trail while resetting the progressive count
    DB[:account_bans]
      .where(email: email)
      .update(ban_count: 0, updated_at: Time.now)
  rescue StandardError => e
    AppLogger.error("Database failed for ban count reset: #{e.message}")
  end

  def get_all_active_bans_redis(limit = 50)
    return [] unless use_redis_for_auth?

    begin
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))

      # Get all ban keys
      ban_keys = redis.keys('account_ban:*')
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
        created_at: ban[:created_at],
      }
    end
  rescue StandardError => e
    AppLogger.error("Database failed for getting all active bans: #{e.message}")
    []
  end

  def common_password?(password)
    # Check against a list of common passwords
    common_passwords = %w[
      password password123 admin admin123 123456 qwerty
      letmein welcome changeme password1 abc123 administrator
    ]

    common_passwords.include?(password.downcase)
  end

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

  def password_expires_soon?(admin, warning_days = 7)
    return false unless admin.password_changed_at

    days_since_change = (Time.now - admin.password_changed_at) / (24 * 60 * 60)
    days_until_expiry = PASSWORD_EXPIRY_DAYS - days_since_change

    days_until_expiry <= warning_days && days_until_expiry.positive?
  end
end

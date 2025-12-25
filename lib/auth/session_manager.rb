# frozen_string_literal: true

# Source-License: Session Management Module
# Handles secure session creation, validation, and lifecycle management

module Auth::SessionManager
  include Auth::BaseAuth

  #
  # ENHANCED SESSION MANAGEMENT
  #

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
        reason: admin ? 'account_deactivated' : 'account_deleted',
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

  # Get current authenticated admin (enhanced version)
  def current_secure_admin
    return nil unless validate_session

    session_data = session[:admin_session]
    return nil unless session_data

    @current_secure_admin ||= Admin[session_data[:admin_id]]
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
    max_indicators = 3 # Threshold for suspicious activity

    # Check 1: IP address consistency (for traditional hosting)
    current_ip = request.ip
    session_ip = session_data[:ip_address]
    if current_ip != session_ip && !load_balancer_environment?
      suspicious_indicators += 1
      log_auth_event('session_ip_mismatch', {
        current_ip: current_ip,
        session_ip: session_ip,
        admin_id: session_data[:admin_id],
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
        admin_id: session_data[:admin_id],
      })
    end

    # Check 3: Rapid geographic location changes (IP geolocation)
    if rapid_location_change?(current_ip, session_ip, session_data[:created_at])
      suspicious_indicators += 1
      log_auth_event('session_rapid_location_change', {
        current_ip: current_ip,
        session_ip: session_ip,
        admin_id: session_data[:admin_id],
      })
    end

    # Check 4: Session timing anomalies
    if suspicious_timing_pattern?(session_data)
      suspicious_indicators += 1
      log_auth_event('session_timing_anomaly', {
        admin_id: session_data[:admin_id],
        session_age: Time.now.to_i - session_data[:created_at],
      })
    end

    # Check 5: Known malicious IP patterns
    if malicious_ip?(current_ip)
      suspicious_indicators += 2
      log_auth_event('session_malicious_ip', {
        ip: current_ip,
        admin_id: session_data[:admin_id],
      })
    end

    suspicious = suspicious_indicators >= max_indicators

    if suspicious
      log_auth_event('session_marked_suspicious', {
        indicators: suspicious_indicators,
        threshold: max_indicators,
        admin_id: session_data[:admin_id],
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
      request.env['HTTP_CF_CONNECTING_IP'] # Cloudflare
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

    # Simple browser detection (in future, use a proper library like browser_details)
    case user_agent.downcase
    when /chrome\/(\d+)/
      { name: 'chrome', major_version: ::Regexp.last_match(1).to_i }
    when /firefox\/(\d+)/
      { name: 'firefox', major_version: ::Regexp.last_match(1).to_i }
    when /safari\/(\d+)/
      { name: 'safari', major_version: ::Regexp.last_match(1).to_i }
    when /edge\/(\d+)/
      { name: 'edge', major_version: ::Regexp.last_match(1).to_i }
    else
      { name: 'other', major_version: 0 }
    end
  end

  def rapid_location_change?(current_ip, session_ip, session_created_at)
    return false if current_ip == session_ip
    return false if load_balancer_environment?

    # Check if IPs are from different countries/regions
    # TODO: use a geolocation service like MaxMind

    # Simple check: if session is less than 30 minutes old and IPs are very different
    session_age = Time.now.to_i - session_created_at.to_i
    return false if session_age > 1800 # 30 minutes

    # Basic IP range check (this is simplified - use proper geolocation in future)
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
    time_since_activity < 60 # Less than 1 minute
  end

  def malicious_ip?(ip)
    # Check against known malicious IP patterns
    # TODO: integrate with threat intelligence feeds

    # Simple checks for obviously malicious patterns
    return true if ip.start_with?('127.', '169.254.', '::1') # Local/invalid IPs

    # Check against a basic blacklist
    # TODO: use external feeds
    malicious_patterns = [
      /^10\./, # Private networks shouldn't reach public apps
      /^192\.168\./, # Private networks
      /^172\.(1[6-9]|2[0-9]|3[0-1])\./, # Private networks
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

    # might want to maintain a blacklist of invalidated sessions
    @current_secure_admin = nil
  end
end

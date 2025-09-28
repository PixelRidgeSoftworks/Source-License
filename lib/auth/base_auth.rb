# frozen_string_literal: true

# Source-License: Base Authentication Module
# Core authentication functionality and configuration

require 'bcrypt'
require 'jwt'
require 'digest'
require 'securerandom'

module Auth::BaseAuth
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
    168 * 60 * 60, # 6th+ ban: 168 hours (7 days)
  ].freeze

  # Session security configuration
  SESSION_TIMEOUT = 8 * 60 * 60 # 8 hours
  SESSION_ROTATION_INTERVAL = 2 * 60 * 60 # 2 hours

  # Password policy configuration
  MIN_PASSWORD_LENGTH = 12
  PASSWORD_EXPIRY_DAYS = 90

  private

  # Get JWT secret from environment or generate one
  def jwt_secret
    ENV['JWT_SECRET'] || ENV['APP_SECRET'] || 'default_jwt_secret_change_me'
  end

  # Security response helper
  def security_response(success, message, data = {})
    {
      success: success,
      message: message,
      timestamp: Time.now.iso8601,
    }.merge(data)
  end

  # Validation helpers
  def valid_email_format?(email)
    return false unless email.is_a?(String)
    return false if email.length > 254

    email_regex = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i
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

  # Production-ready storage methods
  def use_redis_for_auth?
    ENV.fetch('REDIS_URL', nil) && !ENV['REDIS_URL'].empty?
  end
end

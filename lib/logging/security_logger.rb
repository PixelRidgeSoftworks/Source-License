# frozen_string_literal: true

# Security event logging functionality
class SecurityLogger
  def initialize(logger)
    @logger = logger
    @app_name = logger.instance_variable_get(:@app_name)
    @environment = logger.instance_variable_get(:@environment)
    @version = logger.instance_variable_get(:@version)
  end

  def log_security_event(event_type, details = {})
    context = {
      event_type: 'security',
      security_event: event_type,
      details: details,
      severity: determine_security_severity(event_type),
    }

    level = context[:severity] == 'critical' ? :error : :warn
    @logger.log(level, "Security event: #{event_type}", context)

    # Send to security monitoring if configured
    send_security_alert(event_type, details) if should_alert_security?(event_type)
  end

  private

  def determine_security_severity(event_type)
    critical_events = %w[
      admin_account_compromised
      payment_fraud_detected
      data_breach_detected
      unauthorized_admin_access
      multiple_failed_logins
      account_lockout_triggered
    ]

    high_events = %w[
      failed_login_attempt
      suspicious_payment
      rate_limit_exceeded
      invalid_webhook_signature
      csrf_attack_detected
    ]

    return 'critical' if critical_events.include?(event_type)
    return 'high' if high_events.include?(event_type)

    'medium'
  end

  def should_alert_security?(event_type)
    return false unless ENV['SECURITY_WEBHOOK_URL']

    alert_events = %w[
      admin_account_compromised
      payment_fraud_detected
      data_breach_detected
      unauthorized_admin_access
      multiple_failed_logins
      account_lockout_triggered
    ]

    alert_events.include?(event_type)
  end

  def send_security_alert(event_type, details)
    return unless ENV['SECURITY_WEBHOOK_URL']

    Thread.new do
      require 'net/http'
      require 'uri'

      uri = URI(ENV.fetch('SECURITY_WEBHOOK_URL', nil))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = {
        alert_type: 'security_event',
        event_type: event_type,
        severity: determine_security_severity(event_type),
        timestamp: Time.now.iso8601,
        environment: @environment,
        application: @app_name,
        version: @version,
        details: details,
      }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        @logger.warn("Failed to send security alert: #{response.code} #{response.message}")
      end
    rescue StandardError => e
      @logger.error("Failed to send security alert: #{e.message}")
    end
  end
end

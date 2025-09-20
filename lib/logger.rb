# frozen_string_literal: true

# Source-License: Production Logging System
# Structured logging for production environments

require 'logger'
require 'json'

class ProductionLogger
  attr_reader :logger

  def initialize
    @logger = setup_logger
    @app_name = 'source-license'
    @environment = ENV['APP_ENV'] || 'development'
    @version = ENV['APP_VERSION'] || 'unknown'
  end

  def self.instance
    @instance ||= new
  end

  def setup_logger
    log_level = parse_log_level(ENV['LOG_LEVEL'] || 'info')
    log_format = ENV['LOG_FORMAT'] || 'text'

    logger = Logger.new($stdout)
    logger.level = log_level

    # Set custom formatter based on environment
    logger.formatter = if log_format == 'json' || ENV['APP_ENV'] == 'production'
                         method(:json_formatter)
                       else
                         method(:text_formatter)
                       end

    logger
  end

  def info(message, context = {})
    log(:info, message, context)
  end

  def warn(message, context = {})
    log(:warn, message, context)
  end

  def error(message, context = {})
    log(:error, message, context)
  end

  def debug(message, context = {})
    log(:debug, message, context)
  end

  def fatal(message, context = {})
    log(:fatal, message, context)
  end

  # Security event logging
  def security(event_type, details = {})
    context = {
      event_type: 'security',
      security_event: event_type,
      details: details,
      severity: determine_security_severity(event_type),
    }

    level = context[:severity] == 'critical' ? :error : :warn
    log(level, "Security event: #{event_type}", context)

    # Send to security monitoring if configured
    send_security_alert(event_type, details) if should_alert_security?(event_type)
  end

  # Authentication event logging
  def auth(event_type, details = {})
    context = {
      event_type: 'authentication',
      auth_event: event_type,
      details: details,
    }

    log(:info, "Auth event: #{event_type}", context)
  end

  # Payment event logging
  def payment(event_type, details = {})
    # Sanitize payment details to remove sensitive data
    sanitized_details = sanitize_payment_details(details)

    context = {
      event_type: 'payment',
      payment_event: event_type,
      details: sanitized_details,
    }

    log(:info, "Payment event: #{event_type}", context)
  end

  # API request logging
  def api_request(method, path, status, duration, details = {})
    context = {
      event_type: 'api_request',
      http_method: method,
      path: path,
      status_code: status,
      duration_ms: duration,
      details: details,
    }

    level = if status >= 500
              :error
            else
              (status >= 400 ? :warn : :info)
            end
    log(level, "#{method} #{path} #{status} (#{duration}ms)", context)
  end

  # Error logging with exception details
  def exception(exception, context = {})
    error_context = {
      event_type: 'exception',
      exception_class: exception.class.name,
      exception_message: exception.message,
      backtrace: exception.backtrace&.first(10),
      context: context,
    }

    # Log locally
    log(:error, "Exception: #{exception.class.name}: #{exception.message}", error_context)

    # Send to error tracking service if configured
    send_to_error_tracking(exception, context)
  end

  private

  def log(level, message, context = {})
    log_entry = build_log_entry(level, message, context)
    @logger.send(level, log_entry)
  end

  def build_log_entry(level, message, context)
    base_context = {
      timestamp: Time.now.iso8601,
      level: level.to_s.upcase,
      message: message,
      app: @app_name,
      environment: @environment,
      version: @version,
      pid: Process.pid,
      thread_id: Thread.current.object_id,
    }

    base_context.merge(context)
  end

  def json_formatter(severity, datetime, _progname, msg)
    if msg.is_a?(Hash)
      "#{msg.to_json}\n"
    else
      {
        timestamp: datetime.iso8601,
        level: severity,
        message: msg,
        app: @app_name,
        environment: @environment,
        version: @version,
      }.to_json + "\n"
    end
  end

  def text_formatter(severity, datetime, _progname, msg)
    if msg.is_a?(Hash)
      "[#{datetime}] #{severity} #{@app_name}: #{msg[:message] || msg.inspect}\n"
    else
      "[#{datetime}] #{severity} #{@app_name}: #{msg}\n"
    end
  end

  def parse_log_level(level_string)
    case level_string.downcase
    when 'debug' then Logger::DEBUG
    when 'info' then Logger::INFO
    when 'warn', 'warning' then Logger::WARN
    when 'error' then Logger::ERROR
    when 'fatal' then Logger::FATAL
    else Logger::INFO
    end
  end

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
        warn("Failed to send security alert: #{response.code} #{response.message}")
      end
    rescue StandardError => e
      error("Failed to send security alert: #{e.message}")
    end
  end

  def sanitize_payment_details(details)
    # Remove sensitive payment information
    sanitized = details.dup

    # Remove or mask sensitive fields
    sensitive_fields = %w[
      credit_card_number
      cvv
      ssn
      bank_account_number
      stripe_secret_key
      paypal_client_secret
    ]

    sensitive_fields.each do |field|
      if sanitized[field] || sanitized[field.to_sym]
        sanitized[field] = '[REDACTED]'
        sanitized[field.to_sym] = '[REDACTED]'
      end
    end

    # Mask partial information
    sanitized[:email] = mask_email(sanitized[:email]) if sanitized[:email]

    sanitized['email'] = mask_email(sanitized['email']) if sanitized['email']

    sanitized
  end

  def mask_email(email)
    return email unless email.include?('@')

    local, domain = email.split('@')
    masked_local = local.length > 2 ? "#{local[0]}***#{local[-1]}" : '***'
    "#{masked_local}@#{domain}"
  end

  # Error tracking integration
  def send_to_error_tracking(exception, context = {})
    return unless ENV['ERROR_TRACKING_DSN']

    Thread.new do
      case detect_error_service
      when :sentry
        send_to_sentry(exception, context)
      when :bugsnag
        send_to_bugsnag(exception, context)
      when :rollbar
        send_to_rollbar(exception, context)
      when :airbrake
        send_to_airbrake(exception, context)
      when :honeybadger
        send_to_honeybadger(exception, context)
      when :webhook
        send_error_webhook(exception, context)
      end
    rescue StandardError => e
      warn("Failed to send error to tracking service: #{e.message}")
    end
  end

  def detect_error_service
    dsn = ENV['ERROR_TRACKING_DSN'].to_s.downcase

    # Parse URL to check host properly instead of substring matching
    begin
      uri = URI(dsn)
      host = uri.host&.downcase
      
      return :sentry if host == 'sentry.io' || host&.end_with?('.sentry.io') || host == 'ingest.sentry.io' || host&.end_with?('.ingest.sentry.io')
      return :bugsnag if host == 'bugsnag.com' || host&.end_with?('.bugsnag.com')
      return :rollbar if host == 'rollbar.com' || host&.end_with?('.rollbar.com')
      return :airbrake if host == 'airbrake.io' || host&.end_with?('.airbrake.io')
      return :honeybadger if host == 'honeybadger.io' || host&.end_with?('.honeybadger.io')
      return :webhook if dsn.start_with?('http')
    rescue URI::InvalidURIError
      # If URL parsing fails, return unknown
      return :unknown
    end

    :unknown
  end

  def send_to_sentry(exception, context)
    require 'net/http'
    require 'uri'
    require 'base64'

    dsn_uri = URI(ENV.fetch('ERROR_TRACKING_DSN', nil))
    public_key = dsn_uri.user
    secret_key = dsn_uri.password
    project_id = dsn_uri.path.split('/').last

    # Sentry API endpoint
    api_url = "#{dsn_uri.scheme}://#{dsn_uri.host}/api/#{project_id}/store/"

    # Build Sentry payload
    payload = {
      event_id: SecureRandom.hex(16),
      timestamp: Time.now.iso8601,
      level: 'error',
      platform: 'ruby',
      sdk: { name: 'source-license-logger', version: @version },
      server_name: ENV['HOSTNAME'] || 'unknown',
      environment: @environment,
      release: @version,
      exception: {
        values: [{
          type: exception.class.name,
          value: exception.message,
          stacktrace: {
            frames: (exception.backtrace || []).map do |line|
              file, line_no, method = line.split(':')
              {
                filename: file,
                lineno: line_no.to_i,
                function: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
              }
            end,
          },
        }],
      },
      extra: context,
      tags: {
        component: 'source-license',
        version: @version,
      },
    }

    # Create HTTP request
    uri = URI(api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['X-Sentry-Auth'] = build_sentry_auth_header(public_key, secret_key)
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Sentry error tracking failed: #{response.code} #{response.message}")
  end

  def send_to_bugsnag(exception, context)
    require 'net/http'
    require 'uri'

    api_key = ENV.fetch('ERROR_TRACKING_DSN', nil)

    payload = {
      apiKey: api_key,
      notifier: {
        name: 'Source License Logger',
        version: @version,
        url: 'https://github.com/source-license',
      },
      events: [{
        payloadVersion: '5',
        exceptions: [{
          errorClass: exception.class.name,
          message: exception.message,
          stacktrace: (exception.backtrace || []).map do |line|
            file, line_no, method = line.split(':')
            {
              file: file,
              lineNumber: line_no.to_i,
              method: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
            }
          end,
        }],
        context: context[:path] || 'source-license',
        severity: 'error',
        unhandled: false,
        app: {
          version: @version,
          releaseStage: @environment,
        },
        device: {
          hostname: ENV['HOSTNAME'] || 'unknown',
        },
        metaData: { custom: context },
      }],
    }

    uri = URI('https://notify.bugsnag.com/')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Bugsnag error tracking failed: #{response.code} #{response.message}")
  end

  def send_to_rollbar(exception, context)
    require 'net/http'
    require 'uri'

    access_token = ENV.fetch('ERROR_TRACKING_DSN', nil)

    payload = {
      access_token: access_token,
      data: {
        environment: @environment,
        level: 'error',
        timestamp: Time.now.to_i,
        platform: 'ruby',
        framework: 'sinatra',
        language: 'ruby',
        server: {
          host: ENV['HOSTNAME'] || 'unknown',
        },
        body: {
          trace: {
            frames: (exception.backtrace || []).map do |line|
              file, line_no, method = line.split(':')
              {
                filename: file,
                lineno: line_no.to_i,
                method: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
              }
            end,
            exception: {
              class: exception.class.name,
              message: exception.message,
            },
          },
        },
        custom: context,
        notifier: {
          name: 'source-license-logger',
          version: @version,
        },
      },
    }

    uri = URI('https://api.rollbar.com/api/1/item/')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Rollbar error tracking failed: #{response.code} #{response.message}")
  end

  def send_to_airbrake(exception, context)
    require 'net/http'
    require 'uri'

    # Airbrake requires project_id and project_key from DSN
    # Format: https://PROJECT_KEY@PROJECT_ID.airbrake.io/
    dsn_match = ENV['ERROR_TRACKING_DSN'].match(%r{https://([^@]+)@(\d+)\.airbrake\.io})
    return unless dsn_match

    project_key = dsn_match[1]
    project_id = dsn_match[2]

    payload = {
      notifier: {
        name: 'source-license-logger',
        version: @version,
        url: 'https://github.com/source-license',
      },
      errors: [{
        type: exception.class.name,
        message: exception.message,
        backtrace: (exception.backtrace || []).map do |line|
          file, line_no, method = line.split(':')
          {
            file: file,
            line: line_no.to_i,
            function: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
          }
        end,
      }],
      context: {
        version: @version,
        environment: @environment,
        hostname: ENV['HOSTNAME'] || 'unknown',
        **context,
      },
    }

    uri = URI("https://#{project_id}.airbrake.io/api/v3/projects/#{project_id}/notices")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{project_key}"
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Airbrake error tracking failed: #{response.code} #{response.message}")
  end

  def send_to_honeybadger(exception, context)
    require 'net/http'
    require 'uri'

    api_key = ENV.fetch('ERROR_TRACKING_DSN', nil)

    payload = {
      notifier: {
        name: 'source-license-logger',
        url: 'https://github.com/source-license',
        version: @version,
      },
      error: {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace || [],
      },
      request: {
        context: context,
        cgi_data: {
          'SERVER_NAME' => ENV['HOSTNAME'] || 'unknown',
          'RACK_ENV' => @environment,
        },
      },
      server: {
        environment_name: @environment,
        hostname: ENV['HOSTNAME'] || 'unknown',
        project_root: Dir.pwd,
      },
    }

    uri = URI('https://api.honeybadger.io/v1/notices')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['X-API-Key'] = api_key
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Honeybadger error tracking failed: #{response.code} #{response.message}")
  end

  def send_error_webhook(exception, context)
    require 'net/http'
    require 'uri'

    uri = URI(ENV.fetch('ERROR_TRACKING_DSN', nil))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    payload = {
      error: {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace&.first(10),
      },
      context: context,
      application: {
        name: @app_name,
        version: @version,
        environment: @environment,
        hostname: ENV['HOSTNAME'] || 'unknown',
      },
      timestamp: Time.now.iso8601,
    }

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    warn("Error webhook failed: #{response.code} #{response.message}")
  end

  def build_sentry_auth_header(public_key, secret_key)
    timestamp = Time.now.to_i
    "Sentry sentry_version=7, sentry_client=source-license-logger/#{@version}, " \
      "sentry_timestamp=#{timestamp}, sentry_key=#{public_key}, sentry_secret=#{secret_key}"
  end
end

# Global logger instance
module AppLogger
  def self.instance
    @instance ||= ProductionLogger.instance
  end

  def self.info(message, context = {})
    instance.info(message, context)
  end

  def self.warn(message, context = {})
    instance.warn(message, context)
  end

  def self.error(message, context = {})
    instance.error(message, context)
  end

  def self.debug(message, context = {})
    instance.debug(message, context)
  end

  def self.fatal(message, context = {})
    instance.fatal(message, context)
  end

  def self.security(event_type, details = {})
    instance.security(event_type, details)
  end

  def self.auth(event_type, details = {})
    instance.auth(event_type, details)
  end

  def self.payment(event_type, details = {})
    instance.payment(event_type, details)
  end

  def self.api_request(method, path, status, duration, details = {})
    instance.api_request(method, path, status, duration, details)
  end

  def self.exception(exception, context = {})
    instance.exception(exception, context)
  end
end

# Request logging middleware
class RequestLoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start_time = Time.now
    request = Rack::Request.new(env)

    # Skip logging for health checks and static assets
    return @app.call(env) if skip_logging?(request.path)

    status, headers, body = @app.call(env)
    duration = ((Time.now - start_time) * 1000).round(2)

    # Log the request
    AppLogger.api_request(
      request.request_method,
      request.path,
      status,
      duration,
      {
        ip: request.ip,
        user_agent: request.user_agent,
        query_params: request.query_string.empty? ? nil : request.query_string,
      }
    )

    [status, headers, body]
  rescue StandardError => e
    AppLogger.exception(e, {
      method: request&.request_method,
      path: request&.path,
      ip: request&.ip,
    })
    raise
  end

  private

  def skip_logging?(path)
    skip_paths = %w[/health /ready /favicon.ico]
    skip_paths.any? { |skip_path| path.start_with?(skip_path) } ||
      path.match?(/\.(css|js|png|jpg|jpeg|gif|ico|svg)$/)
  end
end

# frozen_string_literal: true

# Source-License: Production Logging System
# Structured logging for production environments

require 'logger'
require 'json'
require_relative 'logging/error_tracking'
require_relative 'logging/security_logger'
require_relative 'logging/specialized_loggers'

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
    SecurityLogger.new(self).log_security_event(event_type, details)
  end

  # Authentication event logging
  def auth(event_type, details = {})
    SpecializedLoggers.log_auth_event(self, event_type, details)
  end

  # Payment event logging
  def payment(event_type, details = {})
    SpecializedLoggers.log_payment_event(self, event_type, details)
  end

  # API request logging
  def api_request(method, path, status, duration, details = {})
    SpecializedLoggers.log_api_request(self, method, path, status, duration, details)
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
    ErrorTracking.new(@app_name, @environment, @version).send_to_service(exception, context)
  end

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

  private

  def json_formatter(severity, datetime, _progname, msg)
    if msg.is_a?(Hash)
      "#{msg.to_json}\n"
    else
      "#{
        {
          timestamp: datetime.iso8601,
          level: severity,
          message: msg,
          app: @app_name,
          environment: @environment,
          version: @version,
        }.to_json
      }\n"
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
    when 'warn', 'warning' then Logger::WARN
    when 'error' then Logger::ERROR
    when 'fatal' then Logger::FATAL
    else Logger::INFO
    end
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

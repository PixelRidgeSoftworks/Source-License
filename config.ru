# frozen_string_literal: true

# config.ru - Rack configuration file for Source-License
# This file is used to run the Sinatra application with rack servers

require 'rack/cors'
require 'rack/ssl-enforcer'
require_relative 'app'

# Production-ready CORS configuration
use Rack::Cors do
  allow do
    if ENV['APP_ENV'] == 'production'
      # Production: Restrict to specific domains
      origins ENV['ALLOWED_ORIGINS']&.split(',') || ['https://yourdomain.com']
    else
      # Development: Allow localhost and common development domains
      origins 'localhost:3000', 'localhost:4567', '127.0.0.1:3000', '127.0.0.1:4567'
    end

    resource '/api/*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: true
  end
end

# Production middleware
if ENV['APP_ENV'] == 'production'
  # Force HTTPS in production
  use Rack::SslEnforcer, hsts: { expires: 31_536_000, subdomains: true }

  # Add security headers
  use Rack::Protection::FrameOptions
  use Rack::Protection::ContentSecurityPolicy
end

# Request logging middleware
use RequestLoggingMiddleware

# Health check endpoint
map '/health' do
  run ->(env) {
    case env['REQUEST_METHOD']
    when 'GET'
      # Basic health check
      status = 200
      body = {
        status: 'healthy',
        timestamp: Time.now.iso8601,
        version: ENV['APP_VERSION'] || 'unknown',
        environment: ENV['APP_ENV'] || 'development',
        uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i,
      }

      # Check database connectivity
      begin
        if defined?(DB)
          DB.test_connection
          body[:database] = 'connected'
        else
          body[:database] = 'not_configured'
        end
      rescue StandardError => e
        status = 503
        body[:database] = 'error'
        body[:database_error] = e.message
      end

      # Check monitoring configuration
      body[:monitoring] = {
        error_tracking: ENV['ERROR_TRACKING_DSN'] ? 'configured' : 'disabled',
        security_webhooks: ENV['SECURITY_WEBHOOK_URL'] ? 'configured' : 'disabled',
        log_format: ENV['LOG_FORMAT'] || 'text',
        log_level: ENV['LOG_LEVEL'] || 'info',
      }

      # Set overall status
      body[:status] = status == 200 ? 'healthy' : 'unhealthy'

      [status, { 'Content-Type' => 'application/json' }, [body.to_json]]
    else
      [405, { 'Content-Type' => 'text/plain' }, ['Method Not Allowed']]
    end
  }
end

# Readiness check endpoint
map '/ready' do
  run ->(env) {
    case env['REQUEST_METHOD']
    when 'GET'
      # More comprehensive readiness check
      checks = {}
      overall_status = 200

      # Database check
      begin
        if defined?(DB)
          DB.test_connection
          # Try a simple query to ensure database is truly ready
          DB[:schema_info].count if DB.table_exists?(:schema_info)
          checks[:database] = { status: 'ok', message: 'Database connection and query successful' }
        else
          checks[:database] = { status: 'warning', message: 'Database not configured' }
        end
      rescue StandardError => e
        checks[:database] = { status: 'error', message: e.message }
        overall_status = 503
      end

      # Redis check (if configured)
      if ENV['REDIS_URL']
        begin
          require 'redis'
          redis = Redis.new(url: ENV['REDIS_URL'])
          redis.ping
          checks[:redis] = { status: 'ok', message: 'Redis connection successful' }
        rescue StandardError => e
          checks[:redis] = { status: 'error', message: e.message }
          overall_status = 503
        end
      else
        checks[:redis] = { status: 'disabled', message: 'Redis not configured' }
      end

      # File system check
      begin
        temp_file = '/tmp/readiness_check'
        File.write(temp_file, 'test')
        File.delete(temp_file)
        checks[:filesystem] = { status: 'ok', message: 'Filesystem writable' }
      rescue StandardError => e
        checks[:filesystem] = { status: 'error', message: e.message }
        overall_status = 503
      end

      # Error tracking check
      if ENV['ERROR_TRACKING_DSN']
        begin
          # Test basic connectivity to error tracking service
          require 'net/http'
          require 'uri'

          dsn = ENV['ERROR_TRACKING_DSN']
          if dsn.include?('sentry.io')
            uri = URI('https://sentry.io')
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.open_timeout = 5
            http.read_timeout = 5
            http.head('/')
            checks[:error_tracking] = { status: 'ok', message: 'Sentry connectivity confirmed', service: 'sentry' }
          elsif dsn.include?('bugsnag.com')
            uri = URI('https://notify.bugsnag.com')
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.open_timeout = 5
            http.read_timeout = 5
            http.head('/')
            checks[:error_tracking] = { status: 'ok', message: 'Bugsnag connectivity confirmed', service: 'bugsnag' }
          elsif dsn.start_with?('http')
            uri = URI(dsn)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = 5
            http.read_timeout = 5
            http.head(uri.path.empty? ? '/' : uri.path)
            checks[:error_tracking] =
              { status: 'ok', message: 'Custom webhook connectivity confirmed', service: 'webhook' }
          else
            checks[:error_tracking] = { status: 'ok', message: 'Error tracking configured', service: 'api_key' }
          end
        rescue StandardError => e
          checks[:error_tracking] =
            { status: 'warning', message: "Error tracking configured but unreachable: #{e.message}" }
        end
      else
        checks[:error_tracking] = { status: 'disabled', message: 'Error tracking not configured' }
      end

      # Security webhooks check
      if ENV['SECURITY_WEBHOOK_URL']
        begin
          require 'net/http'
          require 'uri'

          uri = URI(ENV['SECURITY_WEBHOOK_URL'])
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 5
          http.head(uri.path.empty? ? '/' : uri.path)
          checks[:security_webhooks] = { status: 'ok', message: 'Security webhook endpoint accessible' }
        rescue StandardError => e
          checks[:security_webhooks] =
            { status: 'warning', message: "Security webhook configured but unreachable: #{e.message}" }
        end
      else
        checks[:security_webhooks] = { status: 'disabled', message: 'Security webhooks not configured' }
      end

      # Application dependencies check
      begin
        required_dirs = %w[tmp log public]
        missing_dirs = required_dirs.reject { |dir| Dir.exist?(dir) }

        if missing_dirs.empty?
          checks[:application_structure] = { status: 'ok', message: 'All required directories present' }
        else
          checks[:application_structure] =
            { status: 'warning', message: "Missing directories: #{missing_dirs.join(', ')}" }
        end
      rescue StandardError => e
        checks[:application_structure] = { status: 'error', message: e.message }
        overall_status = 503
      end

      # Memory check
      begin
        # Basic memory usage check
        if RUBY_PLATFORM.include?('linux')
          meminfo = File.read('/proc/meminfo')
          total_memory = meminfo.match(/MemTotal:\s+(\d+) kB/)[1].to_i
          available_memory = meminfo.match(/MemAvailable:\s+(\d+) kB/)[1].to_i
          memory_usage_percent = ((total_memory - available_memory).to_f / total_memory * 100).round(1)

          checks[:memory] = if memory_usage_percent < 90
                              { status: 'ok', message: "Memory usage: #{memory_usage_percent}%" }
                            else
                              { status: 'warning', message: "High memory usage: #{memory_usage_percent}%" }
                            end
        else
          checks[:memory] = { status: 'ok', message: 'Memory check not available on this platform' }
        end
      rescue StandardError => e
        checks[:memory] = { status: 'warning', message: "Memory check failed: #{e.message}" }
      end

      # Count warnings and errors
      error_count = checks.values.count { |check| check[:status] == 'error' }
      warning_count = checks.values.count { |check| check[:status] == 'warning' }

      body = {
        status: overall_status == 200 ? 'ready' : 'not ready',
        timestamp: Time.now.iso8601,
        version: ENV['APP_VERSION'] || 'unknown',
        environment: ENV['APP_ENV'] || 'development',
        summary: {
          total_checks: checks.size,
          errors: error_count,
          warnings: warning_count,
          ok: checks.size - error_count - warning_count,
        },
        checks: checks,
      }

      [overall_status, { 'Content-Type' => 'application/json' }, [body.to_json]]
    else
      [405, { 'Content-Type' => 'text/plain' }, ['Method Not Allowed']]
    end
  }
end

# Mount the secure API controller as the primary license API
map '/api/license' do
  run SecureApiController
end

# Mount the Swagger documentation controller
map '/' do
  use SwaggerController
  run SourceLicenseApp
end

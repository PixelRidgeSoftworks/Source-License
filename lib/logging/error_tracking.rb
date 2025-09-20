# frozen_string_literal: true

# Error tracking integration for various services
class ErrorTracking
  def initialize(app_name, environment, version)
    @app_name = app_name
    @environment = environment
    @version = version
  end

  def send_to_service(exception, context = {})
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

  private

  def detect_error_service
    dsn = ENV['ERROR_TRACKING_DSN'].to_s.downcase
    return :unknown unless valid_dsn?(dsn)

    host = extract_host(dsn)
    return :unknown unless host

    detect_service_by_host(host, dsn)
  end

  def valid_dsn?(dsn)
    !dsn.empty? && dsn.start_with?('http')
  end

  def extract_host(dsn)
    uri = URI(dsn)
    uri.host&.downcase
  rescue URI::InvalidURIError
    nil
  end

  def detect_service_by_host(host, dsn)
    return :sentry if sentry_host?(host)
    return :bugsnag if bugsnag_host?(host)
    return :rollbar if rollbar_host?(host)
    return :airbrake if airbrake_host?(host)
    return :honeybadger if honeybadger_host?(host)
    return :webhook if dsn.start_with?('http')

    :unknown
  end

  def sentry_host?(host)
    host == 'sentry.io' || host&.end_with?('.sentry.io') ||
      host == 'ingest.sentry.io' || host&.end_with?('.ingest.sentry.io')
  end

  def bugsnag_host?(host)
    host == 'bugsnag.com' || host&.end_with?('.bugsnag.com')
  end

  def rollbar_host?(host)
    host == 'rollbar.com' || host&.end_with?('.rollbar.com')
  end

  def airbrake_host?(host)
    host == 'airbrake.io' || host&.end_with?('.airbrake.io')
  end

  def honeybadger_host?(host)
    host == 'honeybadger.io' || host&.end_with?('.honeybadger.io')
  end

  def send_to_sentry(exception, context)
    require 'net/http'
    require 'uri'
    require 'base64'
    require 'securerandom'

    dsn_uri = URI(ENV.fetch('ERROR_TRACKING_DSN', nil))
    payload = build_sentry_payload(exception, context, dsn_uri)
    send_sentry_request(payload, dsn_uri)
  end

  def build_sentry_payload(exception, context, _dsn_uri)
    {
      event_id: SecureRandom.hex(16),
      timestamp: Time.now.iso8601,
      level: 'error',
      platform: 'ruby',
      sdk: { name: 'source-license-logger', version: @version },
      server_name: ENV['HOSTNAME'] || 'unknown',
      environment: @environment,
      release: @version,
      exception: build_sentry_exception(exception),
      extra: context,
      tags: { component: 'source-license', version: @version },
    }
  end

  def build_sentry_exception(exception)
    {
      values: [{
        type: exception.class.name,
        value: exception.message,
        stacktrace: {
          frames: (exception.backtrace || []).map do |line|
            parse_backtrace_line(line)
          end,
        },
      }],
    }
  end

  def parse_backtrace_line(line)
    file, line_no, method = line.split(':')
    {
      filename: file,
      lineno: line_no.to_i,
      function: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
    }
  end

  def send_sentry_request(payload, dsn_uri)
    project_id = dsn_uri.path.split('/').last
    api_url = "#{dsn_uri.scheme}://#{dsn_uri.host}/api/#{project_id}/store/"

    uri = URI(api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['X-Sentry-Auth'] = build_sentry_auth_header(dsn_uri.user, dsn_uri.password)
    request.body = payload.to_json

    response = http.request(request)
    return if response.is_a?(Net::HTTPSuccess)

    warn("Sentry error tracking failed: #{response.code} #{response.message}")
  end

  def send_to_bugsnag(exception, context)
    require 'net/http'
    require 'uri'

    api_key = ENV.fetch('ERROR_TRACKING_DSN', nil)
    payload = build_bugsnag_payload(exception, context, api_key)
    send_bugsnag_request(payload)
  end

  def build_bugsnag_payload(exception, context, api_key)
    {
      apiKey: api_key,
      notifier: {
        name: 'Source License Logger',
        version: @version,
        url: 'https://github.com/source-license',
      },
      events: [build_bugsnag_event(exception, context)],
    }
  end

  def build_bugsnag_event(exception, context)
    {
      payloadVersion: '5',
      exceptions: [build_bugsnag_exception(exception)],
      context: context[:path] || 'source-license',
      severity: 'error',
      unhandled: false,
      app: { version: @version, releaseStage: @environment },
      device: { hostname: ENV['HOSTNAME'] || 'unknown' },
      metaData: { custom: context },
    }
  end

  def build_bugsnag_exception(exception)
    {
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
    }
  end

  def send_bugsnag_request(payload)
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
    payload = build_rollbar_payload(exception, context, access_token)
    send_rollbar_request(payload)
  end

  def build_rollbar_payload(exception, context, access_token)
    {
      access_token: access_token,
      data: {
        environment: @environment,
        level: 'error',
        timestamp: Time.now.to_i,
        platform: 'ruby',
        framework: 'sinatra',
        language: 'ruby',
        server: { host: ENV['HOSTNAME'] || 'unknown' },
        body: { trace: build_rollbar_trace(exception) },
        custom: context,
        notifier: { name: 'source-license-logger', version: @version },
      },
    }
  end

  def build_rollbar_trace(exception)
    {
      frames: (exception.backtrace || []).map do |line|
        file, line_no, method = line.split(':')
        {
          filename: file,
          lineno: line_no.to_i,
          method: method&.gsub(/.*`/, '')&.gsub(/'.*/, '') || 'unknown',
        }
      end,
      exception: { class: exception.class.name, message: exception.message },
    }
  end

  def send_rollbar_request(payload)
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

    dsn_match = ENV['ERROR_TRACKING_DSN'].match(%r{https://([^@]+)@(\d+)\.airbrake\.io})
    return unless dsn_match

    project_key = dsn_match[1]
    project_id = dsn_match[2]
    payload = build_airbrake_payload(exception, context)
    send_airbrake_request(payload, project_key, project_id)
  end

  def build_airbrake_payload(exception, context)
    {
      notifier: {
        name: 'source-license-logger',
        version: @version,
        url: 'https://github.com/source-license',
      },
      errors: [build_airbrake_error(exception)],
      context: {
        version: @version,
        environment: @environment,
        hostname: ENV['HOSTNAME'] || 'unknown',
      }.merge(context),
    }
  end

  def build_airbrake_error(exception)
    {
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
    }
  end

  def send_airbrake_request(payload, project_key, project_id)
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
    payload = build_honeybadger_payload(exception, context)
    send_honeybadger_request(payload, api_key)
  end

  def build_honeybadger_payload(exception, context)
    {
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
  end

  def send_honeybadger_request(payload, api_key)
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
    payload = build_webhook_payload(exception, context)
    send_webhook_request(uri, payload)
  end

  def build_webhook_payload(exception, context)
    {
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
  end

  def send_webhook_request(uri, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

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

# frozen_string_literal: true

# Source-License: Payment Event Logger
# Specialized logger for payment and webhook events

require 'json'
require 'fileutils'

class PaymentLogger
  class << self
    # Log payment-related events with structured data
    def log_payment_event(event_type, data = {})
      event = {
        timestamp: Time.now.iso8601,
        event_type: event_type,
        data: data,
        request_id: Thread.current[:request_id] || SecureRandom.hex(8),
        environment: ENV['APP_ENV'] || 'development',
      }

      # Log to both console and file
      log_to_console(event)
      log_to_file(event, 'payment')

      # Send to external monitoring if configured
      send_to_monitoring(event) if should_send_to_monitoring?(event_type)
    end

    # Log webhook events with enhanced details
    def log_webhook_event(provider, event_type, webhook_id, data = {})
      event = {
        timestamp: Time.now.iso8601,
        provider: provider,
        event_type: event_type,
        webhook_id: webhook_id,
        data: data,
        request_id: Thread.current[:request_id] || SecureRandom.hex(8),
        environment: ENV['APP_ENV'] || 'development',
      }

      log_to_console(event)
      log_to_file(event, 'webhook')

      # Always send critical webhook events to monitoring
      send_to_monitoring(event) if critical_webhook_event?(event_type)
    end

    # Log license lifecycle events
    def log_license_event(license, event_type, data = {})
      event = {
        timestamp: Time.now.iso8601,
        license_id: license&.id,
        license_key: license&.license_key,
        customer_email: license&.customer_email,
        event_type: event_type,
        data: data,
        request_id: Thread.current[:request_id] || SecureRandom.hex(8),
        environment: ENV['APP_ENV'] || 'development',
      }

      log_to_console(event)
      log_to_file(event, 'license')
    end

    # Log security events (failed payments, suspicious activity)
    def log_security_event(event_type, details = {})
      event = {
        timestamp: Time.now.iso8601,
        event_type: event_type,
        details: details,
        severity: determine_severity(event_type),
        request_id: Thread.current[:request_id] || SecureRandom.hex(8),
        environment: ENV['APP_ENV'] || 'development',
      }

      log_to_console(event)
      log_to_file(event, 'security')

      # Always send security events to monitoring
      send_to_monitoring(event)
    end

    # Get payment statistics for monitoring
    def get_payment_stats(hours_back = 24)
      return {} unless File.exist?(payment_log_path)

      cutoff_time = Time.now - (hours_back * 3600)
      stats = {
        total_payments: 0,
        successful_payments: 0,
        failed_payments: 0,
        webhooks_received: 0,
        webhooks_processed: 0,
        licenses_issued: 0,
        licenses_revoked: 0,
        security_events: 0,
      }

      # Read and parse log files
      [payment_log_path, webhook_log_path, license_log_path, security_log_path].each do |log_path|
        next unless File.exist?(log_path)

        File.readlines(log_path).each do |line|
          event = JSON.parse(line)
          event_time = Time.parse(event['timestamp'])
          next if event_time < cutoff_time

          case event['event_type']
          when 'payment_attempt'
            stats[:total_payments] += 1
          when 'payment_success'
            stats[:successful_payments] += 1
          when 'payment_failed'
            stats[:failed_payments] += 1
          when /webhook_received/
            stats[:webhooks_received] += 1
          when /webhook_processed/
            stats[:webhooks_processed] += 1
          when 'license_issued', 'license_renewed'
            stats[:licenses_issued] += 1
          when 'license_revoked'
            stats[:licenses_revoked] += 1
          when /security_/
            stats[:security_events] += 1
          end
        rescue JSON::ParserError, ArgumentError
          # Skip malformed log entries
          next
        end
      end

      stats
    end

    private

    def log_to_console(event)
      if ENV['LOG_FORMAT'] == 'json'
        puts event.to_json
      else
        timestamp = event[:timestamp]
        event_type = event[:event_type]
        provider = event[:provider]
        message = format_console_message(event)

        if provider
          puts "[#{timestamp}] #{provider.upcase}_#{event_type.upcase}: #{message}"
        else
          puts "[#{timestamp}] #{event_type.upcase}: #{message}"
        end
      end
    end

    def log_to_file(event, log_type)
      log_path = case log_type
                 when 'payment'
                   payment_log_path
                 when 'webhook'
                   webhook_log_path
                 when 'license'
                   license_log_path
                 when 'security'
                   security_log_path
                 else
                   general_log_path
                 end

      ensure_log_directory

      File.open(log_path, 'a') do |file|
        file.puts(event.to_json)
      end
    rescue StandardError => e
      puts "Failed to write to log file #{log_path}: #{e.message}"
    end

    def send_to_monitoring(event)
      webhook_url = ENV['SECURITY_WEBHOOK_URL'] || ENV.fetch('MONITORING_WEBHOOK_URL', nil)
      return unless webhook_url

      Thread.new do
        require 'net/http'
        require 'uri'

        uri = URI(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = 'Source-License-Monitor/1.0'
        request.body = {
          service: 'source-license',
          environment: ENV['APP_ENV'] || 'development',
          event: event,
        }.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          puts "Failed to send event to monitoring: #{response.code} #{response.message}"
        end
      rescue StandardError => e
        puts "Error sending event to monitoring: #{e.message}"
      end
    end

    def format_console_message(event)
      case event[:event_type]
      when 'payment_attempt'
        "Order #{event[:data][:order_id]} - Amount: $#{event[:data][:amount]}"
      when 'payment_success'
        "Payment successful - Transaction: #{event[:data][:transaction_id]}"
      when 'payment_failed'
        "Payment failed - Reason: #{event[:data][:error]}"
      when 'webhook_received'
        "Webhook received - ID: #{event[:webhook_id]}"
      when 'webhook_processed'
        'Webhook processed successfully'
      when 'license_issued'
        "License #{event[:license_key]} issued to #{event[:customer_email]}"
      when 'license_revoked'
        "License #{event[:license_key]} revoked - Reason: #{event[:data][:reason]}"
      else
        event[:data].to_s
      end
    end

    def should_send_to_monitoring?(event_type)
      critical_events = %w[
        payment_failed
        webhook_signature_invalid
        duplicate_payment_prevented
        refund_processed
        subscription_failed
      ]

      critical_events.include?(event_type)
    end

    def critical_webhook_event?(event_type)
      critical_types = %w[
        charge.failed
        payment.sale.denied
        subscription.cancelled
        invoice.payment_failed
      ]

      critical_types.any? { |type| event_type.include?(type) }
    end

    def determine_severity(event_type)
      case event_type
      when /failed/, /denied/, /invalid/, /suspicious/
        'high'
      when /warning/, /unusual/
        'medium'
      else
        'low'
      end
    end

    def ensure_log_directory
      log_dir = ENV['LOG_DIR'] || './logs'
      FileUtils.mkdir_p(log_dir)
    end

    def payment_log_path
      File.join(ENV['LOG_DIR'] || './logs', 'payments.log')
    end

    def webhook_log_path
      File.join(ENV['LOG_DIR'] || './logs', 'webhooks.log')
    end

    def license_log_path
      File.join(ENV['LOG_DIR'] || './logs', 'licenses.log')
    end

    def security_log_path
      File.join(ENV['LOG_DIR'] || './logs', 'security.log')
    end

    def general_log_path
      File.join(ENV['LOG_DIR'] || './logs', 'application.log')
    end
  end
end

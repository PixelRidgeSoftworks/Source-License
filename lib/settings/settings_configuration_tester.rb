# frozen_string_literal: true

# Source-License: Settings Configuration Testing
# Tests various configuration categories for validity and connectivity

require_relative 'settings_store'

class Settings::SettingsConfigurationTester
  class << self
    # Test configuration values
    def test_configuration(category = nil)
      results = {}

      categories = category ? [category] : SettingsSchema.categories

      categories.each do |cat|
        results[cat] = test_category_configuration(cat)
      end

      results
    end

    private

    def test_category_configuration(category)
      case category
      when 'email'
        test_email_configuration
      when 'payment'
        test_payment_configuration
      when 'monitoring'
        test_monitoring_configuration
      when 'database'
        test_database_configuration
      when 'performance'
        test_performance_configuration
      when 'security'
        test_security_configuration
      when 'application'
        test_application_configuration
      else
        { status: 'ok', message: 'No specific tests for this category' }
      end
    end

    def test_email_configuration
      host = SettingsStore.get('email.smtp.host')
      port = SettingsStore.get('email.smtp.port')

      return { status: 'disabled', message: 'SMTP not configured' } if host.empty?

      begin
        require 'net/smtp'

        smtp = Net::SMTP.new(host, port)
        smtp.enable_starttls if SettingsStore.get('email.smtp.tls')
        smtp.start(host, SettingsStore.get('email.smtp.username'), SettingsStore.get('email.smtp.password'), :auto)
        smtp.finish

        { status: 'ok', message: 'SMTP connection successful' }
      rescue StandardError => e
        { status: 'error', message: "SMTP connection failed: #{e.message}" }
      end
    end

    def test_payment_configuration
      stripe_key = SettingsStore.get('payment.stripe.secret_key')
      paypal_id = SettingsStore.get('payment.paypal.client_id')

      return { status: 'warning', message: 'No payment gateways configured' } if stripe_key.empty? && paypal_id.empty?

      results = []

      results << test_stripe_configuration unless stripe_key.empty?
      results << test_paypal_configuration unless paypal_id.empty?

      if results.any? { |r| r[:status] == 'error' }
        { status: 'error', message: 'Payment configuration errors detected' }
      elsif results.any? { |r| r[:status] == 'ok' }
        { status: 'ok', message: 'Payment gateways configured' }
      else
        { status: 'warning', message: 'Payment gateways configured but not tested' }
      end
    end

    def test_stripe_configuration
      # Basic Stripe key validation
      secret_key = SettingsStore.get('payment.stripe.secret_key')

      if secret_key.start_with?('sk_')
        { status: 'ok', message: 'Stripe key format valid' }
      else
        { status: 'error', message: 'Invalid Stripe secret key format' }
      end
    end

    def test_paypal_configuration
      # Basic PayPal configuration validation
      client_id = SettingsStore.get('payment.paypal.client_id')

      if client_id.length > 20
        { status: 'ok', message: 'PayPal client ID format valid' }
      else
        { status: 'error', message: 'Invalid PayPal client ID format' }
      end
    end

    def test_monitoring_configuration
      dsn = SettingsStore.get('monitoring.error_tracking_dsn')
      webhook = SettingsStore.get('monitoring.security_webhook_url')

      return { status: 'disabled', message: 'Monitoring not configured' } if dsn.empty? && webhook.empty?

      { status: 'ok', message: 'Monitoring services configured' }
    end

    def test_database_configuration
      DB.test_connection
      { status: 'ok', message: 'Database connection successful' }
    rescue StandardError => e
      { status: 'error', message: "Database connection failed: #{e.message}" }
    end

    def test_performance_configuration
      redis_url = SettingsStore.get('performance.redis_url')

      return { status: 'disabled', message: 'Redis not configured' } if redis_url.empty?

      begin
        # Basic Redis URL validation
        if redis_url.start_with?('redis://')
          { status: 'ok', message: 'Redis URL format valid' }
        else
          { status: 'warning', message: 'Redis URL format may be invalid' }
        end
      rescue StandardError => e
        { status: 'error', message: "Redis configuration error: #{e.message}" }
      end
    end

    def test_security_configuration
      issues = []

      # Check for strong secrets
      app_secret = SettingsStore.get('app.secret')
      jwt_secret = SettingsStore.get('security.jwt_secret')

      issues << 'APP_SECRET not configured' if app_secret.empty?
      issues << 'JWT_SECRET not configured' if jwt_secret.empty?
      issues << 'APP_SECRET too short' if app_secret.length < 32
      issues << 'JWT_SECRET too short' if jwt_secret.length < 32

      # Check SSL configuration
      issues << 'SSL not enforced' unless SettingsStore.get('security.force_ssl')

      if issues.any?
        { status: 'warning', message: "Security issues: #{issues.join(', ')}" }
      else
        { status: 'ok', message: 'Security configuration looks good' }
      end
    end

    def test_application_configuration
      issues = []

      # Check required application settings
      app_name = SettingsStore.get('app.name')
      support_email = SettingsStore.get('app.support_email')

      issues << 'Application name not configured' if app_name.empty?
      issues << 'Support email not configured' if support_email.empty?

      # Check if in production with development settings
      if SettingsStore.get('app.environment') == 'production'
        issues << 'Using default host in production' if SettingsStore.get('app.host') == 'localhost'
        issues << 'Using default port in production' if SettingsStore.get('app.port') == 4567
      end

      if issues.any?
        { status: 'warning', message: "Configuration issues: #{issues.join(', ')}" }
      else
        { status: 'ok', message: 'Application configuration looks good' }
      end
    end
  end
end

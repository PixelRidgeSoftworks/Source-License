# frozen_string_literal: true

# Source-License: Settings Management System
# Manages application configuration through database and environment variables

require 'yaml'
require 'json'

class SettingsManager
  # Define all configurable settings with their metadata
  SETTINGS_SCHEMA = {
    # Application Settings
    'app.name' => {
      type: 'string',
      default: 'Source License',
      category: 'application',
      description: 'Application name displayed throughout the interface',
      web_editable: true,
    },
    'app.description' => {
      type: 'text',
      default: 'Professional license management system',
      category: 'application',
      description: 'Application description for SEO and branding',
      web_editable: true,
    },
    'app.contact_email' => {
      type: 'email',
      default: 'admin@example.com',
      category: 'application',
      description: 'Contact email for customer support',
      web_editable: true,
    },
    'app.timezone' => {
      type: 'select',
      default: 'UTC',
      options: ['UTC', 'America/New_York', 'America/Los_Angeles', 'Europe/London', 'Asia/Tokyo'],
      category: 'application',
      description: 'Default timezone for the application',
      web_editable: true,
    },

    # Payment Settings
    'payment.stripe.publishable_key' => {
      type: 'string',
      default: '',
      category: 'payment',
      description: 'Stripe publishable key for payment processing',
      web_editable: true,
      sensitive: false,
    },
    'payment.stripe.secret_key' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'Stripe secret key for payment processing',
      web_editable: true,
      sensitive: true,
    },
    'payment.stripe.webhook_secret' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'Stripe webhook secret for security',
      web_editable: true,
      sensitive: true,
    },
    'payment.paypal.client_id' => {
      type: 'string',
      default: '',
      category: 'payment',
      description: 'PayPal client ID for payment processing',
      web_editable: true,
      sensitive: false,
    },
    'payment.paypal.client_secret' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'PayPal client secret for payment processing',
      web_editable: true,
      sensitive: true,
    },
    'payment.paypal.environment' => {
      type: 'select',
      default: 'sandbox',
      options: %w[sandbox production],
      category: 'payment',
      description: 'PayPal environment (sandbox for testing)',
      web_editable: true,
    },

    # Email Settings
    'email.smtp.host' => {
      type: 'string',
      default: '',
      category: 'email',
      description: 'SMTP server hostname',
      web_editable: true,
    },
    'email.smtp.port' => {
      type: 'number',
      default: 587,
      category: 'email',
      description: 'SMTP server port (587 for TLS, 465 for SSL)',
      web_editable: true,
    },
    'email.smtp.username' => {
      type: 'string',
      default: '',
      category: 'email',
      description: 'SMTP authentication username',
      web_editable: true,
    },
    'email.smtp.password' => {
      type: 'password',
      default: '',
      category: 'email',
      description: 'SMTP authentication password',
      web_editable: true,
      sensitive: true,
    },
    'email.smtp.tls' => {
      type: 'boolean',
      default: true,
      category: 'email',
      description: 'Enable TLS encryption for SMTP',
      web_editable: true,
    },
    'email.from_name' => {
      type: 'string',
      default: 'Source License',
      category: 'email',
      description: 'From name for outgoing emails',
      web_editable: true,
    },
    'email.from_address' => {
      type: 'email',
      default: '',
      category: 'email',
      description: 'From address for outgoing emails',
      web_editable: true,
    },

    # Security Settings
    'security.password_expiry_days' => {
      type: 'number',
      default: 90,
      category: 'security',
      description: 'Number of days before passwords expire',
      web_editable: true,
    },
    'security.max_login_attempts' => {
      type: 'number',
      default: 5,
      category: 'security',
      description: 'Maximum failed login attempts before lockout',
      web_editable: true,
    },
    'security.lockout_duration_minutes' => {
      type: 'number',
      default: 30,
      category: 'security',
      description: 'Account lockout duration in minutes',
      web_editable: true,
    },
    'security.session_timeout_hours' => {
      type: 'number',
      default: 8,
      category: 'security',
      description: 'Session timeout in hours',
      web_editable: true,
    },

    # License Settings
    'license.default_validity_days' => {
      type: 'number',
      default: 365,
      category: 'license',
      description: 'Default license validity period in days',
      web_editable: true,
    },
    'license.max_activations' => {
      type: 'number',
      default: 3,
      category: 'license',
      description: 'Default maximum activations per license',
      web_editable: true,
    },
    'license.allow_deactivation' => {
      type: 'boolean',
      default: true,
      category: 'license',
      description: 'Allow users to deactivate license on devices',
      web_editable: true,
    },

    # Monitoring Settings
    'monitoring.error_tracking_dsn' => {
      type: 'string',
      default: '',
      category: 'monitoring',
      description: 'Error tracking service DSN (Sentry, Bugsnag, etc.)',
      web_editable: true,
      sensitive: true,
    },
    'monitoring.security_webhook_url' => {
      type: 'url',
      default: '',
      category: 'monitoring',
      description: 'Webhook URL for security alerts (Slack, etc.)',
      web_editable: true,
      sensitive: true,
    },
    'monitoring.log_level' => {
      type: 'select',
      default: 'info',
      options: %w[debug info warn error fatal],
      category: 'monitoring',
      description: 'Application log level',
      web_editable: true,
    },
    'monitoring.log_format' => {
      type: 'select',
      default: 'text',
      options: %w[text json],
      category: 'monitoring',
      description: 'Log output format (JSON recommended for production)',
      web_editable: true,
    },

    # Database Settings (mostly read-only in web interface)
    'database.adapter' => {
      type: 'select',
      default: 'mysql',
      options: %w[mysql postgresql],
      category: 'database',
      description: 'Database adapter type',
      web_editable: false,
    },
    'database.host' => {
      type: 'string',
      default: 'localhost',
      category: 'database',
      description: 'Database server hostname',
      web_editable: false,
    },
    'database.port' => {
      type: 'number',
      default: 3306,
      category: 'database',
      description: 'Database server port',
      web_editable: false,
    },
    'database.name' => {
      type: 'string',
      default: 'source_license',
      category: 'database',
      description: 'Database name',
      web_editable: false,
    },
  }.freeze

  class << self
    # Get setting value (first check database, then environment, then default)
    def get(key)
      # Try database first
      if defined?(DB) && DB.table_exists?(:settings)
        setting = DB[:settings].where(key: key).first
        return parse_value(setting[:value], get_schema(key)[:type]) if setting
      end

      # Try environment variable
      env_key = key_to_env(key)
      env_value = ENV.fetch(env_key, nil)
      return parse_value(env_value, get_schema(key)[:type]) if env_value

      # Return default
      get_schema(key)[:default]
    end

    # Set setting value in database
    def set(key, value)
      return false unless valid_key?(key)

      schema = get_schema(key)
      return false unless validate_value(value, schema)

      ensure_settings_table

      # Convert value to string for storage
      stored_value = serialize_value(value, schema[:type])

      if DB[:settings].where(key: key).any?
        DB[:settings].where(key: key).update(
          value: stored_value,
          updated_at: Time.now
        )
      else
        DB[:settings].insert(
          key: key,
          value: stored_value,
          created_at: Time.now,
          updated_at: Time.now
        )
      end

      # Update environment variable if it exists
      env_key = key_to_env(key)
      ENV[env_key] = stored_value if ENV.key?(env_key)

      true
    end

    # Get all settings for a category
    def get_category(category)
      SETTINGS_SCHEMA.filter_map do |key, schema|
        next unless schema[:category] == category

        {
          key: key,
          value: get(key),
          schema: schema,
        }
      end
    end

    # Get all categories
    def get_categories
      SETTINGS_SCHEMA.values.map { |s| s[:category] }.uniq.sort
    end

    # Get web-editable settings
    def get_web_editable
      SETTINGS_SCHEMA.filter_map do |key, schema|
        next unless schema[:web_editable]

        {
          key: key,
          value: get(key),
          schema: schema,
        }
      end
    end

    # Export settings to YAML
    def export_to_yaml
      settings = {}
      SETTINGS_SCHEMA.each_key do |key|
        value = get(key)
        settings[key] = value unless value == get_schema(key)[:default]
      end
      settings.to_yaml
    end

    # Import settings from YAML
    def import_from_yaml(yaml_content)
      settings = YAML.safe_load(yaml_content)
      imported = 0

      settings.each do |key, value|
        imported += 1 if valid_key?(key) && set(key, value)
      end

      imported
    end

    # Generate .env file content
    def generate_env_file
      lines = ["# Generated .env file - #{Time.now}"]

      get_categories.each do |category|
        lines << ''
        lines << "# #{category.capitalize} Settings"

        get_category(category).each do |setting|
          env_key = key_to_env(setting[:key])
          value = setting[:value]

          # Skip empty values
          next if value.nil? || value == ''

          # Add description as comment
          lines << "# #{setting[:schema][:description]}"
          lines << "#{env_key}=#{value}"
        end
      end

      lines.join("\n")
    end

    # Test configuration values
    def test_configuration(category = nil)
      results = {}

      categories = category ? [category] : get_categories

      categories.each do |cat|
        results[cat] = test_category_configuration(cat)
      end

      results
    end

    private

    def get_schema(key)
      SETTINGS_SCHEMA[key] || { type: 'string', default: nil, category: 'unknown' }
    end

    def valid_key?(key)
      SETTINGS_SCHEMA.key?(key)
    end

    def key_to_env(key)
      # Convert dot notation to uppercase env var
      # e.g., "app.name" -> "APP_NAME"
      #       "payment.stripe.secret_key" -> "STRIPE_SECRET_KEY"

      case key
      when /^payment\.stripe\.(.+)/
        "STRIPE_#{::Regexp.last_match(1).upcase}"
      when /^payment\.paypal\.(.+)/
        "PAYPAL_#{::Regexp.last_match(1).upcase}"
      when /^email\.smtp\.(.+)/
        "SMTP_#{::Regexp.last_match(1).upcase}"
      when /^monitoring\.(.+)/
        case ::Regexp.last_match(1)
        when 'error_tracking_dsn'
          'ERROR_TRACKING_DSN'
        when 'security_webhook_url'
          'SECURITY_WEBHOOK_URL'
        when 'log_level'
          'LOG_LEVEL'
        when 'log_format'
          'LOG_FORMAT'
        else
          ::Regexp.last_match(1).upcase
        end
      when /^database\.(.+)/
        "DATABASE_#{::Regexp.last_match(1).upcase}"
      else
        key.tr('.', '_').upcase
      end
    end

    def parse_value(value, type)
      return nil if value.nil? || value == ''

      case type
      when 'boolean'
        %w[true 1 yes on].include?(value.to_s.downcase)
      when 'number'
        value.to_i
      when 'float'
        value.to_f
      else
        value.to_s
      end
    end

    def serialize_value(value, type)
      case type
      when 'boolean'
      when 'number', 'float'
      end
      value.to_s
    end

    def validate_value(value, schema)
      case schema[:type]
      when 'email'
        value.to_s.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      when 'url'
        value.to_s.match?(/\Ahttps?:\/\//)
      when 'number'
        value.to_s.match?(/\A\d+\z/)
      when 'select'
        schema[:options]&.include?(value.to_s)
      else
        true
      end
    end

    def ensure_settings_table
      return if DB.table_exists?(:settings)

      DB.create_table :settings do
        primary_key :id
        String :key, null: false, unique: true
        Text :value
        DateTime :created_at
        DateTime :updated_at
      end
    end

    def test_category_configuration(category)
      results = {}

      case category
      when 'email'
        results = test_email_configuration
      when 'payment'
        results = test_payment_configuration
      when 'monitoring'
        results = test_monitoring_configuration
      when 'database'
        results = test_database_configuration
      else
        results[:status] = 'ok'
        results[:message] = 'No specific tests for this category'
      end

      results
    end

    def test_email_configuration
      host = get('email.smtp.host')
      port = get('email.smtp.port')

      return { status: 'disabled', message: 'SMTP not configured' } if host.empty?

      begin
        require 'net/smtp'

        smtp = Net::SMTP.new(host, port)
        smtp.enable_starttls if get('email.smtp.tls')
        smtp.start(host, get('email.smtp.username'), get('email.smtp.password'), :auto)
        smtp.finish

        { status: 'ok', message: 'SMTP connection successful' }
      rescue StandardError => e
        { status: 'error', message: "SMTP connection failed: #{e.message}" }
      end
    end

    def test_payment_configuration
      stripe_key = get('payment.stripe.secret_key')
      paypal_id = get('payment.paypal.client_id')

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
      secret_key = get('payment.stripe.secret_key')

      if secret_key.start_with?('sk_')
        { status: 'ok', message: 'Stripe key format valid' }
      else
        { status: 'error', message: 'Invalid Stripe secret key format' }
      end
    end

    def test_paypal_configuration
      # Basic PayPal configuration validation
      client_id = get('payment.paypal.client_id')

      if client_id.length > 20
        { status: 'ok', message: 'PayPal client ID format valid' }
      else
        { status: 'error', message: 'Invalid PayPal client ID format' }
      end
    end

    def test_monitoring_configuration
      dsn = get('monitoring.error_tracking_dsn')
      webhook = get('monitoring.security_webhook_url')

      return { status: 'disabled', message: 'Monitoring not configured' } if dsn.empty? && webhook.empty?

      { status: 'ok', message: 'Monitoring services configured' }
    end

    def test_database_configuration
      DB.test_connection
      { status: 'ok', message: 'Database connection successful' }
    rescue StandardError => e
      { status: 'error', message: "Database connection failed: #{e.message}" }
    end
  end
end

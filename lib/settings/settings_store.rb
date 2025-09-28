# frozen_string_literal: true

# Source-License: Settings Storage and Retrieval
# Handles getting and setting values with database/environment fallback

require_relative 'settings_schema'
require_relative 'settings_validator'

class Settings::SettingsStore
  class << self
    # Get setting value (first check database, then environment, then default)
    def get(key)
      # Try database first
      if defined?(DB) && DB.table_exists?(:settings)
        setting = DB[:settings].where(key: key).first
        return parse_value(setting[:value], schema_for(key)[:type]) if setting
      end

      # Try environment variable
      env_key = key_to_env(key)
      env_value = ENV.fetch(env_key, nil)
      return parse_value(env_value, schema_for(key)[:type]) if env_value

      # Return default
      schema_for(key)[:default]
    end

    # Set setting value in database
    def update_setting(key, value)
      raise ArgumentError, "Invalid setting key: #{key}" unless Settings::SettingsSchema.valid_key?(key)

      schema = schema_for(key)
      unless Settings::SettingsValidator.valid_value?(value, schema)
        raise ArgumentError, "Invalid value for setting #{key}: #{value}"
      end

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

      # Return the stored value instead of boolean
      stored_value
    end

    # Get all settings for a category
    def get_category(category)
      Settings::SettingsSchema.get_category_settings(category).map do |setting|
        {
          key: setting[:key],
          value: get(setting[:key]),
          schema: setting[:schema],
        }
      end
    end

    private

    def schema_for(key)
      Settings::SettingsSchema.get_schema(key)
    end

    def key_to_env(key)
      # Convert dot notation to uppercase env var with specific mappings
      # e.g., "app.name" -> "APP_NAME"
      #       "payment.stripe.secret_key" -> "STRIPE_SECRET_KEY"

      direct_mapping_for(key) ||
        pattern_mapping_for(key) ||
        default_env_mapping(key)
    end

    def direct_mapping_for(key)
      direct_mappings[key]
    end

    def pattern_mapping_for(key)
      pattern_mappings.each do |pattern, handler|
        match = key.match(pattern)
        return handler.call(match) if match
      end
      nil
    end

    def default_env_mapping(key)
      key.tr('.', '_').upcase
    end

    def direct_mappings
      @direct_mappings ||= {
        # Application settings
        'app.name' => 'APP_NAME',
        'app.environment' => 'APP_ENV',
        'app.secret' => 'APP_SECRET',
        'app.host' => 'APP_HOST',
        'app.port' => 'PORT',
        'app.version' => 'APP_VERSION',
        'app.support_email' => 'SUPPORT_EMAIL',
        'app.organization_name' => 'ORGANIZATION_NAME',
        'app.organization_url' => 'ORGANIZATION_URL',

        # Security settings
        'security.jwt_secret' => 'JWT_SECRET',
        'security.allowed_hosts' => 'ALLOWED_HOSTS',
        'security.allowed_origins' => 'ALLOWED_ORIGINS',
        'security.force_ssl' => 'FORCE_SSL',
        'security.hsts_max_age' => 'HSTS_MAX_AGE',
        'security.session_timeout' => 'SESSION_TIMEOUT',
        'security.session_rotation_interval' => 'SESSION_ROTATION_INTERVAL',
        'security.behind_load_balancer' => 'BEHIND_LOAD_BALANCER',

        # License settings
        'license.default_validity_days' => 'LICENSE_VALIDITY_DAYS',
        'license.max_activations' => 'MAX_ACTIVATIONS_PER_LICENSE',

        # Performance settings
        'performance.redis_url' => 'REDIS_URL',
        'performance.enable_caching' => 'ENABLE_CACHING',
        'performance.cache_ttl' => 'CACHE_TTL',
        'performance.db_pool_size' => 'DB_POOL_SIZE',
        'performance.db_timeout' => 'DB_TIMEOUT',
        'performance.rate_limit_requests_per_hour' => 'RATE_LIMIT_REQUESTS_PER_HOUR',
        'performance.rate_limit_admin_requests_per_hour' => 'RATE_LIMIT_ADMIN_REQUESTS_PER_HOUR',

        # Admin settings
        'admin.initial_email' => 'INITIAL_ADMIN_EMAIL',
        'admin.initial_password' => 'INITIAL_ADMIN_PASSWORD',

        # Storage settings
        'storage.downloads_path' => 'DOWNLOADS_PATH',
        'storage.licenses_path' => 'LICENSES_PATH',

        # Social media settings
        'social.enable_social_links' => 'ENABLE_SOCIAL_LINKS',
        'social.enable_github' => 'ENABLE_GITHUB',
        'social.github_url' => 'SOCIAL_GITHUB_URL',
        'social.enable_twitter' => 'ENABLE_TWITTER',
        'social.twitter_url' => 'SOCIAL_TWITTER_URL',
        'social.enable_linkedin' => 'ENABLE_LINKEDIN',
        'social.linkedin_url' => 'SOCIAL_LINKEDIN_URL',
        'social.enable_facebook' => 'ENABLE_FACEBOOK',
        'social.facebook_url' => 'SOCIAL_FACEBOOK_URL',
        'social.enable_youtube' => 'ENABLE_YOUTUBE',
        'social.youtube_url' => 'SOCIAL_YOUTUBE_URL',
        'social.enable_discord' => 'ENABLE_DISCORD',
        'social.discord_url' => 'SOCIAL_DISCORD_URL',
      }.freeze
    end

    def pattern_mappings
      @pattern_mappings ||= [
        # Payment settings
        [/^payment\.stripe\.(.+)/, ->(match) { "STRIPE_#{match[1].upcase}" }],
        [/^payment\.paypal\.(.+)/, ->(match) { "PAYPAL_#{match[1].upcase}" }],

        # Email settings
        [/^email\.smtp\.(.+)/, ->(match) { "SMTP_#{match[1].upcase}" }],

        # Database settings
        [/^database\.(.+)/, ->(match) { "DATABASE_#{match[1].upcase}" }],

        # Monitoring settings with special cases
        [/^monitoring\.(.+)/, method(:monitoring_env_mapping)],

        # Webhook settings
        [/^webhooks\.(.+)/, method(:webhook_env_mapping)],
      ].freeze
    end

    def monitoring_env_mapping(match)
      setting_name = match[1]

      monitoring_special_mappings = {
        'error_tracking_dsn' => 'ERROR_TRACKING_DSN',
        'security_webhook_url' => 'SECURITY_WEBHOOK_URL',
        'log_level' => 'LOG_LEVEL',
        'log_format' => 'LOG_FORMAT',
      }.freeze

      monitoring_special_mappings[setting_name] || setting_name.upcase
    end

    def webhook_env_mapping(match)
      setting_path = match[1]

      # Handle nested webhook settings
      webhook_special_mappings = {
        'enabled' => 'WEBHOOKS_ENABLED',
        'base_url' => 'WEBHOOKS_BASE_URL',
        'security_token' => 'WEBHOOK_SECURITY_TOKEN',
        'retry_attempts' => 'WEBHOOK_RETRY_ATTEMPTS',
        'timeout_seconds' => 'WEBHOOK_TIMEOUT_SECONDS',
        'stripe.charge_succeeded' => 'STRIPE_WEBHOOK_CHARGE_SUCCEEDED',
        'stripe.charge_failed' => 'STRIPE_WEBHOOK_CHARGE_FAILED',
        'stripe.charge_refunded' => 'STRIPE_WEBHOOK_CHARGE_REFUNDED',
        'stripe.customer_subscription_created' => 'STRIPE_WEBHOOK_SUBSCRIPTION_CREATED',
        'stripe.customer_subscription_deleted' => 'STRIPE_WEBHOOK_SUBSCRIPTION_DELETED',
        'stripe.customer_subscription_paused' => 'STRIPE_WEBHOOK_SUBSCRIPTION_PAUSED',
        'stripe.customer_subscription_resumed' => 'STRIPE_WEBHOOK_SUBSCRIPTION_RESUMED',
        'stripe.customer_subscription_updated' => 'STRIPE_WEBHOOK_SUBSCRIPTION_UPDATED',
        'stripe.customer_subscription_trial_will_end' => 'STRIPE_WEBHOOK_TRIAL_WILL_END',
        'paypal.enabled' => 'PAYPAL_WEBHOOK_ENABLED',
        'paypal.webhook_id' => 'PAYPAL_WEBHOOK_ID',
        'notifications.enabled' => 'WEBHOOK_NOTIFICATIONS_ENABLED',
        'notifications.email' => 'WEBHOOK_NOTIFICATIONS_EMAIL',
        'notifications.slack_webhook_url' => 'WEBHOOK_SLACK_URL',
        'logging.enabled' => 'WEBHOOK_LOGGING_ENABLED',
        'logging.log_level' => 'WEBHOOK_LOG_LEVEL',
        'logging.retain_days' => 'WEBHOOK_LOG_RETAIN_DAYS',
      }.freeze

      webhook_special_mappings[setting_path] || "WEBHOOK_#{setting_path.tr('.', '_').upcase}"
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
        value ? 'true' : 'false'
      else
        value.to_s
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
  end
end

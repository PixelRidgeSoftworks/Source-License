# frozen_string_literal: true

# Source-License: Settings Environment Variable Mapping
# Maps setting keys to environment variable names

class Settings::SettingsEnvMapper
  class << self
    def key_to_env(key)
      # Convert dot notation to uppercase env var with specific mappings
      # e.g., "app.name" -> "APP_NAME"
      #       "payment.stripe.secret_key" -> "STRIPE_SECRET_KEY"

      APPLICATION_MAPPINGS[key] ||
        PAYMENT_MAPPINGS[key] ||
        EMAIL_MAPPINGS[key] ||
        SECURITY_MAPPINGS[key] ||
        LICENSE_MAPPINGS[key] ||
        MONITORING_MAPPINGS[key] ||
        PERFORMANCE_MAPPINGS[key] ||
        DATABASE_MAPPINGS[key] ||
        ADMIN_MAPPINGS[key] ||
        STORAGE_MAPPINGS[key] ||
        SOCIAL_MAPPINGS[key] ||
        default_mapping(key)
    end

    APPLICATION_MAPPINGS = {
      'app.name' => 'APP_NAME',
      'app.environment' => 'APP_ENV',
      'app.secret' => 'APP_SECRET',
      'app.host' => 'APP_HOST',
      'app.port' => 'PORT',
      'app.version' => 'APP_VERSION',
      'app.support_email' => 'SUPPORT_EMAIL',
      'app.organization_name' => 'ORGANIZATION_NAME',
      'app.organization_url' => 'ORGANIZATION_URL',
    }.freeze

    PAYMENT_MAPPINGS = {
      /^payment\.stripe\.(.+)/ => 'STRIPE_',
      /^payment\.paypal\.(.+)/ => 'PAYPAL_',
    }.freeze

    EMAIL_MAPPINGS = {
      /^email\.smtp\.(.+)/ => 'SMTP_',
    }.freeze

    SECURITY_MAPPINGS = {
      'security.jwt_secret' => 'JWT_SECRET',
      'security.allowed_hosts' => 'ALLOWED_HOSTS',
      'security.allowed_origins' => 'ALLOWED_ORIGINS',
      'security.force_ssl' => 'FORCE_SSL',
      'security.hsts_max_age' => 'HSTS_MAX_AGE',
      'security.session_timeout' => 'SESSION_TIMEOUT',
      'security.session_rotation_interval' => 'SESSION_ROTATION_INTERVAL',
      'security.behind_load_balancer' => 'BEHIND_LOAD_BALANCER',
    }.freeze

    LICENSE_MAPPINGS = {
      'license.default_validity_days' => 'LICENSE_VALIDITY_DAYS',
      'license.max_activations' => 'MAX_ACTIVATIONS_PER_LICENSE',
    }.freeze

    MONITORING_MAPPINGS = {
      'monitoring.error_tracking_dsn' => 'ERROR_TRACKING_DSN',
      'monitoring.security_webhook_url' => 'SECURITY_WEBHOOK_URL',
      'monitoring.log_level' => 'LOG_LEVEL',
      'monitoring.log_format' => 'LOG_FORMAT',
    }.freeze

    PERFORMANCE_MAPPINGS = {
      'performance.redis_url' => 'REDIS_URL',
      'performance.enable_caching' => 'ENABLE_CACHING',
      'performance.cache_ttl' => 'CACHE_TTL',
      'performance.db_pool_size' => 'DB_POOL_SIZE',
      'performance.db_timeout' => 'DB_TIMEOUT',
      'performance.rate_limit_requests_per_hour' => 'RATE_LIMIT_REQUESTS_PER_HOUR',
      'performance.rate_limit_admin_requests_per_hour' => 'RATE_LIMIT_ADMIN_REQUESTS_PER_HOUR',
    }.freeze

    DATABASE_MAPPINGS = {
      /^database\.(.+)/ => 'DATABASE_',
    }.freeze

    ADMIN_MAPPINGS = {
      'admin.initial_email' => 'INITIAL_ADMIN_EMAIL',
      'admin.initial_password' => 'INITIAL_ADMIN_PASSWORD',
    }.freeze

    STORAGE_MAPPINGS = {
      'storage.downloads_path' => 'DOWNLOADS_PATH',
      'storage.licenses_path' => 'LICENSES_PATH',
    }.freeze

    SOCIAL_MAPPINGS = {
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

    private

    def default_mapping(key)
      # Check regex mappings first
      [PAYMENT_MAPPINGS, EMAIL_MAPPINGS, DATABASE_MAPPINGS].each do |mappings|
        mappings.each do |pattern, prefix|
          match = key.match(pattern)
          return "#{prefix}#{match[1].upcase}" if match
        end
      end

      # Default fallback
      key.tr('.', '_').upcase
    end
  end
end

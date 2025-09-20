# frozen_string_literal: true

# Source-License: Settings Schema Definition
# Defines all configurable settings with their metadata

# Define all configurable settings with their metadata
SETTINGS_SCHEMA = {
  # Application Settings
  'app.name' => {
    type: 'string',
    default: 'Source-License',
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
  'app.support_email' => {
    type: 'email',
    default: 'support@yourdomain.com',
    category: 'application',
    description: 'Support email for customer inquiries',
    web_editable: true,
  },
  'app.organization_name' => {
    type: 'string',
    default: 'Your Organization',
    category: 'application',
    description: 'Organization name for branding and legal purposes',
    web_editable: true,
  },
  'app.organization_url' => {
    type: 'url',
    default: 'https://yourdomain.com',
    category: 'application',
    description: 'Organization website URL',
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
  'app.environment' => {
    type: 'select',
    default: 'development',
    options: %w[development production test],
    category: 'application',
    description: 'Application environment mode',
    web_editable: false,
  },
  'app.version' => {
    type: 'string',
    default: '1.0.0',
    category: 'application',
    description: 'Application version number',
    web_editable: true,
  },
  'app.secret' => {
    type: 'password',
    default: '',
    category: 'application',
    description: 'Application secret key for sessions and encryption',
    web_editable: false,
    sensitive: true,
  },
  'app.host' => {
    type: 'string',
    default: 'localhost',
    category: 'application',
    description: 'Application host/domain name',
    web_editable: true,
  },
  'app.port' => {
    type: 'number',
    default: 4567,
    category: 'application',
    description: 'Application port number',
    web_editable: true,
  },

  # Social Media Settings
  'social.enable_social_links' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Enable social media links in footer',
    web_editable: true,
  },
  'social.enable_github' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show GitHub link in footer',
    web_editable: true,
  },
  'social.github_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'GitHub profile or organization URL',
    web_editable: true,
  },
  'social.enable_twitter' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show Twitter/X link in footer',
    web_editable: true,
  },
  'social.twitter_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'Twitter/X profile URL',
    web_editable: true,
  },
  'social.enable_linkedin' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show LinkedIn link in footer',
    web_editable: true,
  },
  'social.linkedin_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'LinkedIn profile or company page URL',
    web_editable: true,
  },
  'social.enable_facebook' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show Facebook link in footer',
    web_editable: true,
  },
  'social.facebook_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'Facebook page URL',
    web_editable: true,
  },
  'social.enable_youtube' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show YouTube link in footer',
    web_editable: true,
  },
  'social.youtube_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'YouTube channel URL',
    web_editable: true,
  },
  'social.enable_discord' => {
    type: 'boolean',
    default: false,
    category: 'social',
    description: 'Show Discord link in footer',
    web_editable: true,
  },
  'social.discord_url' => {
    type: 'url',
    default: '',
    category: 'social',
    description: 'Discord server invite URL',
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
  'security.jwt_secret' => {
    type: 'password',
    default: '',
    category: 'security',
    description: 'JWT secret key for token signing',
    web_editable: false,
    sensitive: true,
  },
  'security.allowed_hosts' => {
    type: 'text',
    default: 'localhost,127.0.0.1,yourdomain.com,www.yourdomain.com',
    category: 'security',
    description: 'Comma-separated list of allowed hostnames',
    web_editable: true,
  },
  'security.allowed_origins' => {
    type: 'text',
    default: 'https://yourdomain.com,https://www.yourdomain.com',
    category: 'security',
    description: 'Comma-separated list of allowed CORS origins',
    web_editable: true,
  },
  'security.force_ssl' => {
    type: 'boolean',
    default: true,
    category: 'security',
    description: 'Force HTTPS/SSL connections',
    web_editable: true,
  },
  'security.hsts_max_age' => {
    type: 'number',
    default: 31_536_000,
    category: 'security',
    description: 'HTTP Strict Transport Security max age in seconds',
    web_editable: true,
  },
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
  'security.session_timeout' => {
    type: 'number',
    default: 28_800,
    category: 'security',
    description: 'Session timeout in seconds',
    web_editable: true,
  },
  'security.session_rotation_interval' => {
    type: 'number',
    default: 7200,
    category: 'security',
    description: 'Session rotation interval in seconds',
    web_editable: true,
  },
  'security.behind_load_balancer' => {
    type: 'boolean',
    default: false,
    category: 'security',
    description: 'Application is behind a load balancer',
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

  # Tax Settings
  'tax.enable_taxes' => {
    type: 'boolean',
    default: false,
    category: 'tax',
    description: 'Enable tax calculation for orders',
    web_editable: true,
  },
  'tax.auto_apply_taxes' => {
    type: 'boolean',
    default: true,
    category: 'tax',
    description: 'Automatically apply active taxes to all orders',
    web_editable: true,
  },
  'tax.display_tax_breakdown' => {
    type: 'boolean',
    default: true,
    category: 'tax',
    description: 'Show detailed tax breakdown to customers',
    web_editable: true,
  },
  'tax.include_tax_in_price' => {
    type: 'boolean',
    default: false,
    category: 'tax',
    description: 'Include tax in displayed prices (tax-inclusive pricing)',
    web_editable: true,
  },
  'tax.default_tax_name' => {
    type: 'string',
    default: 'Sales Tax',
    category: 'tax',
    description: 'Default name for new taxes',
    web_editable: true,
  },
  'tax.default_tax_rate' => {
    type: 'number',
    default: 0.0,
    category: 'tax',
    description: 'Default tax rate percentage for new taxes',
    web_editable: true,
  },
  'tax.round_tax_amounts' => {
    type: 'boolean',
    default: true,
    category: 'tax',
    description: 'Round tax amounts to nearest cent',
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

  # Performance & Caching Settings
  'performance.redis_url' => {
    type: 'string',
    default: 'redis://localhost:6379/0',
    category: 'performance',
    description: 'Redis server URL for caching',
    web_editable: true,
  },
  'performance.enable_caching' => {
    type: 'boolean',
    default: true,
    category: 'performance',
    description: 'Enable application caching',
    web_editable: true,
  },
  'performance.cache_ttl' => {
    type: 'number',
    default: 3600,
    category: 'performance',
    description: 'Cache time-to-live in seconds',
    web_editable: true,
  },
  'performance.db_pool_size' => {
    type: 'number',
    default: 10,
    category: 'performance',
    description: 'Database connection pool size',
    web_editable: true,
  },
  'performance.db_timeout' => {
    type: 'number',
    default: 5000,
    category: 'performance',
    description: 'Database connection timeout in milliseconds',
    web_editable: true,
  },
  'performance.rate_limit_requests_per_hour' => {
    type: 'number',
    default: 1000,
    category: 'performance',
    description: 'Rate limit for general requests per hour',
    web_editable: true,
  },
  'performance.rate_limit_admin_requests_per_hour' => {
    type: 'number',
    default: 100,
    category: 'performance',
    description: 'Rate limit for admin requests per hour',
    web_editable: true,
  },

  # Database Settings (mostly read-only in web interface)
  'database.adapter' => {
    type: 'select',
    default: 'mysql',
    options: %w[mysql postgresql sqlite],
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
  'database.user' => {
    type: 'string',
    default: '',
    category: 'database',
    description: 'Database username',
    web_editable: false,
    sensitive: false,
  },
  'database.password' => {
    type: 'password',
    default: '',
    category: 'database',
    description: 'Database password',
    web_editable: false,
    sensitive: true,
  },

  # Admin Setup Settings
  'admin.initial_email' => {
    type: 'email',
    default: 'admin@yourdomain.com',
    category: 'admin',
    description: 'Initial admin account email (used during installation)',
    web_editable: false,
    sensitive: false,
  },
  'admin.initial_password' => {
    type: 'password',
    default: '',
    category: 'admin',
    description: 'Initial admin account password (remove after first login)',
    web_editable: false,
    sensitive: true,
  },

  # File Storage Settings
  'storage.downloads_path' => {
    type: 'string',
    default: './downloads',
    category: 'storage',
    description: 'Path for downloadable files',
    web_editable: true,
  },
  'storage.licenses_path' => {
    type: 'string',
    default: './licenses',
    category: 'storage',
    description: 'Path for license files',
    web_editable: true,
  },
}.freeze

module Settings
end

class Settings::SettingsSchema

  class << self
    def get_schema(key)
      SETTINGS_SCHEMA[key] || { type: 'string', default: nil, category: 'unknown' }
    end

    def valid_key?(key)
      SETTINGS_SCHEMA.key?(key)
    end

    def categories
      SETTINGS_SCHEMA.values.map { |s| s[:category] }.uniq.sort
    end

    def get_category_settings(category)
      SETTINGS_SCHEMA.filter_map do |key, schema|
        next unless schema[:category] == category

        { key: key, schema: schema }
      end
    end

    def web_editable_settings
      SETTINGS_SCHEMA.filter_map do |key, schema|
        next unless schema[:web_editable]

        { key: key, schema: schema }
      end
    end

    def all_settings
      SETTINGS_SCHEMA
    end
  end
end

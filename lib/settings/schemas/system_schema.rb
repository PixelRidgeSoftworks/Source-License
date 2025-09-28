# frozen_string_literal: true

# Source-License: System Settings Schema
# Defines system-related settings (license, tax, monitoring, performance, database, admin, storage)

class Settings::Schemas::SystemSchema
  SYSTEM_SETTINGS = {
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

  class << self
    def settings
      SYSTEM_SETTINGS
    end
  end
end

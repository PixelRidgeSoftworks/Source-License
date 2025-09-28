# frozen_string_literal: true

# Source-License: Security Settings Schema
# Defines security configuration settings with their metadata

class Settings::Schemas::SecuritySchema
  SECURITY_SETTINGS = {
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
  }.freeze

  class << self
    def settings
      SECURITY_SETTINGS
    end
  end
end

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

    # Two-Factor Authentication Settings
    'security.2fa.enforce_all_users' => {
      type: 'boolean',
      default: false,
      category: 'security',
      description: 'Require 2FA for all users',
      web_editable: true,
    },
    'security.2fa.enforce_new_users' => {
      type: 'boolean',
      default: false,
      category: 'security',
      description: 'Require 2FA for new user registrations',
      web_editable: true,
    },
    'security.2fa.enforce_admins' => {
      type: 'boolean',
      default: false,
      category: 'security',
      description: 'Require 2FA for all administrators',
      web_editable: true,
    },
    'security.2fa.grace_period_days' => {
      type: 'number',
      default: 7,
      category: 'security',
      description: 'Days users have to set up 2FA after it becomes required',
      web_editable: true,
    },
    'security.2fa.allow_totp' => {
      type: 'boolean',
      default: true,
      category: 'security',
      description: 'Allow TOTP (Authenticator Apps) as 2FA method',
      web_editable: true,
    },
    'security.2fa.allow_webauthn' => {
      type: 'boolean',
      default: true,
      category: 'security',
      description: 'Allow WebAuthn (Security Keys & Biometrics) as 2FA method',
      web_editable: true,
    },
    'security.2fa.allow_backup_codes' => {
      type: 'boolean',
      default: true,
      category: 'security',
      description: 'Allow backup codes for 2FA recovery',
      web_editable: true,
    },
    'security.2fa.backup_code_count' => {
      type: 'select',
      default: 10,
      options: [8, 10, 12, 16],
      category: 'security',
      description: 'Number of backup codes to generate',
      web_editable: true,
    },
    'security.2fa.totp_issuer' => {
      type: 'string',
      default: 'Source-License',
      category: 'security',
      description: 'TOTP issuer name displayed in authenticator apps',
      web_editable: true,
    },

    # WebAuthn Configuration
    'security.webauthn.origin' => {
      type: 'url',
      default: 'https://localhost:4567',
      category: 'security',
      description: 'WebAuthn origin URL for authentication',
      web_editable: true,
    },
    'security.webauthn.rp_name' => {
      type: 'string',
      default: 'Source-License',
      category: 'security',
      description: 'WebAuthn Relying Party name',
      web_editable: true,
    },
    'security.webauthn.rp_id' => {
      type: 'string',
      default: 'localhost',
      category: 'security',
      description: 'WebAuthn Relying Party ID (domain)',
      web_editable: true,
    },
    'security.webauthn.timeout' => {
      type: 'number',
      default: 60,
      category: 'security',
      description: 'WebAuthn authentication timeout in seconds',
      web_editable: true,
    },
    'security.webauthn.user_verification' => {
      type: 'select',
      default: 'preferred',
      options: %w[required preferred discouraged],
      category: 'security',
      description: 'WebAuthn user verification requirement',
      web_editable: true,
    },
    'security.webauthn.attestation' => {
      type: 'select',
      default: 'none',
      options: %w[none indirect direct enterprise],
      category: 'security',
      description: 'WebAuthn attestation preference',
      web_editable: true,
    },
  }.freeze

  class << self
    def settings
      SECURITY_SETTINGS
    end
  end
end

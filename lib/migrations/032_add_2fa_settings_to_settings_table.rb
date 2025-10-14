# frozen_string_literal: true

# Source-License: Migration 32 - Add 2FA Settings to Settings Table
# Populates the settings table with default 2FA configuration values

class Migrations::Add2faSettingsToSettingsTable < Migrations::BaseMigration
  VERSION = 32

  def up
    # Two-Factor Authentication Settings
    default_2fa_settings = {
      'security.2fa.enforce_all_users' => 'false',
      'security.2fa.enforce_new_users' => 'false',
      'security.2fa.enforce_admins' => 'false',
      'security.2fa.grace_period_days' => '7',
      'security.2fa.allow_totp' => 'true',
      'security.2fa.allow_webauthn' => 'true',
      'security.2fa.allow_backup_codes' => 'true',
      'security.2fa.backup_code_count' => '10',
      'security.2fa.totp_issuer' => 'Source-License',

      # WebAuthn Configuration
      'security.webauthn.rp_name' => 'Source-License',
      'security.webauthn.timeout' => '60',
      'security.webauthn.user_verification' => 'preferred',
      'security.webauthn.attestation' => 'none',
    }

    # Insert default settings only if they don't already exist
    default_2fa_settings.each do |key, value|
      next if DB[:settings].where(key: key).any?

      DB[:settings].insert(
        key: key,
        value: value,
        created_at: Time.now,
        updated_at: Time.now
      )
    end

    puts "Added #{default_2fa_settings.count} 2FA settings to settings table"
  end

  def down
    # Remove all 2FA settings
    setting_keys_2fa = [
      'security.2fa.enforce_all_users',
      'security.2fa.enforce_new_users',
      'security.2fa.enforce_admins',
      'security.2fa.grace_period_days',
      'security.2fa.allow_totp',
      'security.2fa.allow_webauthn',
      'security.2fa.allow_backup_codes',
      'security.2fa.backup_code_count',
      'security.2fa.totp_issuer',
      'security.webauthn.rp_name',
      'security.webauthn.timeout',
      'security.webauthn.user_verification',
      'security.webauthn.attestation',
    ]

    deleted_count = DB[:settings].where(key: setting_keys_2fa).delete
    puts "Removed #{deleted_count} 2FA settings from settings table"
  end
end

# frozen_string_literal: true

# Source-License: Migration 33 - Add Expanded Settings to Settings Table
# Populates the settings table with additional configuration values from updated schemas

class Migrations::AddExpandedSettingsToSettingsTable < Migrations::BaseMigration
  VERSION = 33

  def up
    # Define all new settings to add
    default_expanded_settings = {
      # Application Settings
      'app.skip_update_check' => 'false',

      # Secure Licensing System Settings
      'license.hash_salt' => '',
      'license.jwt_secret' => '',
      'license.bcrypt_cost' => '12',
      'license.audit_logging' => 'true',
      'license.max_rate_limit_failures' => '10',
      'license.rate_limit_window' => '1',
      'license.validation_rate_limit' => '30',
      'license.activation_rate_limit' => '10',

      # WebAuthn Configuration (additional settings)
      'security.webauthn.origin' => 'https://localhost:4567',
      'security.webauthn.rp_id' => 'localhost',

      # PayPal Payment Settings
      'payment.paypal.webhook_id' => '',
    }

    # Insert default settings only if they don't already exist
    default_expanded_settings.each do |key, value|
      next if DB[:settings].where(key: key).any?

      DB[:settings].insert(
        key: key,
        value: value,
        created_at: Time.now,
        updated_at: Time.now
      )
    end

    puts "Added #{default_expanded_settings.count} expanded settings to settings table"
  end

  def down
    # Remove all expanded settings
    setting_keys_expanded = [
      'app.skip_update_check',
      'license.hash_salt',
      'license.jwt_secret',
      'license.bcrypt_cost',
      'license.audit_logging',
      'license.max_rate_limit_failures',
      'license.rate_limit_window',
      'license.validation_rate_limit',
      'license.activation_rate_limit',
      'security.webauthn.origin',
      'security.webauthn.rp_id',
      'payment.paypal.webhook_id',
    ]

    deleted_count = DB[:settings].where(key: setting_keys_expanded).delete
    puts "Removed #{deleted_count} expanded settings from settings table"
  end
end

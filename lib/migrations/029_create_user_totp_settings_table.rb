# frozen_string_literal: true

# Source-License: Migration 29 - Create User TOTP Settings Table
# Creates the user_totp_settings table for TOTP (Google Authenticator, etc.) support

class Migrations::CreateUserTotpSettingsTable < Migrations::BaseMigration
  VERSION = 29

  def up
    puts 'Creating user_totp_settings table for TOTP authentication...'

    DB.create_table :user_totp_settings do
      primary_key :id
      foreign_key :user_id, :users, null: false, on_delete: :cascade, unique: true
      String :secret, null: false, size: 32 # Base32 encoded secret
      String :backup_codes, null: true, size: 1000 # JSON array of backup codes
      Boolean :enabled, default: false # Whether TOTP is enabled for this user
      DateTime :enabled_at, null: true # When TOTP was first enabled
      DateTime :last_used_at, null: true # Last successful TOTP verification
      Integer :backup_codes_used, default: 0 # Count of backup codes used
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Indexes for performance
      index :user_id
      index :enabled
      index :enabled_at
      index :last_used_at
    end

    puts '✓ Created user_totp_settings table'
  end

  def down
    puts 'Dropping user_totp_settings table...'
    DB.drop_table :user_totp_settings
    puts '✓ Dropped user_totp_settings table'
  end
end

# frozen_string_literal: true

# Source-License: Migration 31 - Add 2FA Fields to Users Table
# Adds fields to track 2FA status and preferences for users

class Migrations::Add2faFieldsToUsersTable < Migrations::BaseMigration
  VERSION = 31

  def up
    puts 'Adding 2FA fields to users table...'

    DB.alter_table :users do
      add_column :two_factor_enabled, :boolean, default: false
      add_column :two_factor_enabled_at, :datetime, null: true
      add_column :backup_codes_generated_at, :datetime, null: true
      add_column :require_2fa, :boolean, default: false # Admin can force 2FA
      add_column :preferred_2fa_method, :string, size: 20, null: true # 'totp' or 'webauthn'
      add_column :last_2fa_used_at, :datetime, null: true
    end

    # Add performance indexes
    add_index_if_not_exists :users, :two_factor_enabled
    add_index_if_not_exists :users, :require_2fa
    add_index_if_not_exists :users, :two_factor_enabled_at
    add_index_if_not_exists :users, :last_2fa_used_at

    puts '✓ Added 2FA fields to users table'
  end

  def down
    puts 'Removing 2FA fields from users table...'

    DB.alter_table :users do
      drop_column :two_factor_enabled
      drop_column :two_factor_enabled_at
      drop_column :backup_codes_generated_at
      drop_column :require_2fa
      drop_column :preferred_2fa_method
      drop_column :last_2fa_used_at
    end

    puts '✓ Removed 2FA fields from users table'
  end
end

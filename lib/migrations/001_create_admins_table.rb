# frozen_string_literal: true

# Source-License: Migration 1 - Create Admins Table
# Creates the admins table with authentication and security features

class Migrations::CreateAdminsTable < BaseMigration
  VERSION = 1

  def up
    DB.create_table :admins do
      primary_key :id
      String :email, null: false, unique: true, size: 255
      String :password_hash, null: false, size: 255
      String :status, default: 'active', size: 50
      String :roles, default: 'admin', size: 255

      # Authentication tracking
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_login_at
      String :last_login_ip, size: 45
      String :last_login_user_agent, size: 500
      Integer :login_count, default: 0

      # Password management
      DateTime :password_changed_at
      Boolean :must_change_password, default: false
      String :password_reset_token, size: 255
      DateTime :password_reset_sent_at

      # Two-factor authentication
      String :two_factor_secret, size: 255
      Boolean :two_factor_enabled, default: false
      DateTime :two_factor_enabled_at
      DateTime :two_factor_disabled_at

      # Account status tracking
      DateTime :activated_at
      DateTime :deactivated_at
      DateTime :locked_at
      DateTime :unlocked_at

      index :email
      index :status
      index :password_reset_token
      index :last_login_at
    end
  end
end

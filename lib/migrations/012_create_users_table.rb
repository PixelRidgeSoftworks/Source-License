# frozen_string_literal: true

# Source-License: Migration 12 - Create Users Table
# Creates the users table for customer accounts

class Migrations::CreateUsersTable < Migrations::BaseMigration
  VERSION = 12

  def up
    puts 'Creating users table for customer accounts...'

    DB.create_table :users do
      primary_key :id
      String :email, null: false, unique: true, size: 255
      String :name, size: 255
      String :password_hash, null: false, size: 255
      String :status, default: 'active', size: 50

      # Email verification
      Boolean :email_verified, default: false
      String :email_verification_token, size: 255
      DateTime :email_verification_sent_at
      DateTime :email_verified_at

      # Password management
      DateTime :password_changed_at
      String :password_reset_token, size: 255
      DateTime :password_reset_sent_at

      # Authentication tracking
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_login_at
      String :last_login_ip, size: 45
      String :last_login_user_agent, size: 500
      Integer :login_count, default: 0

      # Account status tracking
      DateTime :activated_at
      DateTime :deactivated_at
      DateTime :suspended_at

      index :email
      index :status
      index :email_verification_token
      index :password_reset_token
      index :last_login_at
    end

    puts '✓ Created users table'
  end
end

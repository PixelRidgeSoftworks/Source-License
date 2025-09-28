# frozen_string_literal: true

# Source-License: Migration 14 - Create Failed Login Attempts Table
# Creates the failed_login_attempts table for authentication security

class Migrations::CreateFailedLoginAttemptsTable < BaseMigration
  VERSION = 14

  def up
    puts 'Creating failed_login_attempts table for authentication security...'

    DB.create_table :failed_login_attempts do
      primary_key :id
      String :email, null: false, size: 255
      Integer :admin_id, null: true  # null if not an admin account
      String :ip_address, size: 45   # Support both IPv4 and IPv6
      String :user_agent, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Indexes for performance
      index :email
      index :created_at
      index %i[email created_at]
      index :ip_address
    end

    puts '✓ Created failed_login_attempts table'
  end
end

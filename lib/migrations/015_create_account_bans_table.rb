# frozen_string_literal: true

# Source-License: Migration 15 - Create Account Bans Table
# Creates the account_bans table for progressive ban system

class Migrations::CreateAccountBansTable < Migrations::BaseMigration
  VERSION = 15

  def up
    puts 'Creating account_bans table for progressive ban system...'

    DB.create_table :account_bans do
      primary_key :id
      String :email, null: false, size: 255
      Integer :admin_id, null: true   # null if not an admin account
      Integer :ban_count, null: false, default: 1
      DateTime :banned_until, null: false
      String :reason, default: 'multiple_failed_login_attempts', size: 255
      String :ip_address, size: 45    # Support both IPv4 and IPv6
      String :user_agent, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: true

      # Indexes for performance
      index :email
      index :banned_until
      index %i[email banned_until]
      index %i[email created_at]
      index :created_at
    end

    puts '✓ Created account_bans table'
  end
end

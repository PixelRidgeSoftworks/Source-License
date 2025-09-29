# frozen_string_literal: true

# Source-License: Migration 13 - Add User ID to Licenses
# Adds user_id foreign key to licenses table

class Migrations::AddUserIdToLicenses < Migrations::BaseMigration
  VERSION = 13

  def up
    puts 'Adding user_id to licenses table...'

    # Add user_id foreign key to licenses table
    DB.alter_table :licenses do
      add_foreign_key :user_id, :users, null: true # Allow null for backward compatibility
    end

    # Add index for user_id
    DB.alter_table :licenses do
      add_index :user_id
    end

    puts '✓ Added user_id to licenses table'
  end
end

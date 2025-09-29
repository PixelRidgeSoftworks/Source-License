# frozen_string_literal: true

# Source-License: Migration 8 - Create Settings Table
# Creates the settings table for application configuration

class Migrations::CreateSettingsTable < Migrations::BaseMigration
  VERSION = 8

  def up
    DB.create_table :settings do
      primary_key :id
      String :key, null: false, unique: true, size: 255
      Text :value
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :key
    end
  end
end

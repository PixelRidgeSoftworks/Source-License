# frozen_string_literal: true

# Source-License: Migration 17 - Create Taxes Table
# Creates the taxes table for custom tax configuration

class Migrations::CreateTaxesTable < Migrations::BaseMigration
  VERSION = 17

  def up
    puts 'Creating taxes table for custom tax configuration...'

    DB.create_table :taxes do
      primary_key :id
      String :name, null: false, size: 255
      String :description, size: 500
      Decimal :rate, size: [8, 4], null: false # percentage rate (e.g., 8.25 for 8.25%)
      String :status, default: 'active', size: 20 # active, inactive
      String :type, default: 'percentage', size: 20 # percentage, fixed (for future use)
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :name
      index :status
      index :rate
    end

    puts '✓ Created taxes table'
  end
end

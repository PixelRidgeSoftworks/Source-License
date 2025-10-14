# frozen_string_literal: true

# Source-License: Migration 28 - Create Billing Addresses Table
# Creates the billing_addresses table for customer address management

class Migrations::CreateBillingAddressesTable < Migrations::BaseMigration
  VERSION = 28

  def up
    puts 'Creating billing_addresses table for customer address management...'

    DB.create_table :billing_addresses do
      primary_key :id
      foreign_key :user_id, :users, null: false, on_delete: :cascade
      String :name, null: false, size: 255 # Address nickname like "Home", "Work"
      String :first_name, null: false, size: 100
      String :last_name, null: false, size: 100
      String :company, size: 100 # Optional company name
      String :address_line_1, null: false, size: 255
      String :address_line_2, size: 255 # Optional second line
      String :city, null: false, size: 100
      String :state_province, null: false, size: 100 # State/Province
      String :postal_code, null: false, size: 20 # ZIP/Postal Code
      String :country, null: false, size: 100
      String :phone, size: 20 # Optional phone number
      Boolean :is_default, default: false # Default address for this user
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Indexes for performance
      index :user_id
      index %i[user_id is_default] # For finding user's default address
      index :created_at
    end

    puts '✓ Created billing_addresses table'
  end

  def down
    puts 'Dropping billing_addresses table...'
    DB.drop_table :billing_addresses
    puts '✓ Dropped billing_addresses table'
  end
end

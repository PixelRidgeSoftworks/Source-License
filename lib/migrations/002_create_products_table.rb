# frozen_string_literal: true

# Source-License: Migration 2 - Create Products Table
# Creates the products table for managing software products

class Migrations::CreateProductsTable < Migrations::BaseMigration
  VERSION = 2

  def up
    DB.create_table :products do
      primary_key :id
      String :name, null: false, size: 255
      Text :description
      Text :features # JSON field for product features
      Decimal :price, size: [10, 2], null: false
      String :license_type, null: false, default: 'one_time' # 'one_time' or 'subscription'
      Integer :license_duration_days # null for one-time, number for subscription
      Integer :max_activations, default: 1
      String :download_file, size: 255 # filename in downloads directory
      String :version, size: 50
      Boolean :active, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :name
      index :license_type
      index :active
    end
  end
end

# frozen_string_literal: true

# Source-License: Migration 5 - Create Licenses Table
# Creates the licenses table for managing software licenses

class Migrations::CreateLicensesTable < Migrations::BaseMigration
  VERSION = 5

  def up
    DB.create_table :licenses do
      primary_key :id
      String :license_key, null: false, unique: true, size: 255
      foreign_key :order_id, :orders, null: false
      foreign_key :product_id, :products, null: false
      String :customer_email, null: false, size: 255
      String :status, null: false, default: 'active' # active, suspended, revoked, expired
      Integer :max_activations, null: false, default: 1
      Integer :activation_count, default: 0
      Integer :download_count, default: 0
      DateTime :expires_at # null for lifetime licenses
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_activated_at
      DateTime :last_downloaded_at

      index :license_key
      index :customer_email
      index :status
      index :order_id
      index :product_id
    end
  end
end

# frozen_string_literal: true

# Source-License: Migration 7 - Create License Activations Table
# Creates the license_activations table for tracking license activations

class Migrations::CreateLicenseActivationsTable < Migrations::BaseMigration
  VERSION = 7

  def up
    DB.create_table :license_activations do
      primary_key :id
      foreign_key :license_id, :licenses, null: false, on_delete: :cascade
      String :machine_fingerprint, size: 255 # unique machine identifier
      String :ip_address, size: 45 # supports both IPv4 and IPv6
      String :user_agent, size: 500
      Text :system_info # JSON field for system information
      Boolean :active, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :deactivated_at

      index :license_id
      index :machine_fingerprint
      index %i[license_id machine_fingerprint], unique: true
    end
  end
end

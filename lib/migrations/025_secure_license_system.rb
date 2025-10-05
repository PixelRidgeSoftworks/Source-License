# frozen_string_literal: true

# Source-License: Migration 25 - Secure License System
# Adds security enhancements including hashed license keys and secure machine data

class Migrations::SecureLicenseSystem < Migrations::BaseMigration
  VERSION = 25

  def up
    # Add hashed license key field to licenses table
    DB.alter_table :licenses do
      add_column :license_key_hash, String, size: 60 # bcrypt hash length
      add_column :license_salt, String, size: 32 # salt for additional security
    end

    # Add security fields to license activations table
    DB.alter_table :license_activations do
      add_column :machine_fingerprint_hash, String, size: 64 # SHA-256 hash length
      add_column :machine_id_hash, String, size: 64 # SHA-256 hash length
      add_column :revoked, TrueClass, default: false
      add_column :revoked_at, DateTime
      add_column :revoked_reason, String, size: 255
    end

    # Add audit log table for tracking license operations
    DB.create_table :license_audit_logs do
      primary_key :id
      foreign_key :license_id, :licenses, null: true, on_delete: :set_null
      String :license_key_partial, size: 8 # Only store first 8 chars for identification
      String :action, null: false, size: 50 # validate, activate, revoke, etc.
      String :ip_address, size: 45 # supports both IPv4 and IPv6
      String :user_agent, size: 500
      String :machine_fingerprint_partial, size: 16 # Only store partial for identification
      String :machine_id_partial, size: 16 # Only store partial for identification
      Boolean :success, default: false
      String :failure_reason, size: 255
      Text :metadata # Additional context as JSON
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :license_id
      index :action
      index :ip_address
      index :created_at
      index %i[success action]
    end

    # Add rate limiting table for API protection
    DB.create_table :rate_limits do
      primary_key :id
      String :key_type, null: false, size: 20 # 'ip', 'license_key', 'endpoint'
      String :key_value, null: false, size: 255 # IP address, license key hash, etc.
      String :endpoint, size: 100 # API endpoint
      Integer :requests, default: 0
      DateTime :window_start, null: false
      DateTime :expires_at, null: false

      index %i[key_type key_value endpoint], unique: true
      index :expires_at
    end

    # Add indexes for performance
    DB.add_index :licenses, :license_key_hash
    DB.add_index :license_activations, :machine_fingerprint_hash
    DB.add_index :license_activations, :machine_id_hash
    DB.add_index :license_activations, :revoked
  end

  def down
    # Remove indexes
    DB.drop_index :license_activations, :revoked
    DB.drop_index :license_activations, :machine_id_hash
    DB.drop_index :license_activations, :machine_fingerprint_hash
    DB.drop_index :licenses, :license_key_hash

    # Remove tables
    DB.drop_table :rate_limits
    DB.drop_table :license_audit_logs

    # Remove columns from license_activations
    DB.alter_table :license_activations do
      drop_column :revoked_reason
      drop_column :revoked_at
      drop_column :revoked
      drop_column :machine_id_hash
      drop_column :machine_fingerprint_hash
    end

    # Remove columns from licenses
    DB.alter_table :licenses do
      drop_column :license_salt
      drop_column :license_key_hash
    end
  end
end

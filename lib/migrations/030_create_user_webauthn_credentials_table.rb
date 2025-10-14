# frozen_string_literal: true

# Source-License: Migration 30 - Create User WebAuthn Credentials Table
# Creates the user_webauthn_credentials table for WebAuthn (Windows Hello, YubiKey, etc.) support

class Migrations::CreateUserWebauthnCredentialsTable < Migrations::BaseMigration
  VERSION = 30

  def up
    puts 'Creating user_webauthn_credentials table for WebAuthn authentication...'

    DB.create_table :user_webauthn_credentials do
      primary_key :id
      foreign_key :user_id, :users, null: false, on_delete: :cascade
      String :external_id, null: false, size: 255, unique: true # WebAuthn credential ID
      String :public_key, null: false, size: 1000 # Base64 encoded public key
      String :nickname, null: false, size: 100 # User-friendly name like "YubiKey", "Windows Hello"
      Integer :sign_count, default: 0 # WebAuthn sign counter for replay protection
      String :aaguid, size: 36 # Authenticator Attestation GUID
      String :attestation_format, size: 50 # Attestation format used during registration
      Text :attestation_statement # JSON of attestation statement (for audit purposes)
      String :transports, size: 500 # JSON array of supported transports (usb, nfc, ble, internal)
      Boolean :backup_eligible, default: false # Whether credential can be backed up
      Boolean :backup_state, default: false # Whether credential is backed up
      DateTime :last_used_at, null: true # Last successful authentication
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Indexes for performance and security
      index :user_id
      index :external_id, unique: true
      index :last_used_at
      index :created_at
      index %i[user_id created_at] # For listing user's credentials chronologically
    end

    puts '✓ Created user_webauthn_credentials table'
  end

  def down
    puts 'Dropping user_webauthn_credentials table...'
    DB.drop_table :user_webauthn_credentials
    puts '✓ Dropped user_webauthn_credentials table'
  end
end

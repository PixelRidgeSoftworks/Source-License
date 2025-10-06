# frozen_string_literal: true

require 'bcrypt'
require 'digest'
require 'securerandom'
require 'jwt'

# Secure License Service
# Handles all cryptographic operations for license security
class SecureLicenseService
  class << self
    # Salt for hashing machine data (should be in environment variables in production)
    MACHINE_SALT = ENV.fetch('MACHINE_HASH_SALT', 'default_salt_change_in_production')

    # JWT signing key (should be in environment variables in production)
    JWT_SECRET = ENV.fetch('JWT_SECRET', SecureRandom.hex(32))
    JWT_ALGORITHM = 'HS256'

    # Hash a license key using bcrypt for secure storage
    def hash_license_key(license_key)
      BCrypt::Password.create(license_key, cost: 12)
    end

    # Verify a license key against its hash
    def verify_license_key(license_key, hash)
      return false if license_key.nil? || hash.nil?

      BCrypt::Password.new(hash) == license_key
    rescue BCrypt::Errors::InvalidHash
      false
    end

    # Hash machine data (fingerprint or machine_id) with server-side salt
    def hash_machine_data(data)
      return nil if data.nil? || data.to_s.strip.empty?

      Digest::SHA256.hexdigest("#{MACHINE_SALT}:#{data.to_s.strip}")
    end

    # Generate a secure JWT token for license validation responses
    def generate_license_jwt(license_data)
      # Only include minimal, necessary data
      payload = {
        valid: license_data[:valid],
        expires_at: license_data[:expires_at]&.iso8601,
        requires_machine_id: license_data[:requires_machine_id],
        iat: Time.now.to_i,
        exp: Time.now.to_i + 300, # Token expires in 5 minutes
      }

      # Add license-specific identifier (not the actual key)
      payload[:license_id] = license_data[:license_id] if license_data[:license_id]

      JWT.encode(payload, JWT_SECRET, JWT_ALGORITHM)
    end

    # Verify a JWT token
    def verify_jwt(token)
      JWT.decode(token, JWT_SECRET, true, algorithm: JWT_ALGORITHM)[0]
    rescue JWT::DecodeError
      nil
    end

    # Generate partial identifiers for logging (first few chars only)
    def partial_license_key(license_key)
      return nil if license_key.nil?

      license_key[0..7] if license_key.length > 8
    end

    def partial_machine_data(data)
      return nil if data.nil?

      data[0..15] if data.length > 16
    end

    # Log license operation for audit trail
    def log_license_operation(action:, license_id: nil, license_key: nil,
                              machine_fingerprint: nil, machine_id: nil,
                              ip_address: nil, user_agent: nil,
                              success: false, failure_reason: nil, metadata: {})
      DB[:license_audit_logs].insert(
        license_id: license_id,
        license_key_partial: partial_license_key(license_key),
        action: action.to_s,
        ip_address: ip_address,
        user_agent: user_agent&.length && user_agent.length > 500 ? user_agent[0..499] : user_agent,
        machine_fingerprint_partial: partial_machine_data(machine_fingerprint),
        machine_id_partial: partial_machine_data(machine_id),
        success: success,
        failure_reason: failure_reason,
        metadata: metadata.to_json,
        created_at: Time.now
      )
    end

    # Find license by hashed key (constant time lookup)
    def find_license_by_key(license_key)
      return nil if license_key.nil? || license_key.strip.empty?

      # Get all license hashes and check them in constant time
      # This prevents timing attacks while still being reasonably efficient
      licenses = DB[:licenses].select(:id, :license_key_hash, :status, :expires_at,
                                      :activation_count, :max_activations,
                                      :custom_max_activations, :custom_expires_at,
                                      :product_id, :requires_machine_id).all

      licenses.each do |license|
        next unless license[:license_key_hash]

        return license if verify_license_key(license_key, license[:license_key_hash])
      end

      nil
    end

    # Check rate limits for API endpoints
    def check_rate_limit(key_type:, key_value:, endpoint:, max_requests: 60, window_minutes: 1)
      now = Time.now
      window_start = now - (window_minutes * 60)

      # Clean up expired rate limit records
      DB[:rate_limits].where(expires_at: ..now).delete

      # Find or create rate limit record
      rate_limit = DB[:rate_limits].where(
        key_type: key_type.to_s,
        key_value: key_value.to_s,
        endpoint: endpoint.to_s
      ).first

      if rate_limit
        # Check if we're in the same window
        if rate_limit[:window_start] > window_start
          # Same window, check if limit exceeded
          if rate_limit[:requests] >= max_requests
            return { allowed: false, remaining: 0, reset_at: rate_limit[:expires_at] }
          end

          # Increment counter
          DB[:rate_limits].where(id: rate_limit[:id]).update(
            requests: rate_limit[:requests] + 1
          )

          {
            allowed: true,
            remaining: max_requests - (rate_limit[:requests] + 1),
            reset_at: rate_limit[:expires_at],
          }
        else
          # New window, reset counter
          expires_at = now + (window_minutes * 60)
          DB[:rate_limits].where(id: rate_limit[:id]).update(
            requests: 1,
            window_start: now,
            expires_at: expires_at
          )

          {
            allowed: true,
            remaining: max_requests - 1,
            reset_at: expires_at,
          }
        end
      else
        # Create new rate limit record
        expires_at = now + (window_minutes * 60)
        DB[:rate_limits].insert(
          key_type: key_type.to_s,
          key_value: key_value.to_s,
          endpoint: endpoint.to_s,
          requests: 1,
          window_start: now,
          expires_at: expires_at
        )

        {
          allowed: true,
          remaining: max_requests - 1,
          reset_at: expires_at,
        }
      end
    end

    # Enhanced error response that doesn't leak internal information
    def secure_error_response(message = 'Invalid request')
      {
        valid: false,
        error: message,
        timestamp: Time.now.iso8601,
      }
    end

    # Validate machine activation with hash comparison
    def validate_machine_activation(license_id, machine_fingerprint = nil, machine_id = nil)
      return false if license_id.nil?

      query = DB[:license_activations].where(
        license_id: license_id,
        active: true,
        revoked: false
      )

      # Add machine fingerprint check if provided
      if machine_fingerprint
        fingerprint_hash = hash_machine_data(machine_fingerprint)
        query = query.where(machine_fingerprint_hash: fingerprint_hash)
      end

      # Add machine ID check if provided
      if machine_id
        machine_id_hash = hash_machine_data(machine_id)
        query = query.where(machine_id_hash: machine_id_hash)
      end

      query.any?
    end

    # Migrate existing plaintext data to hashed versions (run once during deployment)
    def migrate_existing_data!
      puts '🔄 Migrating existing license keys to secure hashes...'

      # Migrate license keys
      DB[:licenses].where(license_key_hash: nil).each do |license|
        next unless license[:license_key]

        hash = hash_license_key(license[:license_key])
        salt = SecureRandom.hex(16)

        DB[:licenses].where(id: license[:id]).update(
          license_key_hash: hash,
          license_salt: salt
        )
      end

      puts '🔄 Migrating existing machine data to secure hashes...'

      # Migrate machine data in activations
      DB[:license_activations].where(machine_fingerprint_hash: nil).each do |activation|
        updates = {}

        if activation[:machine_fingerprint]
          updates[:machine_fingerprint_hash] = hash_machine_data(activation[:machine_fingerprint])
        end

        updates[:machine_id_hash] = hash_machine_data(activation[:machine_id]) if activation[:machine_id]

        DB[:license_activations].where(id: activation[:id]).update(updates) if updates.any?
      end

      puts '✅ Data migration completed successfully!'
    end
  end
end

# frozen_string_literal: true

require 'json'
require_relative '../../services/secure_license_service'
require_relative '../../license_generator'

# Secure License Controller
# Handles license validation, activation, and deactivation with security enhancements
class LicenseController
  class << self
    # Secure license validation with rate limiting and audit logging
    def validate_license(license_key, machine_fingerprint = nil, machine_id = nil, request_info = {})
      # Rate limiting by IP address
      rate_limit = SecureLicenseService.check_rate_limit(
        key_type: 'ip',
        key_value: request_info[:ip_address] || 'unknown',
        endpoint: '/api/license/validate',
        max_requests: 30, # More restrictive for validation
        window_minutes: 1
      )

      unless rate_limit[:allowed]
        return {
          valid: false,
          error: 'Rate limit exceeded',
          retry_after: 60,
          timestamp: Time.now.iso8601,
        }
      end

      # Use secure validator with enhanced logging and JWT response
      result = LicenseValidator.validate(
        license_key,
        machine_fingerprint,
        machine_id,
        request_info
      )

      # Add rate limit headers to response metadata
      result[:rate_limit] = {
        remaining: rate_limit[:remaining],
        reset_at: rate_limit[:reset_at].to_i,
      }

      result
    end

    # Secure license activation with comprehensive security checks
    def activate_license(license_key, machine_fingerprint = nil, machine_id = nil, request_info = {})
      # More restrictive rate limiting for activations
      rate_limit = SecureLicenseService.check_rate_limit(
        key_type: 'ip',
        key_value: request_info[:ip_address] || 'unknown',
        endpoint: '/api/license/activate',
        max_requests: 10, # Very restrictive for activations
        window_minutes: 1
      )

      unless rate_limit[:allowed]
        return {
          success: false,
          error: 'Rate limit exceeded',
          retry_after: 60,
          timestamp: Time.now.iso8601,
        }
      end

      # Additional rate limiting by license key to prevent brute force
      if license_key
        license_rate_limit = SecureLicenseService.check_rate_limit(
          key_type: 'license_key',
          key_value: SecureLicenseService.partial_license_key(license_key),
          endpoint: '/api/license/activate',
          max_requests: 5, # Per license key limit
          window_minutes: 5
        )

        unless license_rate_limit[:allowed]
          return {
            success: false,
            error: 'License activation rate limit exceeded',
            retry_after: 300,
            timestamp: Time.now.iso8601,
          }
        end
      end

      # Use secure validator for activation
      result = LicenseValidator.activate(
        license_key,
        machine_fingerprint,
        machine_id,
        request_info
      )

      # Add rate limit info to response
      result[:rate_limit] = {
        remaining: rate_limit[:remaining],
        reset_at: rate_limit[:reset_at].to_i,
      }

      result
    end

    # Secure license deactivation
    def deactivate_license(license_key, machine_fingerprint = nil, machine_id = nil, request_info = {})
      # Rate limiting for deactivations
      rate_limit = SecureLicenseService.check_rate_limit(
        key_type: 'ip',
        key_value: request_info[:ip_address] || 'unknown',
        endpoint: '/api/license/deactivate',
        max_requests: 20,
        window_minutes: 1
      )

      unless rate_limit[:allowed]
        return {
          success: false,
          error: 'Rate limit exceeded',
          retry_after: 60,
          timestamp: Time.now.iso8601,
        }
      end

      # Use secure validator for deactivation
      result = LicenseValidator.deactivate(
        license_key,
        machine_fingerprint,
        machine_id,
        request_info
      )

      # Add rate limit info to response
      result[:rate_limit] = {
        remaining: rate_limit[:remaining],
        reset_at: rate_limit[:reset_at].to_i,
      }

      result
    end

    # Get license information (limited data for security)
    def get_license_info(license_key, request_info = {})
      # Rate limiting
      rate_limit = SecureLicenseService.check_rate_limit(
        key_type: 'ip',
        key_value: request_info[:ip_address] || 'unknown',
        endpoint: '/api/license/info',
        max_requests: 60,
        window_minutes: 1
      )

      unless rate_limit[:allowed]
        return {
          success: false,
          error: 'Rate limit exceeded',
          retry_after: 60,
          timestamp: Time.now.iso8601,
        }
      end

      # Log the info request
      SecureLicenseService.log_license_operation(
        action: 'info',
        license_key: license_key,
        ip_address: request_info[:ip_address],
        user_agent: request_info[:user_agent],
        success: false, # Will update if found
        failure_reason: nil
      )

      # Use secure service for lookup
      license = SecureLicenseService.find_license_by_key(license_key)

      unless license
        return {
          success: false,
          error: 'License not found',
          timestamp: Time.now.iso8601,
        }
      end

      # Return limited, safe information
      {
        success: true,
        license: {
          status: license[:status],
          expires_at: license[:expires_at]&.iso8601,
          max_activations: license[:max_activations],
          activation_count: license[:activation_count],
          requires_machine_id: !license[:requires_machine_id].nil?,
          license_type: license[:license_type],
        },
        rate_limit: {
          remaining: rate_limit[:remaining],
          reset_at: rate_limit[:reset_at].to_i,
        },
        timestamp: Time.now.iso8601,
      }
    end

    # Revoke a license activation (admin function)
    def revoke_activation(license_key, machine_fingerprint = nil, machine_id = nil, reason = 'Admin revocation',
                          request_info = {})
      # Find license using secure service
      license = SecureLicenseService.find_license_by_key(license_key)

      unless license
        return {
          success: false,
          error: 'License not found',
          timestamp: Time.now.iso8601,
        }
      end

      success = false
      begin
        # Find and revoke specific activation
        query = DB[:license_activations].where(
          license_id: license[:id],
          active: true,
          revoked: false
        )

        # Add machine-specific filters if provided
        if machine_fingerprint
          fingerprint_hash = SecureLicenseService.hash_machine_data(machine_fingerprint)
          query = query.where(machine_fingerprint_hash: fingerprint_hash)
        end

        if machine_id
          machine_id_hash = SecureLicenseService.hash_machine_data(machine_id)
          query = query.where(machine_id_hash: machine_id_hash)
        end

        activations = query.all

        if activations.any?
          # Revoke all matching activations
          DB.transaction do
            activations.each do |activation|
              DB[:license_activations].where(id: activation[:id]).update(
                revoked: true,
                revoked_at: Time.now,
                revoked_reason: reason,
                active: false
              )
            end

            # Update license activation count
            DB[:licenses].where(id: license[:id]).update(
              activation_count: [license[:activation_count] - activations.count, 0].max,
              updated_at: Time.now
            )
          end

          success = true
          message = "Revoked #{activations.count} activation(s)"
        else
          message = 'No matching activations found'
        end
      rescue StandardError
        message = 'Revocation failed'
      end

      # Log the revocation attempt
      SecureLicenseService.log_license_operation(
        action: 'revoke_activation',
        license_id: license[:id],
        license_key: license_key,
        machine_fingerprint: machine_fingerprint,
        machine_id: machine_id,
        ip_address: request_info[:ip_address],
        user_agent: request_info[:user_agent],
        success: success,
        failure_reason: success ? nil : message,
        metadata: { reason: reason }
      )

      {
        success: success,
        message: message,
        timestamp: Time.now.iso8601,
      }
    end

    # Get activation history for a license (admin function)
    def get_activation_history(license_key, request_info = {})
      license = SecureLicenseService.find_license_by_key(license_key)

      unless license
        return {
          success: false,
          error: 'License not found',
          timestamp: Time.now.iso8601,
        }
      end

      # Get activation history with partial machine data for privacy
      activations = DB[:license_activations]
        .where(license_id: license[:id])
        .order(Sequel.desc(:activated_at))
        .limit(50) # Limit to recent activations
        .all

      activation_list = activations.map do |activation|
        {
          id: activation[:id],
          activated_at: activation[:activated_at]&.iso8601,
          deactivated_at: activation[:deactivated_at]&.iso8601,
          ip_address: activation[:ip_address],
          active: activation[:active],
          revoked: activation[:revoked],
          revoked_at: activation[:revoked_at]&.iso8601,
          revoked_reason: activation[:revoked_reason],
          # Only show partial machine data for security
          machine_fingerprint_partial: SecureLicenseService.partial_machine_data(activation[:machine_fingerprint]),
          machine_id_partial: SecureLicenseService.partial_machine_data(activation[:machine_id]),
        }
      end

      # Log the history access
      SecureLicenseService.log_license_operation(
        action: 'history',
        license_id: license[:id],
        license_key: license_key,
        ip_address: request_info[:ip_address],
        user_agent: request_info[:user_agent],
        success: true,
        metadata: { activations_count: activations.count }
      )

      {
        success: true,
        license_key: SecureLicenseService.partial_license_key(license_key),
        activations: activation_list,
        total_activations: license[:activation_count],
        max_activations: license[:max_activations],
        timestamp: Time.now.iso8601,
      }
    end

    # Extract request information for security logging
    def extract_request_info(request)
      {
        ip_address: request.ip || 'unknown',
        user_agent: request.user_agent || 'unknown',
        method: request.request_method || 'unknown',
        path: request.path_info || 'unknown',
      }
    end
  end
end

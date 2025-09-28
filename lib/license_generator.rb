# frozen_string_literal: true

# Source-License: License Generator
# Handles creation and management of software licenses

require 'securerandom'
require 'digest'

class LicenseGenerator
  class << self
    # Generate a new license for a product and order
    def generate_for_product(product, order, user = nil)
      license_key = generate_license_key

      license = License.create(
        license_key: license_key,
        order_id: order.id,
        product_id: product.id,
        customer_email: order.email,
        customer_name: order.customer_name,
        user_id: user&.id, # Link to user account if available
        status: 'active',
        max_activations: product.max_activations,
        activation_count: 0,
        download_count: 0,
        license_type: product.subscription? ? 'subscription' : 'perpetual',
        created_at: Time.now,
        updated_at: Time.now
      )

      # Set expiration for subscription products
      set_license_expiration(license, product) if product.subscription?

      # Create subscription record if needed
      create_subscription_record(license, product) if product.subscription?

      license
    end

    # Generate a unique license key
    def generate_license_key(format = :standard)
      case format
      when :long
        # Format: XXXXXXXX-XXXXXXXX-XXXXXXXX
        Array.new(3) { generate_key_segment(8) }.join('-')
      when :uuid
        # Generate UUID-like format
        SecureRandom.uuid.upcase
      else
        # Default to standard format: XXXX-XXXX-XXXX-XXXX
        Array.new(4) { generate_key_segment(4) }.join('-')
      end
    end

    # Validate license key format
    def valid_key_format?(key)
      # Standard format: XXXX-XXXX-XXXX-XXXX
      return true if key.match?(/\A[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)

      # Long format: XXXXXXXX-XXXXXXXX-XXXXXXXX
      return true if key.match?(/\A[A-Z0-9]{8}-[A-Z0-9]{8}-[A-Z0-9]{8}\z/)

      # UUID format
      return true if key.match?(/\A[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\z/)

      false
    end

    # Generate a batch of licenses
    def generate_batch(product, count, customer_email = nil)
      licenses = []

      count.times do
        # Create a temporary order for batch generation
        order = Order.create(
          email: customer_email || 'batch@generated.com',
          customer_name: 'Batch Generated',
          amount: product.price,
          currency: 'USD',
          status: 'completed',
          payment_method: 'manual',
          completed_at: Time.now
        )

        OrderItem.create(
          order_id: order.id,
          product_id: product.id,
          quantity: 1,
          price: product.price
        )

        license = generate_for_product(product, order)
        licenses << license
      end

      licenses
    end

    # Revoke a license
    def revoke_license(license_key, reason = 'Manual revocation')
      license = License.first(license_key: license_key)
      return false unless license

      license.revoke!

      # Log the revocation
      log_license_action(license, 'revoked', reason)

      true
    end

    # Suspend a license temporarily
    def suspend_license(license_key, reason = 'Manual suspension')
      license = License.first(license_key: license_key)
      return false unless license

      license.suspend!

      # Log the suspension
      log_license_action(license, 'suspended', reason)

      true
    end

    # Reactivate a suspended license
    def reactivate_license(license_key, reason = 'Manual reactivation')
      license = License.first(license_key: license_key)
      return false unless license
      return false unless license.suspended?

      license.reactivate!

      # Log the reactivation
      log_license_action(license, 'reactivated', reason)

      true
    end

    # Extend license expiration
    def extend_license(license_key, days)
      license = License.first(license_key: license_key)
      return false unless license

      license.extend!(days)

      # Log the extension
      log_license_action(license, 'extended', "Extended by #{days} days")

      true
    end

    # Transfer license to new email
    def transfer_license(license_key, new_email)
      license = License.first(license_key: license_key)
      return false unless license

      old_email = license.customer_email
      license.update(customer_email: new_email)

      # Log the transfer
      log_license_action(license, 'transferred', "From #{old_email} to #{new_email}")

      true
    end

    # Get license statistics
    def license_stats(product_id = nil)
      base_query = product_id ? License.where(product_id: product_id) : License

      {
        total: base_query.count,
        active: base_query.where(status: 'active').count,
        suspended: base_query.where(status: 'suspended').count,
        revoked: base_query.where(status: 'revoked').count,
        expired: base_query.where(status: 'expired').count,
        total_activations: base_query.sum(:activation_count) || 0,
        total_downloads: base_query.sum(:download_count) || 0,
      }
    end

    # Check for expiring licenses (for notifications)
    def expiring_licenses(days_ahead = 7)
      cutoff_date = Time.now + (days_ahead * 24 * 60 * 60)

      License.where(status: 'active')
        .where { expires_at <= cutoff_date }
        .where { expires_at > Time.now }
        .order(:expires_at)
    end

    # Generate license file content (for downloadable licenses)
    def generate_license_file(license)
      product = license.product

      <<~LICENSE_FILE
        #{product.name} - Software License
        ================================

        License Key: #{license.license_key}
        Product: #{product.name}
        Version: #{product.version || 'Latest'}
        License Type: #{product.license_type.capitalize}

        Licensed To: #{license.customer_email}
        Issue Date: #{license.created_at.strftime('%Y-%m-%d')}
        #{"Expiration Date: #{license.expires_at.strftime('%Y-%m-%d')}" if license.expires_at}

        Maximum Activations: #{license.max_activations}
        Current Activations: #{license.activation_count}

        Terms and Conditions:
        - This license is non-transferable except as allowed by the software vendor
        - You may install this software on up to #{license.max_activations} machine(s)
        - Unauthorized distribution or sharing of this license is prohibited
        - Support is provided according to the vendor's support policy

        For support, please contact: #{ENV['ADMIN_EMAIL'] || 'support@example.com'}

        License verification can be performed at:
        #{ENV['APP_HOST'] || 'localhost:4567'}/api/license/#{license.license_key}/validate

        Digital Signature: #{generate_license_signature(license)}
      LICENSE_FILE
    end

    private

    # Generate a key segment with specified length
    def generate_key_segment(length)
      chars = ('A'..'Z').to_a + ('0'..'9').to_a
      # Remove confusing characters
      chars -= %w[0 O 1 I]

      Array.new(length) { chars.sample }.join
    end

    # Set license expiration based on product type
    def set_license_expiration(license, product)
      return unless product.subscription? && product.license_duration_days

      license.update(expires_at: Time.now + (product.license_duration_days * 24 * 60 * 60))
    end

    # Create subscription record for subscription products
    def create_subscription_record(license, product)
      return unless product.subscription?

      start_time = Time.now
      end_time = start_time + (product.license_duration_days * 24 * 60 * 60)

      Subscription.create(
        license_id: license.id,
        status: 'active',
        current_period_start: start_time,
        current_period_end: end_time,
        auto_renew: true
      )
    end

    # Log license actions for audit trail
    def log_license_action(license, action, details = nil)
      # In a production system, you might want to create a separate audit log table
      # For now, we'll just log to the application logger
      message = "License #{license.license_key} #{action}"
      message += " - #{details}" if details

      if defined?(Rails)
        Rails.logger.info(message)
      else
        puts "[LICENSE] #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} - #{message}"
      end
    end

    # Generate digital signature for license verification
    def generate_license_signature(license)
      data = [
        license.license_key,
        license.product.name,
        license.customer_email,
        license.created_at.to_i,
        ENV['APP_SECRET'] || 'default_secret',
      ].join('|')

      Digest::SHA256.hexdigest(data)[0..15] # First 16 characters
    end

    # Verify license signature
    def verify_license_signature(license, signature)
      expected_signature = generate_license_signature(license)
      signature == expected_signature
    end
  end
end

# License validation service
class LicenseValidator
  class << self
    # Validate a license key
    def validate(license_key, machine_fingerprint = nil)
      license = License.first(license_key: license_key)

      return validation_result(false, 'License not found') unless license
      return validation_result(false, 'License is revoked') if license.revoked?
      return validation_result(false, 'License is suspended') if license.suspended?
      return validation_result(false, 'License has expired') if license.expired?

      # Check machine fingerprint if provided
      if machine_fingerprint
        activation = license.license_activations_dataset.where(
          machine_fingerprint: machine_fingerprint,
          active: true
        ).first

        return validation_result(false, 'License not activated on this machine') unless activation
      end

      validation_result(true, 'License is valid', license_info(license))
    end

    # Activate license on a machine
    def activate(license_key, machine_fingerprint, system_info = {})
      license = License.first(license_key: license_key)

      return activation_result(false, 'License not found') unless license
      return activation_result(false, 'License is not valid') unless license.valid?
      return activation_result(false, 'No activations remaining') unless license.activations_available?

      if license.activate!(machine_fingerprint, system_info[:ip_address], system_info[:user_agent], system_info)
        activation_result(true, 'License activated successfully', {
          activations_remaining: license.remaining_activations,
          expires_at: license.expires_at,
        })
      else
        activation_result(false, 'License already activated on this machine')
      end
    end

    # Deactivate license on a machine
    def deactivate(license_key, machine_fingerprint)
      license = License.first(license_key: license_key)

      return deactivation_result(false, 'License not found') unless license

      if license.deactivate!(machine_fingerprint)
        deactivation_result(true, 'License deactivated successfully')
      else
        deactivation_result(false, 'License not activated on this machine')
      end
    end

    private

    def validation_result(valid, message, data = {})
      {
        valid: valid,
        message: message,
        timestamp: Time.now.iso8601,
      }.merge(data)
    end

    def activation_result(success, message, data = {})
      {
        success: success,
        message: message,
        timestamp: Time.now.iso8601,
      }.merge(data)
    end

    def deactivation_result(success, message, data = {})
      {
        success: success,
        message: message,
        timestamp: Time.now.iso8601,
      }.merge(data)
    end

    def license_info(license)
      {
        product_name: license.product.name,
        product_version: license.product.version,
        customer_email: license.customer_email,
        max_activations: license.max_activations,
        current_activations: license.activation_count,
        expires_at: license.expires_at,
        issued_at: license.created_at,
      }
    end
  end
end

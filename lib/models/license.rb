# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Software licenses
class License < Sequel::Model
  include BaseModelMethods

  set_dataset :licenses
  many_to_one :order
  many_to_one :product
  many_to_one :user
  one_to_many :license_activations
  one_to_one :subscription

  # Check if license is valid
  def valid?
    return false unless active?
    return false if expired?

    true
  end

  # Check if license is valid (alias for compatibility)
  def license_valid?
    valid?
  end

  # Check if license is active
  def active?
    status == 'active'
  end

  # Check if license is expired
  def expired?
    return false unless expires_at

    expires_at < Time.now
  end

  # Check if license is revoked
  def revoked?
    status == 'revoked'
  end

  # Check if license is suspended
  def suspended?
    status == 'suspended'
  end

  # Check if more activations are available
  def activations_available?
    activation_count < effective_max_activations
  end

  # Get remaining activations
  def remaining_activations
    effective_max_activations - activation_count
  end

  # Get effective max activations (custom override or product default)
  def effective_max_activations
    custom_max_activations || max_activations || product&.max_activations || 1
  end

  # Get effective expiration date (custom override or product-based)
  def effective_expires_at
    custom_expires_at || expires_at
  end

  # Check if license has custom configuration
  def custom_config?
    custom_max_activations || custom_expires_at
  end

  # Check license type
  def perpetual?
    license_type == 'perpetual'
  end

  def subscription_based?
    license_type == 'subscription'
  end

  def trial?
    license_type == 'trial'
  end

  # Check trial status
  def trial_active?
    trial? && trial_ends_at && trial_ends_at > Time.now
  end

  def trial_expired?
    trial? && trial_ends_at && trial_ends_at <= Time.now
  end

  # Check grace period status
  def in_grace_period?
    grace_period_ends_at && grace_period_ends_at > Time.now
  end

  def grace_period_expired?
    grace_period_ends_at && grace_period_ends_at <= Time.now
  end

  # Start trial period
  def start_trial!(days = nil)
    trial_days = days || product&.trial_period_days || 0
    return false if trial_days <= 0

    update(
      license_type: 'trial',
      trial_ends_at: Time.now + (trial_days * 24 * 60 * 60),
      status: 'active'
    )
  end

  # Convert trial to subscription
  def convert_trial_to_subscription!
    return false unless trial?

    update(
      license_type: 'subscription',
      trial_ends_at: nil
    )

    # Set up subscription if product is subscription-based
    return unless product&.subscription?

    create_subscription_from_product!
  end

  # Enter grace period after failed payment
  def enter_grace_period!
    grace_days = product&.grace_period_days || 7
    update(
      grace_period_ends_at: Time.now + (grace_days * 24 * 60 * 60),
      status: 'active' # Keep active during grace period
    )
  end

  # Create subscription record from product configuration
  def create_subscription_from_product!
    return unless product&.subscription?
    return if subscription # Already has subscription

    cycle = product.billing_cycle_object
    return unless cycle

    now = Time.now
    period_end = cycle.next_billing_date(now)

    Subscription.create(
      license_id: id,
      status: 'active',
      current_period_start: now,
      current_period_end: period_end,
      billing_cycle: product.billing_cycle,
      billing_interval: product.billing_interval || 1,
      next_billing_date: period_end,
      auto_renew: true
    )
  end

  # Activate license for a machine
  def activate!(machine_fingerprint, ip_address = nil, user_agent = nil, system_info = {})
    return false unless valid?
    return false unless activations_available?

    # Check if already activated on this machine
    existing = license_activations_dataset.where(
      machine_fingerprint: machine_fingerprint,
      active: true
    ).first

    return false if existing

    DB.transaction do
      # Create activation record
      add_license_activation(
        machine_fingerprint: machine_fingerprint,
        ip_address: ip_address,
        user_agent: user_agent,
        system_info: system_info.to_json,
        active: true
      )

      # Update activation count
      update(
        activation_count: activation_count + 1,
        last_activated_at: Time.now
      )
    end

    true
  end

  # Deactivate license for a machine
  def deactivate!(machine_fingerprint)
    activation = license_activations_dataset.where(
      machine_fingerprint: machine_fingerprint,
      active: true
    ).first

    return false unless activation

    DB.transaction do
      activation.update(active: false, deactivated_at: Time.now)
      update(activation_count: [0, activation_count - 1].max)
    end

    true
  end

  # Revoke license
  def revoke!
    update(status: 'revoked')
    # Deactivate all activations
    license_activations_dataset.where(active: true).update(
      active: false,
      deactivated_at: Time.now
    )
  end

  # Suspend license
  def suspend!
    update(status: 'suspended')
  end

  # Reactivate suspended license
  def reactivate!
    update(status: 'active')
  end

  # Set expiration date based on product
  def set_expiration_from_product!
    return unless product.subscription? && product.license_duration_days

    start_date = subscription&.current_period_start || created_at
    self.expires_at = start_date + (product.license_duration_days * 24 * 60 * 60)
    save_changes
  end

  # Extend license (for renewals)
  def extend!(days)
    current_expiry = expires_at || Time.now
    self.expires_at = current_expiry + (days * 24 * 60 * 60)
    save_changes
  end

  # Validation
  def validate
    super
    errors.add(:license_key, 'cannot be empty') if !license_key || license_key.strip.empty?
    errors.add(:customer_email, 'cannot be empty') if !customer_email || customer_email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i.match?(customer_email)
      errors.add(:customer_email,
                 'must be valid email format')
    end
    errors.add(:status, 'invalid status') unless %w[active suspended revoked expired].include?(status)
    errors.add(:max_activations, 'must be greater than 0') if !max_activations || max_activations <= 0
  end
end

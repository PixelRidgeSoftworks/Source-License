# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Billing cycles for subscription management
class BillingCycle < Sequel::Model
  include BaseModelMethods

  set_dataset :billing_cycles

  # Get all active billing cycles
  def self.active
    where(active: true)
  end

  # Get billing cycle by name
  def self.by_name(name)
    where(name: name).first
  end

  # Calculate next billing date from a start date
  def next_billing_date(from_date = Time.now)
    from_date + (days * 24 * 60 * 60)
  end

  # Get Stripe-compatible interval
  def stripe_pricing_config
    {
      interval: stripe_interval,
      interval_count: stripe_interval_count,
    }
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:display_name, 'cannot be empty') if !display_name || display_name.strip.empty?
    errors.add(:days, 'must be greater than 0') if !days || days <= 0
    errors.add(:stripe_interval, 'must be week, month, or year') unless %w[week month year].include?(stripe_interval)
    errors.add(:stripe_interval_count, 'must be greater than 0') if !stripe_interval_count || stripe_interval_count <= 0
  end
end

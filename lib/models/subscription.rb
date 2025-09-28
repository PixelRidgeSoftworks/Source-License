# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Subscription management for recurring licenses
class Subscription < Sequel::Model
  include BaseModelMethods

  set_dataset :subscriptions
  many_to_one :license

  # Check if subscription is active
  def active?
    status == 'active' && current_period_end > Time.now
  end

  # Check if subscription is canceled
  def canceled?
    status == 'canceled'
  end

  # Check if subscription is past due
  def past_due?
    status == 'past_due'
  end

  # Check if subscription is in current period
  def in_current_period?
    now = Time.now
    now.between?(current_period_start, current_period_end)
  end

  # Cancel subscription
  def cancel!
    update(status: 'canceled', canceled_at: Time.now, auto_renew: false)
  end

  # Renew subscription for next period
  def renew!(next_period_start, next_period_end)
    update(
      current_period_start: next_period_start,
      current_period_end: next_period_end,
      status: 'active'
    )

    # Extend license
    license.extend!(license.product.license_duration_days)
  end

  # Validation
  def validate
    super
    errors.add(:status, 'invalid status') unless %w[active canceled past_due unpaid].include?(status)
    errors.add(:current_period_start, 'cannot be empty') unless current_period_start
    errors.add(:current_period_end, 'cannot be empty') unless current_period_end
    return unless current_period_end && current_period_start && current_period_end <= current_period_start

    errors.add(:current_period_end,
               'must be after start')
  end
end

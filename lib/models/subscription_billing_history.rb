# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Subscription billing history tracking
class SubscriptionBillingHistory < Sequel::Model
  include BaseModelMethods

  set_dataset :subscription_billing_histories
  many_to_one :subscription

  # Check payment status
  def paid?
    status == 'paid'
  end

  def failed?
    status == 'failed'
  end

  def pending?
    status == 'pending'
  end

  def refunded?
    status == 'refunded'
  end

  # Mark as paid
  def mark_paid!(payment_date = Time.now)
    update(status: 'paid', paid_at: payment_date)
  end

  # Mark as failed
  def mark_failed!(reason = nil)
    update(status: 'failed', failed_at: Time.now, failure_reason: reason)
  end

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Get billing period duration in days
  def period_duration_days
    ((billing_period_end - billing_period_start) / (24 * 60 * 60)).round
  end

  # Validation
  def validate
    super
    errors.add(:amount, 'must be greater than 0') if !amount || amount <= 0
    errors.add(:status, 'invalid status') unless %w[pending paid failed refunded].include?(status)
    errors.add(:billing_period_start, 'cannot be empty') unless billing_period_start
    errors.add(:billing_period_end, 'cannot be empty') unless billing_period_end
    return unless billing_period_end && billing_period_start && billing_period_end <= billing_period_start

    errors.add(:billing_period_end, 'must be after start')
  end
end

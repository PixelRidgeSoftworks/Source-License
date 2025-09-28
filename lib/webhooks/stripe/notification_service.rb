# frozen_string_literal: true

# Service for sending notifications related to Stripe webhook events
class Webhooks::Stripe::NotificationService
  class << self
    # Charge-related notifications
    def send_charge_success_notification(license, charge)
      amount = charge.amount / 100.0
      puts "NOTIFICATION: Charge successful for license #{license.license_key} - Amount: $#{amount}"
    end

    def send_charge_failed_notification(license, charge)
      puts "NOTIFICATION: Charge failed for license #{license.license_key} - Reason: #{charge.failure_message}"
    end

    # License-related notifications
    def send_license_revoked_notification(license, reason)
      puts "NOTIFICATION: License #{license.license_key} revoked due to #{reason}"
    end

    # Subscription-related notifications
    def send_subscription_created_notification(license)
      puts "NOTIFICATION: New subscription created for license #{license.license_key}"
    end

    def send_subscription_canceled_notification(license)
      puts "NOTIFICATION: Subscription canceled for license #{license.license_key}"
    end

    def send_subscription_paused_notification(license)
      puts "NOTIFICATION: Subscription paused for license #{license.license_key}"
    end

    def send_subscription_resumed_notification(license)
      puts "NOTIFICATION: Subscription resumed for license #{license.license_key}"
    end

    def send_subscription_updated_notification(license, previous_status, new_status)
      puts "NOTIFICATION: Subscription updated for license #{license.license_key} - Status: #{previous_status} -> #{new_status}"
    end

    def send_trial_ending_notification(license, stripe_subscription)
      days_remaining = ((stripe_subscription.trial_end - Time.now.to_i) / 86_400).ceil
      puts "NOTIFICATION: Trial ending soon for license #{license.license_key} - #{days_remaining} days remaining"
    end

    # Dispute-related notifications
    def send_dispute_created_notification(license, dispute)
      puts "NOTIFICATION: Dispute created for license #{license.license_key} - Reason: #{dispute.reason} - Amount: $#{dispute.amount / 100.0}"
    end

    def send_dispute_won_notification(license, _dispute)
      puts "NOTIFICATION: Dispute won for license #{license.license_key} - License reactivated"
    end

    def send_dispute_lost_notification(license, _dispute)
      puts "NOTIFICATION: Dispute lost for license #{license.license_key} - License revoked"
    end

    # Payment-related notifications
    def send_payment_failed_notification(license, _invoice)
      puts "NOTIFICATION: Payment failed for license #{license.license_key} - Grace period until #{license.grace_period_ends_at}"
    end

    def send_payment_succeeded_notification(license, _invoice)
      puts "NOTIFICATION: Payment succeeded for license #{license.license_key} - License renewed until #{license.expires_at}"
    end
  end
end

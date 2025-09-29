# frozen_string_literal: true

require_relative 'base_event_handler'
require_relative 'license_finder_service'
require_relative 'notification_service'

class Webhooks::Stripe::SubscriptionEventHandler < Webhooks::Stripe::BaseEventHandler
  class << self
    # Main entry point for subscription events
    def handle_event(event)
      return { success: true, message: "Webhook #{event.type} is disabled" } unless webhook_enabled?(event.type)

      case event.type
      when 'customer.subscription.created'
        handle_subscription_created(event)
      when 'customer.subscription.deleted'
        handle_subscription_deleted(event)
      when 'customer.subscription.paused'
        handle_subscription_paused(event)
      when 'customer.subscription.resumed'
        handle_subscription_resumed(event)
      when 'customer.subscription.updated'
        handle_subscription_updated(event)
      when 'customer.subscription.trial_will_end'
        handle_subscription_trial_will_end(event)
      when 'invoice.payment_failed'
        handle_invoice_payment_failed(event)
      when 'invoice.payment_succeeded'
        handle_invoice_payment_succeeded(event)
      else
        { success: true, message: "Unhandled subscription event type: #{event.type}" }
      end
    end

    private

    # Handle subscription creation (used when customer subscribes to new product)
    def handle_subscription_created(event)
      stripe_subscription = event.data.object

      # Find license by customer email or subscription metadata
      license = LicenseFinderService.find_license_for_subscription(stripe_subscription)
      return { success: false, error: 'License not found for subscription' } unless license

      DB.transaction do
        # Create or update local subscription with Stripe details
        if license.subscription
          period_start = stripe_subscription['current_period_start'] ? Time.at(stripe_subscription['current_period_start']) : Time.now
          period_end = stripe_subscription['current_period_end'] ? Time.at(stripe_subscription['current_period_end']) : (Time.now + (30 * 24 * 60 * 60)) # Default to 30 days from now

          license.subscription.update(
            external_subscription_id: stripe_subscription.id,
            status: map_stripe_status(stripe_subscription.status),
            current_period_start: period_start,
            current_period_end: period_end,
            auto_renew: true
          )
        else
          # Create new subscription record
          license.create_subscription_from_product!
          license.subscription.update(external_subscription_id: stripe_subscription.id)
        end

        # Activate license
        license.reactivate! unless license.active?

        log_license_event(license, 'subscription_created', {
          subscription_id: stripe_subscription.id,
        })

        # Send welcome notification
        NotificationService.send_subscription_created_notification(license)
      end

      { success: true, message: 'Subscription created and license activated' }
    end

    # Handle subscription deletion/cancellation (cancel recurring license)
    def handle_subscription_deleted(event)
      stripe_subscription = event.data.object

      subscription = find_subscription_by_external_id(stripe_subscription.id)
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Cancel local subscription
        subscription.cancel!

        # Revoke the license immediately when subscription is canceled
        license = subscription.license
        license.revoke!

        log_license_event(license, 'revoked_subscription_deleted', {
          subscription_id: stripe_subscription.id,
        })

        # Send cancellation notification
        NotificationService.send_subscription_canceled_notification(license)
      end

      { success: true, message: 'Subscription canceled and license revoked' }
    end

    # Handle subscription paused (suspend license)
    def handle_subscription_paused(event)
      stripe_subscription = event.data.object

      subscription = find_subscription_by_external_id(stripe_subscription.id)
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Update subscription status
        subscription.update(status: 'paused')

        # Suspend the license
        license = subscription.license
        license.suspend!

        log_license_event(license, 'suspended_subscription_paused', {
          subscription_id: stripe_subscription.id,
        })

        # Send suspension notification
        NotificationService.send_subscription_paused_notification(license)
      end

      { success: true, message: 'Subscription paused and license suspended' }
    end

    # Handle subscription resumed (un-suspend license and capture payment if required)
    def handle_subscription_resumed(event)
      stripe_subscription = event.data.object

      subscription = find_subscription_by_external_id(stripe_subscription.id)
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Update subscription status
        subscription.update(
          status: map_stripe_status(stripe_subscription.status),
          current_period_start: Time.at(stripe_subscription.current_period_start),
          current_period_end: Time.at(stripe_subscription.current_period_end)
        )

        # Reactivate the license
        license = subscription.license
        license.reactivate!

        # Update license expiration based on new period
        license.update(expires_at: Time.at(stripe_subscription.current_period_end))

        log_license_event(license, 'reactivated_subscription_resumed', {
          subscription_id: stripe_subscription.id,
        })

        # Send reactivation notification
        NotificationService.send_subscription_resumed_notification(license)
      end

      { success: true, message: 'Subscription resumed and license reactivated' }
    end

    # Handle subscription updated (billing changes, status updates)
    def handle_subscription_updated(event)
      stripe_subscription = event.data.object

      subscription = find_subscription_by_external_id(stripe_subscription.id)
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Get previous values for comparison
        previous_status = subscription.status
        previous_period_end = subscription.current_period_end

        # Update subscription with new information
        period_start = stripe_subscription['current_period_start'] ? Time.at(stripe_subscription['current_period_start']) : subscription.current_period_start
        period_end = stripe_subscription['current_period_end'] ? Time.at(stripe_subscription['current_period_end']) : subscription.current_period_end

        subscription.update(
          status: map_stripe_status(stripe_subscription.status),
          current_period_start: period_start,
          current_period_end: period_end
        )

        license = subscription.license

        # Handle status changes
        if previous_status != subscription.status
          case subscription.status
          when 'active'
            license.reactivate! unless license.active?
          when 'past_due'
            # Enter grace period for past due subscriptions
            license.enter_grace_period! if license.active?
          when 'canceled'
            license.revoke!
          end
        end

        # Handle period extensions (billing cycle updates)
        if previous_period_end != subscription.current_period_end
          license.update(expires_at: subscription.current_period_end)
        end

        log_license_event(license, 'subscription_updated', {
          subscription_id: stripe_subscription.id,
          status_change: "#{previous_status} -> #{subscription.status}",
          period_change: previous_period_end != subscription.current_period_end,
        })

        # Send update notification if significant changes occurred
        NotificationService.send_subscription_updated_notification(license, previous_status, subscription.status)
      end

      { success: true, message: 'Subscription updated and license status synchronized' }
    end

    # Handle trial ending soon notification
    def handle_subscription_trial_will_end(event)
      stripe_subscription = event.data.object

      subscription = find_subscription_by_external_id(stripe_subscription.id)
      return { success: false, error: 'Subscription not found locally' } unless subscription

      license = subscription.license

      # Send trial ending notification
      NotificationService.send_trial_ending_notification(license, stripe_subscription)

      log_license_event(license, 'trial_ending_notification', {
        subscription_id: stripe_subscription.id,
        trial_end: Time.at(stripe_subscription.trial_end),
        days_remaining: ((stripe_subscription.trial_end - Time.now.to_i) / 86_400).ceil,
      })

      { success: true, message: 'Trial ending notification sent' }
    end

    def handle_invoice_payment_failed(event)
      invoice = event.data.object

      subscription = LicenseFinderService.find_subscription_by_invoice(invoice)
      return { success: false, error: 'Subscription not found for failed invoice' } unless subscription

      license = subscription.license

      DB.transaction do
        # Update subscription status
        subscription.update(
          status: 'past_due',
          last_payment_attempt: Time.now
        )

        # Put license in grace period
        grace_period_days = 7 # Configurable
        license.enter_grace_period!(grace_period_days)

        log_license_event(license, 'invoice_payment_failed', {
          invoice_id: invoice.id,
          subscription_id: invoice.subscription,
          amount: invoice.amount_due / 100.0,
          attempt_count: invoice.attempt_count,
          grace_period_ends: license.grace_period_ends_at,
        })

        NotificationService.send_payment_failed_notification(license, invoice)
      end

      { success: true, message: 'Invoice payment failed - license in grace period' }
    end

    def handle_invoice_payment_succeeded(event)
      invoice = event.data.object

      subscription = LicenseFinderService.find_subscription_by_invoice(invoice)
      return { success: false, error: 'Subscription not found for successful invoice' } unless subscription

      license = subscription.license

      DB.transaction do
        # Update subscription status
        subscription.update(
          status: 'active',
          last_payment_at: Time.now,
          current_period_start: Time.at(invoice.period_start),
          current_period_end: Time.at(invoice.period_end)
        )

        # Ensure license is active and extend expiration
        license.reactivate! unless license.active?
        license.update(
          expires_at: Time.at(invoice.period_end),
          grace_period_ends_at: nil # Clear any grace period
        )

        # Create billing history record
        create_billing_history_record(subscription, invoice, 'paid')

        log_license_event(license, 'invoice_payment_succeeded', {
          invoice_id: invoice.id,
          subscription_id: invoice.subscription,
          amount: invoice.amount_paid / 100.0,
          period_end: Time.at(invoice.period_end),
        })

        NotificationService.send_payment_succeeded_notification(license, invoice)
      end

      { success: true, message: 'Invoice payment succeeded - license renewed' }
    end

    def create_billing_history_record(subscription, invoice, status)
      SubscriptionBillingHistory.create(
        subscription_id: subscription.id,
        billing_period_start: Time.at(invoice.period_start),
        billing_period_end: Time.at(invoice.period_end),
        amount: invoice.amount_paid / 100.0, # Convert from cents
        currency: invoice.currency,
        status: status,
        external_invoice_id: invoice.id,
        paid_at: status == 'paid' ? Time.now : nil,
        failed_at: status == 'failed' ? Time.now : nil
      )
    end
  end
end

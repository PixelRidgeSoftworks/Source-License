# frozen_string_literal: true

# Source-License: PayPal Webhook Handler
# Handles PayPal subscription webhooks for automatic license management

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require_relative '../logging/payment_logger'

# Define the Webhooks namespace hierarchy first
module Webhooks::Paypal
end

class Webhooks::PaypalWebhookHandler
  class << self
    # Process incoming PayPal webhook
    def handle_webhook(payload, headers)
      # Verify webhook signature
      return { success: false, error: 'Invalid signature' } unless verify_webhook_signature(payload, headers)

      # Parse the webhook event
      event = JSON.parse(payload)

      # Log webhook event
      log_webhook_event(event)

      # Process the event based on type
      result = process_webhook_event(event)

      # Log processing result
      log_webhook_result(event, result)

      result
    rescue JSON::ParserError
      { success: false, error: 'Invalid JSON payload' }
    rescue StandardError => e
      error_result = { success: false, error: e.message }
      log_webhook_error(event, e)
      error_result
    end

    private

    # Verify webhook signature for security
    def verify_webhook_signature(payload, headers)
      # Use payments layer verification which calls PayPal verify-webhook-signature API
      valid = Payments::PaypalProcessor.verify_webhook_signature(payload, headers)

      # Add simple replay protection by persisting the transmission id
      transmission_id = headers['PAYPAL-TRANSMISSION-ID']

      return false unless transmission_id && valid

      processed_dir = File.join(ENV['TMP_DIR'] || 'tmp', 'webhooks', 'paypal')
      FileUtils.mkdir_p(processed_dir)

      processed_flag = File.join(processed_dir, transmission_id)
      if File.exist?(processed_flag)
        PaymentLogger.log_security_event('webhook_replay_detected', { provider: 'paypal', transmission_id: transmission_id })
        return false
      end

      # Mark as processed (durable for simple replay protection)
      File.write(processed_flag, Time.now.iso8601)

      true
    rescue StandardError => e
      PaymentLogger.log_security_event('webhook_verify_error', { provider: 'paypal', error: e.message })
      false
    end

    # Process different types of webhook events
    def process_webhook_event(event)
      event_type = event['event_type']

      # Check if webhook processing is enabled for this event type
      return { success: true, message: "Webhook #{event_type} is disabled" } unless webhook_enabled?(event_type)

      case event_type
      when 'PAYMENT.SALE.COMPLETED'
        handle_payment_completed(event)
      when 'PAYMENT.SALE.DENIED'
        handle_payment_denied(event)
      when 'PAYMENT.SALE.REFUNDED'
        handle_payment_refunded(event)
      when 'BILLING.SUBSCRIPTION.CREATED'
        handle_subscription_created(event)
      when 'BILLING.SUBSCRIPTION.ACTIVATED'
        handle_subscription_activated(event)
      when 'BILLING.SUBSCRIPTION.CANCELLED'
        handle_subscription_cancelled(event)
      when 'BILLING.SUBSCRIPTION.SUSPENDED'
        handle_subscription_suspended(event)
      when 'BILLING.SUBSCRIPTION.PAYMENT.FAILED'
        handle_subscription_payment_failed(event)
      else
        # Log unhandled events but don't fail
        { success: true, message: "Unhandled event type: #{event_type}" }
      end
    end

    # Handle successful payments
    def handle_payment_completed(event)
      payment = event['resource']

      # Find associated license by custom ID or payer email
      license = find_license_for_payment(payment)
      return { success: false, error: 'License not found for payment' } unless license

      DB.transaction do
        # If this is a subscription renewal payment
        if license.subscription_based? && license.subscription
          # Extend the license for the next billing period
          product = license.product
          if product&.license_duration_days
            license.extend!(product.license_duration_days)
            license.subscription.update(
              status: 'active',
              last_payment_at: Time.now
            )
            log_license_event(license, 'renewed_via_payment', {
              payment_id: payment['id'],
              amount: payment['amount']['total'],
              currency: payment['amount']['currency'],
            })
          end
        elsif license.revoked? || license.suspended?
          # For one-time purchases, ensure license is active
          license.reactivate!
          log_license_event(license, 'issued_via_payment', {
            payment_id: payment['id'],
            amount: payment['amount']['total'],
            currency: payment['amount']['currency'],
          })
        end

        # Send success notification
        send_payment_success_notification(license, payment)
      end

      { success: true, message: 'Payment success processed - license extended/renewed/issued' }
    end

    # Handle denied payments
    def handle_payment_denied(event)
      payment = event['resource']

      # Find associated license
      license = find_license_for_payment(payment)
      return { success: false, error: 'License not found for payment' } unless license

      # Send warning notification to user
      send_payment_failed_notification(license, payment)

      log_license_event(license, 'payment_denied_warning', {
        payment_id: payment['id'],
        failure_reason: payment['reason_code'],
      })

      { success: true, message: 'Payment denial notification sent' }
    end

    # Handle refunded payments
    def handle_payment_refunded(event)
      refund = event['resource']

      # Find the original sale from the refund
      sale_id = refund['sale_id']
      license = find_license_by_transaction_id(sale_id)
      return { success: false, error: 'License not found for refund' } unless license

      DB.transaction do
        # Revoke the license due to refund
        license.revoke!

        # If it's a subscription, cancel it as well
        if license.subscription
          license.subscription.cancel!

          # Cancel the PayPal subscription to prevent future charges
          if license.subscription.external_subscription_id
            cancel_paypal_subscription(license.subscription.external_subscription_id)
          end
        end

        log_license_event(license, 'revoked_due_to_refund', {
          refund_id: refund['id'],
          sale_id: sale_id,
          refund_amount: refund['amount']['total'],
        })

        # Send revocation notification
        send_license_revoked_notification(license, 'refund')
      end

      { success: true, message: 'License revoked due to payment refund' }
    end

    # Handle subscription creation
    def handle_subscription_created(event)
      subscription_data = event['resource']

      # Find license by subscriber email or custom fields
      license = find_license_for_subscription(subscription_data)
      return { success: false, error: 'License not found for subscription' } unless license

      DB.transaction do
        # Create or update local subscription with PayPal details
        if license.subscription
          license.subscription.update(
            external_subscription_id: subscription_data['id'],
            status: map_paypal_status(subscription_data['status']),
            auto_renew: true
          )
        else
          # Create new subscription record
          license.create_subscription_from_product!
          license.subscription.update(external_subscription_id: subscription_data['id'])
        end

        log_license_event(license, 'subscription_created', {
          subscription_id: subscription_data['id'],
        })
      end

      { success: true, message: 'Subscription created' }
    end

    # Handle subscription activation
    def handle_subscription_activated(event)
      subscription_data = event['resource']

      subscription = find_subscription_by_external_id(subscription_data['id'])
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Update subscription status
        subscription.update(status: 'active')

        # Activate the license
        license = subscription.license
        license.reactivate! unless license.active?

        log_license_event(license, 'activated_subscription_activated', {
          subscription_id: subscription_data['id'],
        })

        # Send activation notification
        send_subscription_activated_notification(license)
      end

      { success: true, message: 'Subscription activated and license activated' }
    end

    # Handle subscription cancellation
    def handle_subscription_cancelled(event)
      subscription_data = event['resource']

      subscription = find_subscription_by_external_id(subscription_data['id'])
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Cancel local subscription
        subscription.cancel!

        # Revoke the license immediately when subscription is canceled
        license = subscription.license
        license.revoke!

        log_license_event(license, 'revoked_subscription_cancelled', {
          subscription_id: subscription_data['id'],
        })

        # Send cancellation notification
        send_subscription_canceled_notification(license)
      end

      { success: true, message: 'Subscription canceled and license revoked' }
    end

    # Handle subscription suspension
    def handle_subscription_suspended(event)
      subscription_data = event['resource']

      subscription = find_subscription_by_external_id(subscription_data['id'])
      return { success: false, error: 'Subscription not found locally' } unless subscription

      DB.transaction do
        # Update subscription status
        subscription.update(status: 'suspended')

        # Suspend the license
        license = subscription.license
        license.suspend!

        log_license_event(license, 'suspended_subscription_suspended', {
          subscription_id: subscription_data['id'],
        })

        # Send suspension notification
        send_subscription_suspended_notification(license)
      end

      { success: true, message: 'Subscription suspended and license suspended' }
    end

    # Handle subscription payment failures
    def handle_subscription_payment_failed(event)
      subscription_data = event['resource']

      subscription = find_subscription_by_external_id(subscription_data['id'])
      return { success: false, error: 'Subscription not found locally' } unless subscription

      # Send payment failure warning
      license = subscription.license
      send_subscription_payment_failed_notification(license, subscription_data)

      log_license_event(license, 'subscription_payment_failed', {
        subscription_id: subscription_data['id'],
      })

      { success: true, message: 'Subscription payment failure notification sent' }
    end

    # Helper methods

    def webhook_enabled?(event_type)
      # Check if webhook is enabled in settings (default: false)
      setting_key = "webhooks.paypal.#{event_type.downcase.tr('.', '_')}"
      SettingsManager.get(setting_key, false)
    end

    def find_subscription_by_external_id(external_id)
      Subscription.where(external_subscription_id: external_id).first
    end

    def find_license_for_payment(payment)
      # Try multiple methods to find the license for this payment

      # Method 1: Check custom ID for order ID
      if payment['custom']
        order = Order[payment['custom']]
        return order&.licenses&.first if order
      end

      # Method 2: Find by payer email
      payer_email = payment.dig('payer', 'payer_info', 'email')
      if payer_email
        license = License.where(customer_email: payer_email).first
        return license if license
      end

      # Method 3: Find by transaction ID in orders
      if payment['parent_payment']
        order = Order.where(transaction_id: payment['parent_payment']).first
        return order&.licenses&.first if order
      end

      nil
    end

    def find_license_by_transaction_id(transaction_id)
      order = Order.where(transaction_id: transaction_id).first
      order&.licenses&.first
    end

    def find_license_for_subscription(subscription_data)
      # Find license by subscriber email
      subscriber_email = subscription_data.dig('subscriber', 'email_address')
      return nil unless subscriber_email

      License.where(customer_email: subscriber_email).first
    end

    def map_paypal_status(paypal_status)
      case paypal_status.downcase
      when 'cancelled', 'canceled'
        'canceled'
      when 'suspended'
        'suspended'
      else
        'active'
      end
    end

    def cancel_paypal_subscription(subscription_id)
      # This would make an API call to PayPal to cancel the subscription
      # Implementation depends on your PayPal integration
      puts "Would cancel PayPal subscription: #{subscription_id}"
    end

    # Logging methods

    def log_webhook_event(event)
      PaymentLogger.log_webhook_event('paypal', event['event_type'], event['id'], {
        create_time: event['create_time'],
        resource_type: event['resource_type'],
      })
    end

    def log_webhook_result(event, result)
      status = result[:success] ? 'webhook_processed' : 'webhook_failed'
      PaymentLogger.log_webhook_event('paypal', status, event['id'], {
        event_type: event['event_type'],
        message: result[:message] || result[:error],
      })
    end

    def log_webhook_error(event, error)
      PaymentLogger.log_security_event('webhook_processing_error', {
        provider: 'paypal',
        event_type: event&.dig('event_type'),
        event_id: event&.dig('id'),
        error_class: error.class.name,
        error_message: error.message,
      })
    end

    def log_license_event(license, event_type, data = {})
      PaymentLogger.log_license_event(license, event_type, data)
    end

    # Notification methods (stubs - implement with your email system)

    def send_payment_success_notification(license, payment)
      amount = payment['amount']['total']
      puts "NOTIFICATION: Payment successful for license #{license.license_key} - Amount: #{amount}"
    end

    def send_payment_failed_notification(license, payment)
      puts "NOTIFICATION: Payment failed for license #{license.license_key} - Reason: #{payment['reason_code']}"
    end

    def send_license_revoked_notification(license, reason)
      puts "NOTIFICATION: License #{license.license_key} revoked due to #{reason}"
    end

    def send_subscription_activated_notification(license)
      puts "NOTIFICATION: Subscription activated for license #{license.license_key}"
    end

    def send_subscription_canceled_notification(license)
      puts "NOTIFICATION: Subscription canceled for license #{license.license_key}"
    end

    def send_subscription_suspended_notification(license)
      puts "NOTIFICATION: Subscription suspended for license #{license.license_key}"
    end

    def send_subscription_payment_failed_notification(license, _subscription_data)
      puts "NOTIFICATION: Subscription payment failed for license #{license.license_key}"
    end
  end
end

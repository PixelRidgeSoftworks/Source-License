# frozen_string_literal: true

# Source-License: Stripe Webhook Handler
# Handles Stripe subscription webhooks for automatic license management
# Refactored to use modular event handlers for better maintainability

require 'stripe'
require 'json'
require_relative '../logging/payment_logger'
require_relative '../models'
require_relative '../settings_manager'
require_relative 'stripe/event_dispatcher'

module Webhooks
end

class Webhooks::StripeWebhookHandler
  class << self
    # Process incoming Stripe webhook
    def handle_webhook(payload, signature)
      # Verify webhook signature
      event = verify_webhook_signature(payload, signature)
      return { success: false, error: 'Invalid signature' } unless event

      # Log webhook event
      log_webhook_event(event)

      # Process the event using the new modular dispatcher
      result = process_webhook_event(event)

      # Log processing result
      log_webhook_result(event, result)

      result
    rescue StandardError => e
      error_result = { success: false, error: e.message }
      log_webhook_error(event, e)
      error_result
    end

    private

    # Verify webhook signature for security
    def verify_webhook_signature(payload, signature)
      endpoint_secret = ENV.fetch('STRIPE_WEBHOOK_SECRET', nil)
      raise 'Stripe webhook secret not configured' unless endpoint_secret

      Stripe::Webhook.construct_event(payload, signature, endpoint_secret)
    rescue Stripe::SignatureVerificationError => e
      puts "Webhook signature verification failed: #{e.message}"
      nil
    end

    # Process different types of webhook events using the modular dispatcher
    def process_webhook_event(event)
      Webhooks::Stripe::EventDispatcher.dispatch(event)
    end

    # Logging methods
    def log_webhook_event(event)
      PaymentLogger.log_webhook_event('stripe', event.type, event.id, {
        api_version: event.api_version,
        livemode: event.livemode,
        pending_webhooks: event.pending_webhooks,
      })
    end

    def log_webhook_result(event, result)
      status = result[:success] ? 'webhook_processed' : 'webhook_failed'
      PaymentLogger.log_webhook_event('stripe', status, event.id, {
        event_type: event.type,
        message: result[:message] || result[:error],
      })
    end

    def log_webhook_error(event, error)
      PaymentLogger.log_security_event('webhook_processing_error', {
        provider: 'stripe',
        event_type: event&.type,
        event_id: event&.id,
        error_class: error.class.name,
        error_message: error.message,
      })
    end
  end
end

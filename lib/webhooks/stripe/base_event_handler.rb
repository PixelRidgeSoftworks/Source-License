# frozen_string_literal: true

# Base class for Stripe webhook event handlers
class Webhooks::Stripe::BaseEventHandler
  class << self
    # Check if webhook processing is enabled for this specific event type
    def webhook_enabled?(event_type)
      setting_key = "webhooks.stripe.#{event_type.tr('.', '_')}"
      SettingsManager.get(setting_key)
    end

    # Find subscription by external Stripe ID
    def find_subscription_by_external_id(external_id)
      Subscription.where(external_subscription_id: external_id).first
    end

    # Map Stripe subscription status to local status
    def map_stripe_status(stripe_status)
      case stripe_status
      when 'past_due'
        'past_due'
      when 'canceled', 'cancelled'
        'canceled'
      when 'unpaid'
        'unpaid'
      else
        'active'
      end
    end

    # Logging helper methods
    def log_license_event(license, event_type, data = {})
      PaymentLogger.log_license_event(license, event_type, data)
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

    private

    # Template method - subclasses should implement this
    def process_event(event)
      raise NotImplementedError, 'Subclasses must implement process_event'
    end

    # Common error handling wrapper
    def handle_with_error_logging(event)
      result = process_event(event)
      log_license_event(nil, "#{event.type}_processed", result)
      result
    rescue StandardError => e
      log_webhook_error(event, e)
      { success: false, error: e.message }
    end
  end
end

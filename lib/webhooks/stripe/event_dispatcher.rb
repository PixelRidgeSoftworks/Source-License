# frozen_string_literal: true

require_relative 'payment_event_handler'
require_relative 'subscription_event_handler'
require_relative 'customer_dispute_event_handler'

class Webhooks::Stripe::EventDispatcher
  # Event type to handler mapping
  EVENT_HANDLERS = {
    # Payment events
    'payment_intent.created' => Webhooks::Stripe::PaymentEventHandler,
    'payment_intent.succeeded' => Webhooks::Stripe::PaymentEventHandler,
    'charge.succeeded' => Webhooks::Stripe::PaymentEventHandler,
    'charge.failed' => Webhooks::Stripe::PaymentEventHandler,
    'charge.refunded' => Webhooks::Stripe::PaymentEventHandler,
    'payment_method.attached' => Webhooks::Stripe::PaymentEventHandler,

    # Subscription events
    'customer.subscription.created' => Webhooks::Stripe::SubscriptionEventHandler,
    'customer.subscription.deleted' => Webhooks::Stripe::SubscriptionEventHandler,
    'customer.subscription.paused' => Webhooks::Stripe::SubscriptionEventHandler,
    'customer.subscription.resumed' => Webhooks::Stripe::SubscriptionEventHandler,
    'customer.subscription.updated' => Webhooks::Stripe::SubscriptionEventHandler,
    'customer.subscription.trial_will_end' => Webhooks::Stripe::SubscriptionEventHandler,
    'invoice.payment_failed' => Webhooks::Stripe::SubscriptionEventHandler,
    'invoice.payment_succeeded' => Webhooks::Stripe::SubscriptionEventHandler,

    # Customer and dispute events
    'customer.updated' => Webhooks::Stripe::CustomerDisputeEventHandler,
    'charge.dispute.created' => Webhooks::Stripe::CustomerDisputeEventHandler,
    'charge.dispute.updated' => Webhooks::Stripe::CustomerDisputeEventHandler,
    'charge.dispute.closed' => Webhooks::Stripe::CustomerDisputeEventHandler,
  }.freeze

  class << self
    # Dispatch event to appropriate handler
    def dispatch(event)
      handler_class = EVENT_HANDLERS[event.type]

      if handler_class
        handler_class.handle_event(event)
      else
        # Log unhandled events but don't fail
        { success: true, message: "Unhandled event type: #{event.type}" }
      end
    end

    # Get list of supported event types
    def supported_event_types
      EVENT_HANDLERS.keys
    end

    # Check if event type is supported
    def supports_event_type?(event_type)
      EVENT_HANDLERS.key?(event_type)
    end
  end
end

# frozen_string_literal: true

require_relative 'payment_event_handler'
require_relative 'subscription_event_handler'
require_relative 'customer_dispute_event_handler'

class Webhooks::Stripe::EventDispatcher
  # Event type to handler mapping
  EVENT_HANDLERS = {
    # Payment events
    'payment_intent.created' => PaymentEventHandler,
    'payment_intent.succeeded' => PaymentEventHandler,
    'charge.succeeded' => PaymentEventHandler,
    'charge.failed' => PaymentEventHandler,
    'charge.refunded' => PaymentEventHandler,
    'payment_method.attached' => PaymentEventHandler,

    # Subscription events
    'customer.subscription.created' => SubscriptionEventHandler,
    'customer.subscription.deleted' => SubscriptionEventHandler,
    'customer.subscription.paused' => SubscriptionEventHandler,
    'customer.subscription.resumed' => SubscriptionEventHandler,
    'customer.subscription.updated' => SubscriptionEventHandler,
    'customer.subscription.trial_will_end' => SubscriptionEventHandler,
    'invoice.payment_failed' => SubscriptionEventHandler,
    'invoice.payment_succeeded' => SubscriptionEventHandler,

    # Customer and dispute events
    'customer.updated' => CustomerDisputeEventHandler,
    'charge.dispute.created' => CustomerDisputeEventHandler,
    'charge.dispute.updated' => CustomerDisputeEventHandler,
    'charge.dispute.closed' => CustomerDisputeEventHandler,
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

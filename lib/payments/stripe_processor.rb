# frozen_string_literal: true

# Source-License: Stripe Payment Processor
# Handles Stripe payment processing with enhanced security

# TODO: Implement logging for all payment actions
# TODO: Add support for 3D Secure authentication flows (If not already handled)
# TODO: Test with Mastercard
# TODO: Add support for Apple Pay and Google Pay via Stripe
# TODO: Implement webhook abstraction layer so users can decide what to do on events

begin
  require 'stripe'
rescue LoadError
  # Stripe gem not available in this environment (tests). Provide a minimal stub so
  # the rest of the application can operate without loading the real gem.

  module Stripe
    class StripeError < StandardError; end
    class CardError < StripeError; end
    class RateLimitError < StripeError; end
    class InvalidRequestError < StripeError; end
    class AuthenticationError < StripeError; end
    class APIConnectionError < StripeError; end

    # Lightweight Struct-based stubs instead of OpenStruct to avoid style offense
    PaymentIntentStruct = Struct.new(:id, :client_secret, :status)
    class PaymentIntent
      def self.create(*)
        PaymentIntentStruct.new('pi_test', 'cs_test', 'succeeded')
      end

      def self.retrieve(id)
        PaymentIntentStruct.new(id, 'cs_test', 'succeeded')
      end
    end

    RefundStruct = Struct.new(:amount, :id)
    class Refund
      def self.create(*)
        RefundStruct.new(0, 're_test')
      end
    end

    PriceStruct = Struct.new(:id)
    class Price
      def self.create(*)
        PriceStruct.new('price_test')
      end
    end

    SubscriptionStruct = Struct.new(:id)
    class Subscription
      def self.create(*)
        SubscriptionStruct.new('sub_test')
      end

      def self.update(id, _params)
        SubscriptionStruct.new(id)
      end

      def self.delete(id)
        SubscriptionStruct.new(id)
      end
    end

    def self.api_key=(_); end
    def self.api_key = nil
  end
end
require_relative 'base_payment_processor'

class Payments::StripeProcessor < Payments::BasePaymentProcessor
  class << self
    def process_payment(order, payment_data = {})
      setup_stripe

      begin
        # Generate idempotency key for this payment
        idempotency_key = payment_data[:idempotency_key] || generate_payment_idempotency_key(order)

        # Create payment intent with enhanced security
        intent_params = {
          amount: (order.amount * 100).to_i, # Convert to cents
          currency: order.currency.downcase,
          payment_method: payment_data[:payment_method_id],
          confirmation_method: 'manual',
          confirm: true,
          metadata: {
            order_id: order.id,
            customer_email: order.email,
            environment: ENV['APP_ENV'] || 'development',
            created_at: Time.now.iso8601,
          },
        }

        # Add billing details with postal code support for international customers
        if payment_data[:billing_details]
          billing_details = payment_data[:billing_details]
          intent_params[:payment_method_data] = {
            type: 'card',
            card: { token: payment_data[:payment_method_id] },
            billing_details: {
              name: billing_details[:name],
              email: billing_details[:email],
              address: {
                line1: billing_details[:address_line1],
                line2: billing_details[:address_line2],
                city: billing_details[:city],
                state: billing_details[:state],
                postal_code: billing_details[:postal_code], # Support both ZIP codes and postal codes
                country: billing_details[:country] || 'US',
              },
            },
          }
        end

        # Add idempotency key to prevent duplicate charges
        intent = Stripe::PaymentIntent.create(intent_params, {
          idempotency_key: idempotency_key,
        })

        # Update order with payment intent ID
        order.update(payment_intent_id: intent.id)

        # Handle the response based on intent status
        handle_stripe_intent_response(intent, order)
      rescue Stripe::CardError => e
        # Card was declined
        order.update(status: 'failed')
        {
          success: false,
          error: e.message,
          decline_code: e.decline_code,
        }
      rescue Stripe::RateLimitError
        # Too many requests
        {
          success: false,
          error: 'Rate limit exceeded. Please try again later.',
        }
      rescue Stripe::InvalidRequestError
        # Invalid parameters
        {
          success: false,
          error: 'Invalid payment request. Please check your information.',
        }
      rescue Stripe::AuthenticationError
        # Authentication error
        {
          success: false,
          error: 'Payment processing authentication failed.',
        }
      rescue Stripe::APIConnectionError
        # Network communication error
        {
          success: false,
          error: 'Payment processing temporarily unavailable. Please try again.',
        }
      rescue Stripe::StripeError
        # Generic error
        {
          success: false,
          error: 'Payment processing failed. Please try again.',
        }
      end
    end

    def create_payment_intent(order)
      setup_stripe

      # Generate idempotency key
      idempotency_key = generate_payment_idempotency_key(order)

      intent_params = {
        amount: (order.amount * 100).to_i,
        currency: order.currency.downcase,
        metadata: {
          order_id: order.id,
          customer_email: order.email,
          environment: ENV['APP_ENV'] || 'development',
          created_at: Time.now.iso8601,
        },
      }

      intent = Stripe::PaymentIntent.create(intent_params, {
        idempotency_key: idempotency_key,
      })

      order.update(payment_intent_id: intent.id)

      {
        client_secret: intent.client_secret,
        publishable_key: ENV.fetch('STRIPE_PUBLISHABLE_KEY', nil),
      }
    end

    def verify_payment(payment_intent_id)
      setup_stripe

      begin
        intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
        intent.status == 'succeeded'
      rescue Stripe::StripeError
        false
      end
    end

    def process_refund(order, amount, reason)
      setup_stripe

      begin
        # Map custom reasons to valid Stripe reasons
        stripe_reason = map_refund_reason(reason)

        refund = Stripe::Refund.create({
          payment_intent: order.payment_intent_id,
          amount: (amount * 100).to_i,
          reason: stripe_reason,
          metadata: {
            order_id: order.id,
            refund_reason: reason || 'Unknown',
            original_reason: reason,
          },
        })

        # Update order status
        order.update(status: 'refunded') if refund.amount == (order.amount * 100).to_i

        {
          success: true,
          refund_id: refund.id,
          amount: refund.amount / 100.0,
        }
      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
        }
      end
    end

    # Subscription management methods
    def create_subscription(license)
      setup_stripe

      product = license.product

      # Create or retrieve Stripe product
      stripe_product = create_or_get_stripe_product(product)

      # Create price for the product
      price = Stripe::Price.create({
        unit_amount: (product.price * 100).to_i,
        currency: 'usd',
        recurring: {
          interval: 'month', # Could be made configurable
          interval_count: 1,
        },
        product: stripe_product.id,
      })

      # Create subscription
      subscription = Stripe::Subscription.create({
        customer: get_or_create_stripe_customer(license.customer_email),
        items: [{ price: price.id }],
        metadata: {
          license_id: license.id,
          product_name: product.name,
        },
      })

      # Update license subscription record
      license.subscription.update(external_subscription_id: subscription.id)

      subscription.id
    end

    def cancel_subscription(subscription_id, at_period_end: false)
      setup_stripe

      begin
        stripe_sub = Stripe::Subscription.update(subscription_id, {
          cancel_at_period_end: at_period_end,
        })

        # If immediate cancellation, actually cancel it
        stripe_sub = Stripe::Subscription.delete(subscription_id) unless at_period_end

        stripe_sub
      rescue Stripe::StripeError
        false
      end
    end

    def pause_subscription(subscription_id)
      setup_stripe

      begin
        Stripe::Subscription.update(subscription_id, {
          pause_collection: {
            behavior: 'keep_as_draft',
          },
        })
      rescue Stripe::StripeError
        false
      end
    end

    def resume_subscription(subscription_id)
      setup_stripe

      begin
        Stripe::Subscription.update(subscription_id, {
          pause_collection: '', # Empty string removes the pause
        })
      rescue Stripe::StripeError
        false
      end
    end

    def update_subscription_payment_method(subscription_id, payment_method_id)
      setup_stripe

      begin
        # First attach payment method to customer if needed
        subscription = Stripe::Subscription.retrieve(subscription_id)

        Stripe::PaymentMethod.attach(payment_method_id, {
          customer: subscription.customer,
        })

        # Update subscription's default payment method
        Stripe::Subscription.update(subscription_id, {
          default_payment_method: payment_method_id,
        })

        true
      rescue Stripe::StripeError
        false
      end
    end

    def find_or_create_customer(email, name = nil)
      setup_stripe

      begin
        # Try to find existing customer by email
        customers = Stripe::Customer.list(email: email, limit: 1)

        if customers.data.any?
          customers.data.first
        else
          # Create new customer
          Stripe::Customer.create({
            email: email,
            name: name,
            metadata: {
              created_by: 'source_license',
              created_at: Time.now.iso8601,
            },
          })
        end
      rescue Stripe::StripeError
        nil
      end
    end

    def create_customer_portal_session(customer_id, return_url)
      setup_stripe

      begin
        Stripe::BillingPortal::Session.create({
          customer: customer_id,
          return_url: return_url,
        })
      rescue Stripe::StripeError
        nil
      end
    end

    private

    def handle_stripe_intent_response(intent, order)
      case intent.status
      when 'succeeded'
        order.complete!
        {
          success: true,
          payment_intent_id: intent.id,
          status: 'completed',
        }
      when 'requires_action', 'requires_source_action'
        {
          success: false,
          requires_action: true,
          client_secret: intent.client_secret,
        }
      when 'requires_payment_method', 'requires_source'
        order.update(status: 'failed')
        {
          success: false,
          error: 'Payment method was declined. Please try a different payment method.',
        }
      else
        order.update(status: 'failed')
        {
          success: false,
          error: 'Payment processing failed.',
        }
      end
    end

    def setup_stripe
      stripe_key = ENV.fetch('STRIPE_SECRET_KEY', nil)
      raise 'Stripe secret key not configured' unless stripe_key
      raise 'Invalid Stripe key format' unless stripe_key.start_with?('sk_')

      Stripe.api_key = stripe_key

      # Set API version for consistency
      Stripe.api_version = '2023-10-16'

      # Configure timeouts
      Stripe.open_timeout = 30
      Stripe.read_timeout = 80
    end

    def create_or_get_stripe_product(product)
      # In a real implementation, you might store Stripe product IDs
      # For now, create a new product each time
      Stripe::Product.create({
        name: product.name,
        description: product.description,
        metadata: {
          product_id: product.id,
        },
      })
    end

    def get_or_create_stripe_customer(email)
      # Try to find existing customer by email first
      customers = Stripe::Customer.list(email: email, limit: 1)

      return customers.data.first.id if customers.data.any?

      # Create new customer if none found
      customer = Stripe::Customer.create({
        email: email,
        metadata: {
          created_by: 'source_license',
          created_at: Time.now.iso8601,
        },
      })
      customer.id
    rescue Stripe::StripeError
      # Fallback: create customer without checking for duplicates
      customer = Stripe::Customer.create({ email: email })
      customer.id
    end

    # Map custom refund reasons to valid Stripe reasons
    def map_refund_reason(reason)
      return 'requested_by_customer' if reason.nil? || reason.empty?

      case reason.to_s.downcase
      when /duplicate|duplicated|double.*charge|charged.*twice/
        'duplicate'
      when /fraud|fraudulent|unauthorized|chargeback|dispute/
        'fraudulent'
      when /admin.*refund|admin.*initiated|bulk.*refund|customer.*request|requested|refund.*request/
        'requested_by_customer'
      end
    end
  end
end

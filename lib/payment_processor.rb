# frozen_string_literal: true

# Source-License: Payment Processor Facade
# Main entry point for payment processing that delegates to specific processors

require_relative 'payments/base_payment_processor'
require_relative 'payments/stripe_processor'
require_relative 'payments/paypal_processor'
require_relative 'logging/payment_logger'

class PaymentProcessor
  class << self
    # Process payment with specified provider
    def process_payment(order, payment_method, payment_data = {})
      # Validate input parameters
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)
      unless %w[stripe paypal].include?(payment_method.to_s.downcase)
        return { success: false, error: 'Invalid payment method' }
      end

      # Log payment attempt
      PaymentLogger.log_payment_event('payment_attempt', {
        order_id: order.id,
        payment_method: payment_method,
        amount: order.amount,
      })

      # Check for duplicate payments
      if payment_data[:idempotency_key]
        existing_payment = check_duplicate_payment(payment_data[:idempotency_key])
        if existing_payment
          PaymentLogger.log_security_event('duplicate_payment_prevented', {
            order_id: order.id,
            existing_order_id: existing_payment.id,
            payment_method: payment_method,
          })
          return { success: false, error: 'Duplicate payment detected' }
        end
      end

      # Validate order integrity
      unless validate_order_amount(order)
        PaymentLogger.log_security_event('order_validation_failed', {
          order_id: order.id,
          payment_method: payment_method,
        })
        return { success: false, error: 'Order validation failed' }
      end

      # Delegate to appropriate processor
      processor = get_processor(payment_method)
      processor.process_payment(order, payment_data)
    end

    # Create payment intent for client-side processing
    def create_payment_intent(order, payment_method)
      # Validate inputs
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)
      unless %w[stripe paypal].include?(payment_method.to_s.downcase)
        return { success: false, error: 'Invalid payment method' }
      end

      # Delegate to appropriate processor
      processor = get_processor(payment_method)
      processor.create_payment_intent(order)
    end

    # Verify payment completion with enhanced security
    def verify_payment(payment_id, payment_method)
      return false unless payment_id.is_a?(String) && !payment_id.empty?
      return false unless %w[stripe paypal].include?(payment_method.to_s.downcase)

      # Delegate to appropriate processor
      processor = get_processor(payment_method)
      processor.verify_payment(payment_id)
    end

    # Process refund with enhanced validation
    def process_refund(order, amount = nil, reason = nil)
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)

      amount ||= order.amount

      # Validate refund amount
      return { success: false, error: 'Invalid refund amount' } unless validate_refund_amount(order, amount)

      # Log refund attempt
      PaymentLogger.log_payment_event('refund_attempt', {
        order_id: order.id,
        amount: amount,
        reason: reason,
      })

      # Delegate to appropriate processor
      processor = get_processor(order.payment_method)
      processor.process_refund(order, amount, reason)
    end

    private

    # Get the appropriate payment processor class
    def get_processor(payment_method)
      case payment_method.to_s.downcase
      when 'stripe'
        Payments::StripeProcessor
      when 'paypal'
        Payments::PaypalProcessor
      else
        raise "Unsupported payment method: #{payment_method}"
      end
    end

    # Shared validation and utility methods
    def validate_order_amount(order)
      return false unless order.amount.is_a?(Numeric)
      return false if order.amount <= 0 || order.amount > 999_999.99

      # Validate amount matches order items
      calculated_total = order.order_items.sum { |item| item.price * item.quantity }
      (calculated_total - order.amount).abs < 0.01
    end

    def validate_refund_amount(order, amount)
      return false unless amount.is_a?(Numeric)
      return false if amount <= 0
      return false if amount > order.amount

      true
    end

    def check_duplicate_payment(idempotency_key)
      # Check if payment with this idempotency key already exists
      Order.where(idempotency_key: idempotency_key).first
    end

    # This method is now handled by PaymentLogger
    def log_payment_event(event_type, details = {})
      PaymentLogger.log_payment_event(event_type, details)
    end
  end
end

# Subscription management for recurring payments
class SubscriptionProcessor
  class << self
    # Create subscription for recurring payments
    def create_subscription(license, payment_method)
      processor = get_processor(payment_method)
      processor.create_subscription(license)
    end

    # Cancel subscription
    def cancel_subscription(subscription)
      payment_method = subscription.license.order.payment_method
      processor = get_processor(payment_method)
      processor.cancel_subscription(subscription)
    end

    # Handle subscription renewal
    def process_renewal(subscription)
      product = subscription.license.product

      # Extend the subscription period
      new_period_start = subscription.current_period_end
      new_period_end = new_period_start + (product.license_duration_days * 24 * 60 * 60)

      subscription.renew!(new_period_start, new_period_end)

      # Generate renewal notification
      send_renewal_notification(subscription)
    end

    private

    # Get the appropriate payment processor class
    def get_processor(payment_method)
      case payment_method.to_s.downcase
      when 'stripe'
        Payments::StripeProcessor
      when 'paypal'
        Payments::PaypalProcessor
      else
        raise "Unsupported payment method: #{payment_method}"
      end
    end

    def send_renewal_notification(subscription)
      # Send email notification about renewal
      # This would integrate with your email system
    end
  end
end

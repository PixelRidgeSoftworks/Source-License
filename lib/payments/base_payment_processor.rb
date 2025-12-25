# frozen_string_literal: true

# Source-License: Base Payment Processor
# Abstract base class for payment processors

require 'digest'
require 'securerandom'

module Payments
end

class Payments::BasePaymentProcessor
  class << self
    # Abstract methods that must be implemented by subclasses
    def process_payment(order, payment_data = {})
      raise NotImplementedError, "#{self} must implement process_payment"
    end

    def create_payment_intent(order)
      raise NotImplementedError, "#{self} must implement create_payment_intent"
    end

    def verify_payment(payment_id)
      raise NotImplementedError, "#{self} must implement verify_payment"
    end

    def process_refund(order, amount, reason)
      raise NotImplementedError, "#{self} must implement process_refund"
    end

    protected

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

    def generate_payment_idempotency_key(order)
      data = "#{order.id}:#{order.amount}:#{order.email}:#{Time.now.to_i / 300}" # 5-minute window
      Digest::SHA256.hexdigest(data)[0, 32]
    end

    def check_duplicate_payment(idempotency_key)
      # Check if payment with this idempotency key already exists
      Order.where(idempotency_key: idempotency_key).first
    end

    def log_payment_event(event_type, details = {})
      event_log = {
        timestamp: Time.now.iso8601,
        event_type: event_type,
        details: details,
      }

      # Log to payment log file or service
      puts "PAYMENT_EVENT: #{event_log.to_json}" # TODO: Remove this and handle logging in the specific processor
    end

    def base_url
      host = ENV['APP_HOST'] || 'localhost:4567'
      protocol = ENV['APP_ENV'] == 'production' ? 'https' : 'http'

      # Validate host format for security
      raise 'Invalid host configuration' unless host.match?(/^[a-zA-Z0-9.-]+(?::\d+)?$/)

      "#{protocol}://#{host}"
    end
  end
end

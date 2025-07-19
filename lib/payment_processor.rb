# frozen_string_literal: true

# Source-License: Payment Processor
# Handles Stripe and PayPal payment processing with enhanced security

require 'stripe'
require 'net/http'
require 'uri'
require 'json'
require 'digest'
require 'securerandom'

class PaymentProcessor
  class << self
    # Process payment with specified provider
    def process_payment(order, payment_method, payment_data = {})
      # Validate input parameters
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)
      return { success: false, error: 'Invalid payment method' } unless %w[stripe
                                                                           paypal].include?(payment_method.to_s.downcase)

      # Log payment attempt
      log_payment_event('payment_attempt', {
        order_id: order.id,
        payment_method: payment_method,
        amount: order.amount,
      })

      # Check for duplicate payments
      if payment_data[:idempotency_key]
        existing_payment = check_duplicate_payment(payment_data[:idempotency_key])
        if existing_payment
          log_payment_event('duplicate_payment_prevented', {
            order_id: order.id,
            existing_order_id: existing_payment.id,
          })
          return { success: false, error: 'Duplicate payment detected' }
        end
      end

      # Validate order integrity
      unless validate_order_amount(order)
        log_payment_event('order_validation_failed', { order_id: order.id })
        return { success: false, error: 'Order validation failed' }
      end

      case payment_method.to_s.downcase
      when 'stripe'
        process_stripe_payment(order, payment_data)
      when 'paypal'
        process_paypal_payment(order, payment_data)
      else
        raise "Unsupported payment method: #{payment_method}"
      end
    end

    # Create payment intent for client-side processing
    def create_payment_intent(order, payment_method)
      # Validate inputs
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)
      return { success: false, error: 'Invalid payment method' } unless %w[stripe
                                                                           paypal].include?(payment_method.to_s.downcase)

      # Generate idempotency key for this payment intent
      generate_payment_idempotency_key(order)

      case payment_method.to_s.downcase
      when 'stripe'
        create_stripe_payment_intent(order)
      when 'paypal'
        create_paypal_order(order)
      else
        raise "Unsupported payment method: #{payment_method}"
      end
    end

    # Verify payment completion with enhanced security
    def verify_payment(payment_id, payment_method)
      return false unless payment_id.is_a?(String) && !payment_id.empty?
      return false unless %w[stripe paypal].include?(payment_method.to_s.downcase)

      case payment_method.to_s.downcase
      when 'stripe'
        verify_stripe_payment(payment_id)
      when 'paypal'
        verify_paypal_payment(payment_id)
      else
        false
      end
    end

    # Process refund with enhanced validation
    def process_refund(order, amount = nil, reason = nil)
      return { success: false, error: 'Invalid order' } unless order.is_a?(Order)

      amount ||= order.amount

      # Validate refund amount
      return { success: false, error: 'Invalid refund amount' } unless validate_refund_amount(order, amount)

      # Log refund attempt
      log_payment_event('refund_attempt', {
        order_id: order.id,
        amount: amount,
        reason: reason,
      })

      case order.payment_method.to_s.downcase
      when 'stripe'
        process_stripe_refund(order, amount, reason)
      when 'paypal'
        process_paypal_refund(order, amount, reason)
      else
        raise "Unsupported payment method: #{order.payment_method}"
      end
    end

    private

    # ===== STRIPE PAYMENT PROCESSING =====

    def process_stripe_payment(order, payment_data)
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

    def create_stripe_payment_intent(order)
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

    def verify_stripe_payment(payment_intent_id)
      setup_stripe

      begin
        intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
        intent.status == 'succeeded'
      rescue Stripe::StripeError
        false
      end
    end

    def process_stripe_refund(order, amount, reason)
      setup_stripe

      begin
        refund = Stripe::Refund.create({
          payment_intent: order.payment_intent_id,
          amount: (amount * 100).to_i,
          reason: reason || 'requested_by_customer',
          metadata: {
            order_id: order.id,
            refund_reason: reason,
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

    # ===== PAYPAL PAYMENT PROCESSING =====

    def process_paypal_payment(order, payment_data)
      # Capture the PayPal order
      response = capture_paypal_order(payment_data[:order_id])

      if response['status'] == 'COMPLETED'
        order.update(
          status: 'completed',
          completed_at: Time.now,
          transaction_id: response['id']
        )

        {
          success: true,
          transaction_id: response['id'],
        }
      else
        order.update(status: 'failed')
        {
          success: false,
          error: 'PayPal payment was not completed',
        }
      end
    rescue StandardError
      order.update(status: 'failed')
      {
        success: false,
        error: 'PayPal payment processing failed',
      }
    end

    def create_paypal_order(order)
      access_token = paypal_access_token

      order_data = {
        intent: 'CAPTURE',
        purchase_units: [{
          amount: {
            currency_code: order.currency,
            value: format('%.2f', order.amount),
          },
          description: "Order ##{order.id}",
          custom_id: order.id.to_s,
        }],
        application_context: {
          return_url: "#{base_url}/success?order_id=#{order.id}",
          cancel_url: "#{base_url}/cart",
        },
      }

      response = make_paypal_request(
        'POST',
        '/v2/checkout/orders',
        order_data,
        access_token
      )

      raise 'Failed to create PayPal order' unless response['id']

      order.update(payment_intent_id: response['id'])

      # Find approval URL
      approval_url = response['links']&.find { |link| link['rel'] == 'approve' }&.dig('href')

      {
        order_id: response['id'],
        approval_url: approval_url,
      }
    end

    def verify_paypal_payment(order_id)
      access_token = paypal_access_token

      response = make_paypal_request(
        'GET',
        "/v2/checkout/orders/#{order_id}",
        nil,
        access_token
      )

      response['status'] == 'COMPLETED'
    rescue StandardError
      false
    end

    def process_paypal_refund(order, amount, reason)
      access_token = paypal_access_token

      # Get capture ID from the order
      order_details = make_paypal_request(
        'GET',
        "/v2/checkout/orders/#{order.payment_intent_id}",
        nil,
        access_token
      )

      capture_id = order_details.dig('purchase_units', 0, 'payments', 'captures', 0, 'id')
      return { success: false, error: 'Capture ID not found' } unless capture_id

      refund_data = {
        amount: {
          currency_code: order.currency,
          value: format('%.2f', amount),
        },
        note_to_payer: reason || 'Refund processed',
      }

      response = make_paypal_request(
        'POST',
        "/v2/payments/captures/#{capture_id}/refund",
        refund_data,
        access_token
      )

      if response['status'] == 'COMPLETED'
        order.update(status: 'refunded') if amount == order.amount

        {
          success: true,
          refund_id: response['id'],
          amount: amount,
        }
      else
        {
          success: false,
          error: 'PayPal refund failed',
        }
      end
    rescue StandardError
      {
        success: false,
        error: 'PayPal refund processing failed',
      }
    end

    def capture_paypal_order(order_id)
      access_token = paypal_access_token

      make_paypal_request(
        'POST',
        "/v2/checkout/orders/#{order_id}/capture",
        {},
        access_token
      )
    end

    def paypal_access_token
      client_id = ENV.fetch('PAYPAL_CLIENT_ID', nil)
      client_secret = ENV.fetch('PAYPAL_CLIENT_SECRET', nil)

      raise 'PayPal credentials not configured' unless client_id && client_secret

      # Validate credential format
      unless client_id.match?(/^[A-Za-z0-9_-]+$/) && client_secret.match?(/^[A-Za-z0-9_-]+$/)
        raise 'Invalid PayPal credential format'
      end

      uri = URI("#{paypal_base_url}/v1/oauth2/token")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request.basic_auth(client_id, client_secret)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = 'grant_type=client_credentials'

      response = http.request(request)
      data = JSON.parse(response.body)

      raise 'Failed to get PayPal access token' unless data['access_token']

      data['access_token']
    end

    def make_paypal_request(method, endpoint, data, access_token)
      uri = URI("#{paypal_base_url}#{endpoint}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = case method.upcase
                when 'GET'
                  Net::HTTP::Get.new(uri)
                when 'POST'
                  Net::HTTP::Post.new(uri)
                when 'PUT'
                  Net::HTTP::Put.new(uri)
                when 'DELETE'
                  Net::HTTP::Delete.new(uri)
                else
                  raise "Unsupported HTTP method: #{method}"
                end

      request['Authorization'] = "Bearer #{access_token}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'

      request.body = data.to_json if data

      response = http.request(request)

      raise "PayPal API request failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def paypal_base_url
      if ENV['PAYPAL_ENVIRONMENT'] == 'production'
        'https://api.paypal.com'
      else
        'https://api.sandbox.paypal.com'
      end
    end

    def base_url
      host = ENV['APP_HOST'] || 'localhost:4567'
      protocol = ENV['APP_ENV'] == 'production' ? 'https' : 'http'

      # Validate host format for security
      raise 'Invalid host configuration' unless host.match?(/^[a-zA-Z0-9.-]+(?::\d+)?$/)

      "#{protocol}://#{host}"
    end

    # Security and validation helpers
    def generate_payment_idempotency_key(order)
      data = "#{order.id}:#{order.amount}:#{order.email}:#{Time.now.to_i / 300}" # 5-minute window
      Digest::SHA256.hexdigest(data)[0, 32]
    end

    def check_duplicate_payment(idempotency_key)
      # Check if payment with this idempotency key already exists
      Order.where(idempotency_key: idempotency_key).first
    end

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

    def log_payment_event(event_type, details = {})
      event_log = {
        timestamp: Time.now.iso8601,
        event_type: event_type,
        details: details,
      }

      # Log to payment log file or service
      puts "PAYMENT_EVENT: #{event_log.to_json}" # In production, use proper logging
    end
  end
end

# Subscription management for recurring payments
class SubscriptionProcessor
  class << self
    # Create subscription for recurring payments
    def create_subscription(license, payment_method)
      case payment_method.to_s.downcase
      when 'stripe'
        create_stripe_subscription(license)
      when 'paypal'
        create_paypal_subscription(license)
      else
        raise "Unsupported payment method: #{payment_method}"
      end
    end

    # Cancel subscription
    def cancel_subscription(subscription)
      case subscription.license.order.payment_method.to_s.downcase
      when 'stripe'
        cancel_stripe_subscription(subscription)
      when 'paypal'
        cancel_paypal_subscription(subscription)
      else
        false
      end
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

    def create_stripe_subscription(license)
      Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)

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

    def create_paypal_subscription(license)
      # PayPal subscription implementation
      # This would involve creating a PayPal billing plan and subscription
      # Similar to the order process but for recurring payments
    end

    def cancel_stripe_subscription(subscription)
      Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)

      begin
        stripe_sub = Stripe::Subscription.retrieve(subscription.external_subscription_id)
        stripe_sub.cancel
        subscription.cancel!
        true
      rescue Stripe::StripeError
        false
      end
    end

    def cancel_paypal_subscription(subscription)
      # PayPal subscription cancellation implementation
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
      # In a real implementation, you'd store and retrieve customer IDs
      # For now, create a new customer each time
      customer = Stripe::Customer.create({ email: email })
      customer.id
    end

    def send_renewal_notification(subscription)
      # Send email notification about renewal
      # This would integrate with your email system
    end
  end
end

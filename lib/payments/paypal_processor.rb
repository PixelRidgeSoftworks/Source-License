# frozen_string_literal: true

# Source-License: PayPal Payment Processor
# Handles PayPal payment processing with webhook-first flow and improved security

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require_relative 'base_payment_processor'
require_relative '../logging/payment_logger'

class Payments::PaypalProcessor < Payments::BasePaymentProcessor
  class << self
    # Process a PayPal payment. When webhooks are enabled this will be idempotent
    # and return a result indicating that fulfillment will occur via webhook.
    def process_payment(order, payment_data = {})
      PaymentLogger.log_payment_event('payment_attempt', {
        order_id: order.id,
        method: 'paypal',
        payment_data: payment_data,
      })

      use_webhooks = ENV['PAYPAL_USE_WEBHOOKS'] == 'true'

      if use_webhooks
        # Defer finalization to webhook processing to support asynchronous capture
        order.update(status: 'pending', payment_method: 'paypal', payment_intent_id: payment_data[:order_id])

        PaymentLogger.log_payment_event('payment_deferred_to_webhook',
                                        { order_id: order.id, order_id_from_provider: payment_data[:order_id] })

        return { success: true, message: 'Payment deferred; awaiting webhook for capture' }
      end

      # Fallback: attempt immediate capture
      response = capture_paypal_order(payment_data[:order_id])

      if response['status'] == 'COMPLETED' || response.dig('purchase_units', 0, 'payments', 'captures')
        capture_id = response['id'] || response.dig('purchase_units', 0, 'payments', 'captures', 0, 'id')

        order.update(
          status: 'completed',
          completed_at: Time.now,
          transaction_id: capture_id,
          payment_intent_id: payment_data[:order_id]
        )

        PaymentLogger.log_payment_event('payment_success', { order_id: order.id, transaction_id: capture_id })

        { success: true, transaction_id: capture_id }
      else
        order.update(status: 'failed')
        PaymentLogger.log_payment_event('payment_failed',
                                        { order_id: order.id, error: 'PayPal payment not completed',
                                          response: response, })
        { success: false, error: 'PayPal payment was not completed' }
      end
    rescue StandardError => e
      order.update(status: 'failed')
      PaymentLogger.log_security_event('payment_failed', { order_id: order.id, error: e.message })
      { success: false, error: "PayPal payment processing failed: #{e.message}" }
    end

    # Create a PayPal order and return approval URL and order id
    def create_payment_intent(order)
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
          return_url: "#{base_url}/payments/paypal/return?order_id=#{order.id}",
          cancel_url: "#{base_url}/cart",
        },
      }

      response = make_paypal_request('POST', '/v2/checkout/orders', order_data, access_token)

      raise 'Failed to create PayPal order' unless response['id']

      order.update(payment_intent_id: response['id'])

      approval_url = response['links']&.find { |link| link['rel'] == 'approve' }&.dig('href')

      PaymentLogger.log_payment_event('payment_intent_created', { order_id: order.id, paypal_order_id: response['id'] })

      { order_id: response['id'], approval_url: approval_url }
    rescue StandardError => e
      PaymentLogger.log_security_event('payment_intent_error', { order_id: order.id, error: e.message })
      raise
    end

    # Verify a PayPal order direct-API check
    def verify_payment(order_id)
      access_token = paypal_access_token
      response = make_paypal_request('GET', "/v2/checkout/orders/#{order_id}", nil, access_token)
      response['status'] == 'COMPLETED'
    rescue StandardError => e
      PaymentLogger.log_security_event('payment_verify_error', { order_id: order_id, error: e.message })
      false
    end

    # Process a refund for an order
    def process_refund(order, amount, reason)
      access_token = paypal_access_token

      order_details = make_paypal_request('GET', "/v2/checkout/orders/#{order.payment_intent_id}", nil, access_token)

      capture_id = order_details.dig('purchase_units', 0, 'payments', 'captures', 0, 'id')
      return { success: false, error: 'Capture ID not found' } unless capture_id

      refund_data = {
        amount: {
          currency_code: order.currency,
          value: format('%.2f', amount),
        },
        note_to_payer: reason || 'Refund processed',
      }

      response = make_paypal_request('POST', "/v2/payments/captures/#{capture_id}/refund", refund_data, access_token)

      if response['status'] == 'COMPLETED'
        order.update(status: 'refunded') if amount == order.amount
        PaymentLogger.log_payment_event('refund_processed',
                                        { order_id: order.id, refund_id: response['id'], amount: amount })
        { success: true, refund_id: response['id'], amount: amount }
      else
        PaymentLogger.log_payment_event('refund_failed', { order_id: order.id, response: response })
        { success: false, error: 'PayPal refund failed' }
      end
    rescue StandardError => e
      PaymentLogger.log_security_event('refund_processing_failed', { order_id: order.id, error: e.message })
      { success: false, error: "PayPal refund processing failed: #{e.message}" }
    end

    # Subscription management
    def create_subscription(license)
      access_token = paypal_access_token
      product = license.product

      product_data = {
        name: product.name,
        description: product.description || product.name,
        type: 'SERVICE',
        category: 'SOFTWARE',
      }

      paypal_product = make_paypal_request('POST', '/v1/catalogs/products', product_data, access_token)

      plan_data = {
        product_id: paypal_product['id'],
        name: "#{product.name} Subscription",
        description: "Recurring subscription for #{product.name}",
        billing_cycles: [{
          frequency: { interval_unit: 'MONTH', interval_count: 1 },
          tenure_type: 'REGULAR',
          sequence: 1,
          total_cycles: 0,
          pricing_scheme: { fixed_price: { value: format('%.2f', product.price),
                                           currency_code: product.currency || 'USD', } },
        }],
        payment_preferences: { auto_bill_outstanding: true, setup_fee_failure_action: 'CONTINUE',
                               payment_failure_threshold: 3, },
      }

      billing_plan = make_paypal_request('POST', '/v1/billing/plans', plan_data, access_token)

      subscription_data = {
        plan_id: billing_plan['id'],
        subscriber: { email_address: license.customer_email },
        application_context: { brand_name: 'Source License', return_url: "#{base_url}/subscription/success",
                               cancel_url: "#{base_url}/subscription/cancel", },
      }

      subscription = make_paypal_request('POST', '/v1/billing/subscriptions', subscription_data, access_token)

      if subscription['id']
        license.subscription.update(external_subscription_id: subscription['id']) if license.subscription
        PaymentLogger.log_payment_event('subscription_created',
                                        { license_id: license.id, paypal_subscription_id: subscription['id'] })
        { success: true, subscription_id: subscription['id'], approval_url: subscription.dig('links')&.find do |l|
          l['rel'] == 'approve'
        end&.dig('href'), }
      else
        PaymentLogger.log_payment_event('subscription_create_failed',
                                        { license_id: license.id, response: subscription })
        { success: false, error: 'Failed to create PayPal subscription' }
      end
    rescue StandardError => e
      PaymentLogger.log_security_event('subscription_create_error', { license_id: license.id, error: e.message })
      { success: false, error: e.message }
    end

    def cancel_subscription(subscription, reason = 'User requested cancellation')
      access_token = paypal_access_token

      make_paypal_request('POST', "/v1/billing/subscriptions/#{subscription.external_subscription_id}/cancel",
                          { reason: reason }, access_token)

      subscription.cancel!
      PaymentLogger.log_payment_event('subscription_canceled',
                                      { subscription_id: subscription.id,
                                        external_id: subscription.external_subscription_id, })

      { success: true }
    rescue StandardError => e
      PaymentLogger.log_security_event('subscription_cancel_failed',
                                       { subscription_id: subscription.id, error: e.message })
      { success: false, error: e.message }
    end

    # Webhook signature verification using PayPal API
    def verify_webhook_signature(payload, headers)
      webhook_id = ENV.fetch('PAYPAL_WEBHOOK_ID', nil)
      return false unless webhook_id

      access_token = paypal_access_token

      verification_request = {
        transmission_id: headers['PAYPAL-TRANSMISSION-ID'],
        transmission_time: headers['PAYPAL-TRANSMISSION-TIME'],
        cert_url: headers['PAYPAL-CERT-URL'],
        auth_algo: headers['PAYPAL-AUTH-ALGO'],
        transmission_sig: headers['PAYPAL-TRANSMISSION-SIG'],
        webhook_id: webhook_id,
        webhook_event: JSON.parse(payload),
      }

      response = make_paypal_request('POST', '/v1/notifications/verify-webhook-signature', verification_request,
                                     access_token)

      valid = response['verification_status'] == 'SUCCESS'

      unless valid
        PaymentLogger.log_security_event('webhook_signature_invalid', { provider: 'paypal', details: response })
      end

      valid
    rescue StandardError => e
      PaymentLogger.log_security_event('webhook_verification_error', { provider: 'paypal', error: e.message })
      false
    end

    private

    # Capture an order, with idempotency checks
    def capture_paypal_order(order_id)
      access_token = paypal_access_token

      # Check order status first
      order = make_paypal_request('GET', "/v2/checkout/orders/#{order_id}", nil, access_token)

      return order if order['status'] == 'COMPLETED'

      # Attempt capture
      make_paypal_request('POST', "/v2/checkout/orders/#{order_id}/capture", {}, access_token)
    end

    def paypal_access_token
      client_id = ENV.fetch('PAYPAL_CLIENT_ID', nil)
      client_secret = ENV.fetch('PAYPAL_CLIENT_SECRET', nil)

      raise 'PayPal credentials not configured' unless client_id && client_secret

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
      http.open_timeout = 10
      http.read_timeout = 30

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
      request['PayPal-Request-Id'] = SecureRandom.uuid # Idempotency header

      request.body = data.to_json if data

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        body = begin
          JSON.parse(response.body)
        rescue StandardError
          { message: response.body }
        end
        raise "PayPal API request failed: #{response.code} #{response.message} - #{body}"
      end

      JSON.parse(response.body)
    end

    def paypal_base_url
      ENV['PAYPAL_ENVIRONMENT'] == 'production' ? 'https://api.paypal.com' : 'https://api.sandbox.paypal.com'
    end

    def base_url
      if ENV['APP_ENV'] == 'production'
        "https://#{ENV['APP_HOST'] || 'localhost'}"
      else
        port = ENV['PORT'] || '4567'
        host = ENV['APP_HOST'] || 'localhost'
        "http://#{host}:#{port}"
      end
    end
  end
end

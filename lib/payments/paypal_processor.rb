# frozen_string_literal: true

# Source-License: PayPal Payment Processor
# Handles PayPal payment processing with enhanced security

# TODO: Refactor to use webhooks instead of the REST API
# TODO: Add subscription management methods
# TODO: Implement better error handling and logging
# TODO: Add support for PayPal Vault for storing payment methods
# TODO: Implement retry logic for transient API errors
# TODO: Add more detailed validation of PayPal responses
# TODO: Implement rate limiting for API requests
# TODO: Add support for PayPal's advanced fraud protection features
# TODO: Write unit and integration tests for all methods
# TODO: Document all methods and classes thoroughly
# TODO: Ensure compliance with PCI DSS standards
# TODO: Add localization support for different currencies and regions
# TODO: Implement idempotency for payment requests

require 'net/http'
require 'uri'
require 'json'
require_relative 'base_payment_processor'

class Payments::PaypalProcessor < Payments::BasePaymentProcessor
  class << self
    def process_payment(order, payment_data = {})
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

    def verify_payment(order_id)
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

    def process_refund(order, amount, reason)
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

    # Subscription management methods
    def create_subscription(license)
      # PayPal subscription implementation
      # This would involve creating a PayPal billing plan and subscription
      # Similar to the order process but for recurring payments
      access_token = paypal_access_token
      product = license.product

      # Create PayPal product for subscription
      product_data = {
        name: product.name,
        description: product.description,
        type: 'SERVICE',
        category: 'SOFTWARE',
      }

      paypal_product = make_paypal_request(
        'POST',
        '/v1/catalogs/products',
        product_data,
        access_token
      )

      # Create billing plan
      plan_data = {
        product_id: paypal_product['id'],
        name: "#{product.name} Subscription",
        description: "Monthly subscription for #{product.name}",
        billing_cycles: [{
          frequency: {
            interval_unit: 'MONTH',
            interval_count: 1,
          },
          tenure_type: 'REGULAR',
          sequence: 1,
          total_cycles: 0, # Infinite
          pricing_scheme: {
            fixed_price: {
              value: format('%.2f', product.price),
              currency_code: 'USD',
            },
          },
        }],
        payment_preferences: {
          auto_bill_outstanding: true,
          setup_fee_failure_action: 'CONTINUE',
          payment_failure_threshold: 3,
        },
      }

      billing_plan = make_paypal_request(
        'POST',
        '/v1/billing/plans',
        plan_data,
        access_token
      )

      # Create subscription
      subscription_data = {
        plan_id: billing_plan['id'],
        subscriber: {
          email_address: license.customer_email,
        },
        application_context: {
          brand_name: 'Source License',
          return_url: "#{base_url}/subscription/success",
          cancel_url: "#{base_url}/subscription/cancel",
        },
      }

      subscription = make_paypal_request(
        'POST',
        '/v1/billing/subscriptions',
        subscription_data,
        access_token
      )

      # Update license subscription record
      license.subscription.update(external_subscription_id: subscription['id'])

      subscription['id']
    end

    def cancel_subscription(subscription)
      access_token = paypal_access_token

      begin
        cancel_data = {
          reason: 'User requested cancellation',
        }

        make_paypal_request(
          'POST',
          "/v1/billing/subscriptions/#{subscription.external_subscription_id}/cancel",
          cancel_data,
          access_token
        )

        subscription.cancel!
        true
      rescue StandardError
        false
      end
    end

    private

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
      # Get the base URL for return/cancel URLs
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

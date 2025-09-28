# frozen_string_literal: true

# Source-License: Webhooks Controller
# Handles incoming webhook requests from payment providers

require_relative '../webhooks/stripe_webhook_handler'
require_relative '../webhooks/paypal_webhook_handler'

module WebhooksController
  def self.setup_routes(app)
    app.instance_eval do
      # Ensure content type is set correctly for webhook responses
      before '/webhooks/*' do
        content_type :json
      end

      # Stripe webhook endpoint
      post '/webhooks/stripe' do
        # Get raw body for signature verification
        request.body.rewind
        payload = request.body.read
        signature = request.env['HTTP_STRIPE_SIGNATURE']

        # Validate required parameters
        halt 400, { error: 'Missing payload' }.to_json if payload.empty?
        halt 400, { error: 'Missing Stripe signature' }.to_json unless signature

        begin
          # Process the webhook
          result = Webhooks::StripeWebhookHandler.handle_webhook(payload, signature)

          if result[:success]
            status 200
            { success: true, message: result[:message] }.to_json
          else
            status 400
            { success: false, error: result[:error] }.to_json
          end
        rescue StandardError => e
          # Log error and return 500 to trigger Stripe retry
          puts "Stripe webhook error: #{e.class}: #{e.message}"
          puts e.backtrace.join("\n") if ENV['APP_ENV'] == 'development'

          status 500
          { success: false, error: 'Internal server error' }.to_json
        end
      end

      # PayPal webhook endpoint
      post '/webhooks/paypal' do
        # Get raw body for signature verification
        request.body.rewind
        payload = request.body.read
        headers = request.env.select { |k, _v| k.start_with?('HTTP_PAYPAL') }
          .transform_keys { |k| k.sub('HTTP_', '') }

        # Validate required parameters
        halt 400, { error: 'Missing payload' }.to_json if payload.empty?

        begin
          # Process the webhook
          result = Webhooks::PaypalWebhookHandler.handle_webhook(payload, headers)

          if result[:success]
            status 200
            { success: true, message: result[:message] }.to_json
          else
            status 400
            { success: false, error: result[:error] }.to_json
          end
        rescue StandardError => e
          # Log error and return 500 to trigger PayPal retry
          puts "PayPal webhook error: #{e.class}: #{e.message}"
          puts e.backtrace.join("\n") if ENV['APP_ENV'] == 'development'

          status 500
          { success: false, error: 'Internal server error' }.to_json
        end
      end

      # Health check endpoint for webhook monitoring
      get '/webhooks/health' do
        content_type :json
        {
          status: 'healthy',
          timestamp: Time.now.iso8601,
          version: '1.0.0',
        }.to_json
      end

      # Webhook test endpoint (development only)
      if ENV['APP_ENV'] == 'development'
        post '/webhooks/test' do
          request.body.rewind
          payload = request.body.read

          begin
            data = JSON.parse(payload)

            # Log test webhook
            puts "TEST_WEBHOOK: #{data.inspect}"

            status 200
            { success: true, message: 'Test webhook processed', data: data }.to_json
          rescue JSON::ParserError
            status 400
            { success: false, error: 'Invalid JSON payload' }.to_json
          end
        end
      end
    end
  end
end

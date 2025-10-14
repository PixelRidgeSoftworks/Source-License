# frozen_string_literal: true

require_relative '../payments/stripe_processor'
require_relative '../logging/payment_logger'
require_relative 'route_primitive'

module SubscriptionController
  def self.setup_routes(app)
    # Setup authentication filters
    setup_subscription_filters(app)

    # Register individual subscription routes
    subscription_pause_route(app)
    subscription_resume_route(app)
    subscription_cancel_route(app)
    customer_portal_route(app)
    payment_method_update_page_route(app)
    payment_method_update_handler_route(app)
  end

  # Setup authentication filters for subscription routes
  def self.setup_subscription_filters(app)
    app.instance_eval do
      # Require authentication for all subscription actions
      before '/subscription/*' do
        redirect '/login' unless user_logged_in?
        @user = current_user
      end

      before '/customer-portal/*' do
        redirect '/login' unless user_logged_in?
        @user = current_user
      end

      before '/update-payment-method/*' do
        redirect '/login' unless user_logged_in?
        @user = current_user
      end
    end
  end

  # Pause a subscription
  def self.subscription_pause_route(app)
    app.post '/subscription/:id/pause' do
      subscription = find_user_subscription(params[:id])
      return json_error('Subscription not found', 404) unless subscription

      begin
        # Check if subscription has Stripe ID
        unless subscription.external_subscription_id
          return json_error('Cannot pause subscription: No Stripe subscription found')
        end

        # Pause subscription via Stripe
        stripe_subscription = Payments::StripeProcessor.pause_subscription(subscription.external_subscription_id)

        if stripe_subscription
          # Update local subscription status
          subscription.update(
            status: 'paused',
            paused_at: Time.now
          )

          # Log the action
          PaymentLogger.log_subscription_action(
            subscription_id: subscription.id,
            action: 'paused',
            user_id: @user.id,
            details: {
              stripe_subscription_id: subscription.external_subscription_id,
              paused_by: 'customer',
            }
          )

          json_success('Subscription paused successfully. Your license will remain active until the current billing period ends.')
        else
          json_error('Failed to pause subscription. Please try again.')
        end
      rescue StandardError => e
        PaymentLogger.log_error("Failed to pause subscription #{subscription.id}: #{e.message}", {
          subscription_id: subscription.id,
          user_id: @user.id,
          error: e.class.name,
        })
        json_error('An error occurred while pausing the subscription.')
      end
    end
  end

  # Resume a paused subscription
  def self.subscription_resume_route(app)
    app.post '/subscription/:id/resume' do
      subscription = find_user_subscription(params[:id])
      return json_error('Subscription not found', 404) unless subscription

      begin
        # Check if subscription has Stripe ID
        unless subscription.external_subscription_id
          return json_error('Cannot resume subscription: No Stripe subscription found')
        end

        # Resume subscription via Stripe
        stripe_subscription = Payments::StripeProcessor.resume_subscription(subscription.external_subscription_id)

        if stripe_subscription
          # Update local subscription status
          subscription.update(
            status: 'active',
            paused_at: nil
          )

          # Reactivate license if it was suspended due to pause
          subscription.license.reactivate! if subscription.license&.suspended?

          # Log the action
          PaymentLogger.log_subscription_action(
            subscription_id: subscription.id,
            action: 'resumed',
            user_id: @user.id,
            details: {
              stripe_subscription_id: subscription.external_subscription_id,
              resumed_by: 'customer',
            }
          )

          json_success('Subscription resumed successfully. Your license is now active.')
        else
          json_error('Failed to resume subscription. Please try again.')
        end
      rescue StandardError => e
        PaymentLogger.log_error("Failed to resume subscription #{subscription.id}: #{e.message}", {
          subscription_id: subscription.id,
          user_id: @user.id,
          error: e.class.name,
        })
        json_error('An error occurred while resuming the subscription.')
      end
    end
  end

  # Cancel a subscription
  def self.subscription_cancel_route(app)
    app.post '/subscription/:id/cancel' do
      subscription = find_user_subscription(params[:id])
      return json_error('Subscription not found', 404) unless subscription

      begin
        # Check if subscription has Stripe ID
        unless subscription.external_subscription_id
          return json_error('Cannot cancel subscription: No Stripe subscription found')
        end

        # Cancel subscription via Stripe (at period end to avoid prorating)
        stripe_subscription = Payments::StripeProcessor.cancel_subscription(
          subscription.external_subscription_id,
          at_period_end: true
        )

        if stripe_subscription
          # Update local subscription status
          subscription.update(
            status: 'canceled',
            canceled_at: Time.now,
            auto_renew: false
          )

          # Log the action
          PaymentLogger.log_subscription_action(
            subscription_id: subscription.id,
            action: 'canceled',
            user_id: @user.id,
            details: {
              stripe_subscription_id: subscription.external_subscription_id,
              canceled_by: 'customer',
              cancel_at_period_end: true,
            }
          )

          json_success('Subscription canceled successfully. Your license will remain active until the current billing period ends.')
        else
          json_error('Failed to cancel subscription. Please try again.')
        end
      rescue StandardError => e
        PaymentLogger.log_error("Failed to cancel subscription #{subscription.id}: #{e.message}", {
          subscription_id: subscription.id,
          user_id: @user.id,
          error: e.class.name,
        })
        json_error('An error occurred while canceling the subscription.')
      end
    end
  end

  # Create Stripe Customer Portal session
  def self.customer_portal_route(app)
    app.get '/customer-portal/:subscription_id' do
      subscription = find_user_subscription(params[:subscription_id])
      redirect '/dashboard' unless subscription

      begin
        # Get customer ID from subscription or create if needed
        customer_id = subscription.external_customer_id
        unless customer_id
          # Try to find customer by email
          customer = Payments::StripeProcessor.find_or_create_customer(@user.email, @user.name)
          customer_id = customer.id if customer
        end

        if customer_id
          # Create portal session
          portal_session = Payments::StripeProcessor.create_customer_portal_session(
            customer_id,
            "#{request.base_url}/licenses/#{subscription.license_id}"
          )

          if portal_session
            redirect portal_session.url
          else
            flash[:error] = 'Unable to access customer portal. Please try again.'
            redirect "/licenses/#{subscription.license_id}"
          end
        else
          flash[:error] = 'Customer account not found. Please contact support.'
          redirect "/licenses/#{subscription.license_id}"
        end
      rescue StandardError => e
        PaymentLogger.log_error("Failed to create customer portal session for subscription #{subscription.id}: #{e.message}", {
          subscription_id: subscription.id,
          user_id: @user.id,
          error: e.class.name,
        })
        flash[:error] = 'An error occurred accessing the customer portal.'
        redirect "/licenses/#{subscription.license_id}"
      end
    end
  end

  # Payment method update page
  def self.payment_method_update_page_route(app)
    app.get '/update-payment-method/:subscription_id' do
      @subscription = find_user_subscription(params[:subscription_id])
      redirect '/dashboard' unless @subscription

      @license = @subscription.license
      erb :'users/update_payment_method'
    end
  end

  # Process payment method update
  def self.payment_method_update_handler_route(app)
    app.post '/update-payment-method/:subscription_id' do
      subscription = find_user_subscription(params[:subscription_id])
      redirect '/dashboard' unless subscription

      begin
        payment_method_id = params[:payment_method_id]&.strip

        if payment_method_id.nil? || payment_method_id.empty?
          flash[:error] = 'Payment method is required.'
          redirect "/update-payment-method/#{subscription.id}"
        end

        # Update default payment method for the subscription
        success = Payments::StripeProcessor.update_subscription_payment_method(
          subscription.external_subscription_id,
          payment_method_id
        )

        if success
          # Log the update
          PaymentLogger.log_subscription_action(
            subscription_id: subscription.id,
            action: 'payment_method_updated',
            user_id: @user.id,
            details: {
              stripe_subscription_id: subscription.external_subscription_id,
              payment_method_id: payment_method_id,
            }
          )

          flash[:success] = 'Payment method updated successfully.'
          redirect "/licenses/#{subscription.license_id}"
        else
          flash[:error] = 'Failed to update payment method. Please try again.'
          redirect "/update-payment-method/#{subscription.id}"
        end
      rescue StandardError => e
        PaymentLogger.log_error("Failed to update payment method for subscription #{subscription.id}: #{e.message}", {
          subscription_id: subscription.id,
          user_id: @user.id,
          error: e.class.name,
        })
        flash[:error] = 'An error occurred while updating the payment method.'
        redirect "/update-payment-method/#{subscription.id}"
      end
    end
  end

  # Helper methods available to all route methods
  class << self
    private

    # Find subscription that belongs to current user
    def find_user_subscription(subscription_id)
      # NOTE: This method is called within the app context, so @user is available
      # Find subscription through user's licenses
      @user.licenses_dataset
        .join(:subscriptions, license_id: :id)
        .where(subscriptions__id: subscription_id)
        .first&.subscription
    end

    # Helper methods for JSON responses
    def json_success(message, data = {})
      content_type :json
      { success: true, message: message, **data }.to_json
    end

    def json_error(message, status = 400)
      status status
      content_type :json
      { success: false, error: message }.to_json
    end
  end
end

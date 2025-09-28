# frozen_string_literal: true

require_relative 'base_event_handler'
require_relative 'license_finder_service'
require_relative 'notification_service'

class Webhooks::Stripe::PaymentEventHandler < BaseEventHandler
  class << self
    # Main entry point for payment events
    def handle_event(event)
      return { success: true, message: "Webhook #{event.type} is disabled" } unless webhook_enabled?(event.type)

      case event.type
      when 'payment_intent.created'
        handle_payment_intent_created(event)
      when 'payment_intent.succeeded'
        handle_payment_intent_succeeded(event)
      when 'charge.succeeded'
        handle_charge_succeeded(event)
      when 'charge.failed'
        handle_charge_failed(event)
      when 'charge.refunded'
        handle_charge_refunded(event)
      when 'payment_method.attached'
        handle_payment_method_attached(event)
      else
        { success: true, message: "Unhandled payment event type: #{event.type}" }
      end
    end

    private

    # Handle payment intent created (track payment initiation)
    def handle_payment_intent_created(event)
      payment_intent = event.data.object

      # Use PaymentLogger directly since license might be nil
      log_license_event(nil, 'payment_intent_created', {
        payment_intent_id: payment_intent.id,
        amount: payment_intent.amount / 100.0,
        currency: payment_intent.currency,
        customer_id: payment_intent.customer,
      })

      { success: true, message: 'Payment intent created - tracked for monitoring' }
    end

    # Handle payment intent succeeded (alternative to charge.succeeded for some flows)
    def handle_payment_intent_succeeded(event)
      payment_intent = event.data.object

      # Find associated order by payment intent ID
      order = Order.where(payment_intent_id: payment_intent.id).first

      if order
        # Complete the order if it's still pending
        unless order.status == 'pending'
          return { success: true, message: 'Payment intent succeeded - order already processed' }
        end

        DB.transaction do
          order.update(status: 'completed', completed_at: Time.now)

          # Generate licenses if they don't exist yet
          if order.licenses.empty?
            ApiController.generate_licenses_for_order(order)
            order.refresh
          end

          # Check if any products in this order are subscription-based
          order.order_items.each do |item|
            product = item.product

            next unless product&.subscription?

            # Create Stripe subscription for this customer and product
            stripe_sub = create_stripe_subscription_for_order(order, product, payment_intent)
            next unless stripe_sub

            log_license_event(order.licenses.first, 'subscription_setup_completed', {
              stripe_subscription_id: stripe_sub.id,
              order_id: order.id,
              product_id: product.id,
            })
          end
        end

        log_license_event(order.licenses.first, 'payment_intent_succeeded_order_completed', {
          payment_intent_id: payment_intent.id,
          order_id: order.id,
          amount: payment_intent.amount / 100.0,
        })

        return { success: true, message: 'Payment intent succeeded - order completed and licenses generated' }
      end

      # Log for monitoring even if no order found
      log_license_event(nil, 'payment_intent_succeeded_no_order', {
        payment_intent_id: payment_intent.id,
        amount: payment_intent.amount / 100.0,
        currency: payment_intent.currency,
      })

      { success: true, message: 'Payment intent succeeded - no associated order found' }
    end

    # Handle successful charges (extend/renew/issue license)
    def handle_charge_succeeded(event)
      charge = event.data.object

      # Find associated order or license by charge metadata or customer email
      license = LicenseFinderService.find_license_for_charge(charge)
      return { success: false, error: 'License not found for charge' } unless license

      DB.transaction do
        # If this is a subscription renewal charge
        if license.subscription_based? && license.subscription
          # Extend the license for the next billing period
          product = license.product
          if product&.license_duration_days
            license.extend!(product.license_duration_days)
            license.subscription.update(status: 'active')
            log_license_event(license, 'renewed_via_charge', {
              charge_id: charge.id,
              amount: charge.amount / 100.0,
              extended_days: product.license_duration_days,
            })
          end
        elsif license.revoked? || license.suspended?
          # For one-time purchases, ensure license is active
          license.reactivate!
          log_license_event(license, 'issued_via_charge', {
            charge_id: charge.id,
            amount: charge.amount / 100.0,
          })
        end

        # Send success notification
        NotificationService.send_charge_success_notification(license, charge)
      end

      { success: true, message: 'Charge success processed - license extended/renewed/issued' }
    end

    # Handle failed charges (warn user)
    def handle_charge_failed(event)
      charge = event.data.object

      # Find associated license
      license = LicenseFinderService.find_license_for_charge(charge)
      return { success: false, error: 'License not found for charge' } unless license

      # Send warning notification to user
      NotificationService.send_charge_failed_notification(license, charge)

      log_license_event(license, 'charge_failed_warning', {
        charge_id: charge.id,
        failure_reason: charge.failure_message,
      })

      { success: true, message: 'Charge failure notification sent' }
    end

    # Handle refunded charges (automatically revoke/disable license)
    def handle_charge_refunded(event)
      charge = event.data.object

      # Find associated license
      license = LicenseFinderService.find_license_for_charge(charge)
      return { success: false, error: 'License not found for charge' } unless license

      DB.transaction do
        # Revoke the license due to refund
        license.revoke!

        # If it's a subscription, cancel it as well
        if license.subscription
          license.subscription.cancel!

          # Cancel the Stripe subscription to prevent future charges
          if license.subscription.external_subscription_id
            cancel_stripe_subscription(license.subscription.external_subscription_id)
          end
        end

        log_license_event(license, 'revoked_due_to_refund', {
          charge_id: charge.id,
          refund_amount: charge.amount_refunded / 100.0,
        })

        # Send revocation notification
        NotificationService.send_license_revoked_notification(license, 'refund')
      end

      { success: true, message: 'License revoked due to charge refund' }
    end

    def handle_payment_method_attached(event)
      payment_method = event.data.object

      log_license_event(nil, 'payment_method_attached', {
        payment_method_id: payment_method.id,
        customer_id: payment_method.customer,
        type: payment_method.type,
      })

      { success: true, message: 'Payment method attached - logged for tracking' }
    end

    # Create Stripe subscription for subscription-based product
    def create_stripe_subscription_for_order(order, product, payment_intent)
      ::Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)

      # Get or create Stripe customer
      customer_id = payment_intent.customer
      if customer_id.nil?
        # Create a new Stripe customer
        customer = ::Stripe::Customer.create({
          email: order.email,
          name: order.email, # Use email as name since Order doesn't have a name field
          metadata: {
            order_id: order.id,
            source: 'source-license',
          },
        })
        customer_id = customer.id
      end

      # Check if customer has a default payment method, if not, set one up
      customer = ::Stripe::Customer.retrieve(customer_id)
      collection_method = if customer.invoice_settings&.default_payment_method.nil? && customer.default_source.nil?
                            # For subscriptions without a default payment method, use collection_method: 'send_invoice'
                            # This tells Stripe to send invoices for payment collection
                            'send_invoice'
                          else
                            # Customer has a payment method, use normal charge_automatically
                            'charge_automatically'
                          end

      # Create price object for this product (if it doesn't exist)
      price_id = create_or_get_stripe_price(product)

      # Create the subscription with appropriate collection method
      subscription_params = {
        customer: customer_id,
        items: [{
          price: price_id,
        }],
        metadata: {
          order_id: order.id,
          license_id: order.licenses.first&.id,
          product_id: product.id,
          source: 'source-license',
        },
        # Start immediately since payment already succeeded
        billing_cycle_anchor: Time.now.to_i,
        proration_behavior: 'none',
        collection_method: collection_method,
      }

      # Add payment behavior for invoice collection
      if collection_method == 'send_invoice'
        subscription_params[:days_until_due] = 7 # Customer has 7 days to pay invoice
      end

      stripe_subscription = ::Stripe::Subscription.create(subscription_params)

      # Update the license with subscription information
      license = order.licenses.first
      if license
        # Create local subscription record if it doesn't exist
        license.create_subscription_from_product! unless license.subscription

        # Update with Stripe details
        license.subscription.update(
          external_subscription_id: stripe_subscription.id,
          status: 'active',
          current_period_start: Time.at(stripe_subscription.current_period_start),
          current_period_end: Time.at(stripe_subscription.current_period_end),
          auto_renew: true
        )

        # Update license expiration to match subscription period
        license.update(expires_at: Time.at(stripe_subscription.current_period_end))

        log_license_event(license, 'stripe_subscription_created', {
          subscription_id: stripe_subscription.id,
          order_id: order.id,
          product_id: product.id,
          period_end: stripe_subscription.current_period_end,
        })
      end

      stripe_subscription
    rescue StandardError => e
      log_license_event(order.licenses.first, 'stripe_subscription_creation_failed', {
        order_id: order.id,
        product_id: product.id,
        error: e.message,
      })
      nil
    end

    # Create or retrieve Stripe price for a product
    def create_or_get_stripe_price(product)
      # For now, create a new price each time. In production, you might want to
      # cache these or create them when products are created
      ::Stripe::Price.create({
        currency: 'usd',
        unit_amount: (product.price * 100).to_i, # Convert to cents
        recurring: {
          interval: 'month', # Could be made configurable based on product
          interval_count: 1,
        },
        product_data: {
          name: product.name,
          metadata: {
            source_license_product_id: product.id,
            license_duration_days: product.license_duration_days,
          },
        },
      }).id
    end

    def cancel_stripe_subscription(subscription_id)
      ::Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)
      ::Stripe::Subscription.cancel(subscription_id)
    rescue StandardError => e
      puts "Failed to cancel Stripe subscription #{subscription_id}: #{e.message}"
    end
  end
end

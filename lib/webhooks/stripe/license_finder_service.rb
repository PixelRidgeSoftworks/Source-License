# frozen_string_literal: true

# Service for finding licenses associated with Stripe events
class Webhooks::Stripe::LicenseFinderService
  class << self
    # Find license associated with a Stripe charge
    def find_license_for_charge(charge)
      # Method 1: Find by payment intent (most reliable for checkout flow)
      if charge.payment_intent
        order = Order.where(payment_intent_id: charge.payment_intent).first
        if order
          # Return existing licenses if they exist - don't create duplicates
          return order.licenses.first if order.licenses.any?

          # Only generate licenses if order is still pending (shouldn't happen in normal flow)
          if order.status == 'pending'
            # Complete the order and generate licenses
            order.update(status: 'completed', completed_at: Time.now)
            ApiController.generate_licenses_for_order(order)
            order.refresh # Reload to get the new licenses
            return order.licenses.first if order.licenses.any?
          end
        end
      end

      # Method 2: Check charge metadata for license_key or order_id
      if charge.metadata
        if charge.metadata['license_key']
          license = License.where(license_key: charge.metadata['license_key']).first
          return license if license
        end

        if charge.metadata['order_id']
          order = Order[charge.metadata['order_id']]
          if order
            # Generate licenses if they don't exist
            if order.licenses.empty?
              order.update(status: 'completed', completed_at: Time.now) if order.status == 'pending'
              ApiController.generate_licenses_for_order(order)
              order.refresh
            end
            return order.licenses.first if order.licenses.any?
          end
        end
      end

      # Method 3: Find by customer email
      customer_id = charge.customer
      if customer_id
        begin
          ::Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)
          customer = ::Stripe::Customer.retrieve(customer_id)

          # First try to find an order with this email and payment intent
          order = Order.where(email: customer.email, payment_intent_id: charge.payment_intent).first
          if order
            if order.licenses.empty?
              order.update(status: 'completed', completed_at: Time.now) if order.status == 'pending'
              ApiController.generate_licenses_for_order(order)
              order.refresh
            end
            return order.licenses.first if order.licenses.any?
          end

          # Fallback to existing license lookup
          license = License.where(customer_email: customer.email).first
          return license if license
        rescue StandardError
          # Continue to next method
        end
      end

      nil
    end

    # Find license associated with a Stripe subscription
    def find_license_for_subscription(stripe_subscription)
      ::Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)

      # Method 1: Check subscription metadata for license_id (most reliable)
      if stripe_subscription.metadata && stripe_subscription.metadata['license_id']
        license_id = stripe_subscription.metadata['license_id']
        license = License[license_id.to_i]
        return license if license
      end

      # Method 2: Check subscription metadata for order_id
      if stripe_subscription.metadata && stripe_subscription.metadata['order_id']
        order_id = stripe_subscription.metadata['order_id']
        order = Order[order_id.to_i]
        return order.licenses.first if order&.licenses&.any?
      end

      # Method 3: Find by customer email
      begin
        customer_id = stripe_subscription.customer
        customer = ::Stripe::Customer.retrieve(customer_id)

        # Find most recent license for this customer email
        license = License.where(customer_email: customer.email)
          .order(:created_at)
          .last # Get the most recent license for this customer
        return license if license
      rescue StandardError => e
        puts "Failed to retrieve customer #{customer_id}: #{e.message}"
      end

      # Method 4: Try to find by external subscription ID (in case it's already set)
      subscription = Subscription.where(external_subscription_id: stripe_subscription.id).first
      return subscription.license if subscription

      nil
    end

    # Find license by charge ID (retrieves charge from Stripe first)
    def find_license_for_charge_id(charge_id)
      ::Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)
      begin
        charge = ::Stripe::Charge.retrieve(charge_id)
        find_license_for_charge(charge)
      rescue StandardError => e
        puts "Failed to retrieve charge #{charge_id}: #{e.message}"
        nil
      end
    end

    # Find subscription by invoice
    def find_subscription_by_invoice(invoice)
      return nil unless invoice.subscription

      Subscription.where(external_subscription_id: invoice.subscription).first
    end
  end
end

# frozen_string_literal: true

# Source-License: Admin Webhook Settings Controller
# Manages webhook configuration settings for payment providers

module AdminControllers::WebhookSettingsController
  def self.setup_routes(app)
    # Show webhook settings page
    app.get '/admin/webhooks' do
      require_secure_admin_auth
      @page_title = 'Webhook Settings'
      @webhook_settings = get_webhook_settings
      erb :'admin/webhook_settings', layout: :'layouts/admin_layout'
    end

    # Update webhook settings
    app.post '/admin/webhooks' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      # Get form data
      stripe_settings = params[:stripe_webhooks] || {}
      paypal_settings = params[:paypal_webhooks] || {}
      general_settings = params[:general_webhooks] || {}

      begin
        # Update general webhook settings
        update_general_webhook_settings(general_settings)

        # Update Stripe webhook settings
        update_stripe_webhook_settings(stripe_settings)

        # Update PayPal webhook settings
        update_paypal_webhook_settings(paypal_settings)

        # Set flash message and redirect
        flash[:success] = 'Webhook settings updated successfully'
        redirect '/admin/webhooks'
      rescue StandardError => e
        flash[:error] = "Failed to update webhook settings: #{e.message}"
        redirect '/admin/webhooks'
      end
    end

    # Test webhook endpoint (development only)
    return unless ENV['APP_ENV'] == 'development'

    app.post '/admin/webhooks/test' do
      require_secure_admin_auth
      content_type :json

      webhook_type = params[:webhook_type]
      event_data = params[:event_data]

      begin
        # Simulate webhook processing
        result = case webhook_type
                 when 'stripe'
                   simulate_stripe_webhook(event_data)
                 when 'paypal'
                   simulate_paypal_webhook(event_data)
                 else
                   { success: false, error: 'Unknown webhook type' }
                 end

        result.to_json
      rescue StandardError => e
        { success: false, error: e.message }.to_json
      end
    end
  end

  def self.get_webhook_settings
    {
      general: {
        enabled: SettingsManager.get('webhooks.enabled'),
        base_url: SettingsManager.get('webhooks.base_url'),
        timeout: SettingsManager.get('webhooks.timeout_seconds'),
        retry_attempts: SettingsManager.get('webhooks.retry_attempts'),
      },
      stripe: {
        'charge.succeeded' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_succeeded'),
          description: 'Extend/renew/issue license when charge succeeds',
        },
        'charge.failed' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_failed'),
          description: 'Warn user when charge fails',
        },
        'charge.refunded' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_refunded'),
          description: 'Automatically revoke license when charge is refunded',
        },
        'customer.subscription.deleted' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_deleted'),
          description: 'Cancel recurring license when subscription is deleted',
        },
        'customer.subscription.created' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_created'),
          description: 'Activate license when new subscription is created',
        },
        'customer.subscription.paused' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_paused'),
          description: 'Suspend license when subscription is paused',
        },
        'customer.subscription.resumed' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_resumed'),
          description: 'Un-suspend license when subscription is resumed',
        },
        'customer.subscription.updated' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_updated'),
          description: 'Handle subscription billing changes and status updates',
        },
        'customer.subscription.trial_will_end' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_subscription_trial_will_end'),
          description: 'Send trial ending notifications to customers',
        },
        'payment_intent.created' => {
          enabled: SettingsManager.get('webhooks.stripe.payment_intent_created'),
          description: 'Track payment initiation for monitoring',
        },
        'payment_intent.succeeded' => {
          enabled: SettingsManager.get('webhooks.stripe.payment_intent_succeeded'),
          description: 'Complete orders when payment intent succeeds',
        },
        'charge.dispute.created' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_dispute_created'),
          description: 'Process Stripe charge.dispute.created events (chargeback handling)',
        },
        'charge.dispute.updated' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_dispute_updated'),
          description: 'Process Stripe charge.dispute.updated events (dispute progress tracking)',
        },
        'charge.dispute.closed' => {
          enabled: SettingsManager.get('webhooks.stripe.charge_dispute_closed'),
          description: 'Process Stripe charge.dispute.closed events (dispute resolution)',
        },
        'invoice.payment_failed' => {
          enabled: SettingsManager.get('webhooks.stripe.invoice_payment_failed'),
          description: 'Process Stripe invoice.payment_failed events (subscription payment failures)',
        },
        'invoice.payment_succeeded' => {
          enabled: SettingsManager.get('webhooks.stripe.invoice_payment_succeeded'),
          description: 'Process Stripe invoice.payment_succeeded events (subscription renewals)',
        },
        'invoice.created' => {
          enabled: SettingsManager.get('webhooks.stripe.invoice_created'),
          description: 'Process Stripe invoice.created events (billing cycle tracking)',
        },
        'payment_method.attached' => {
          enabled: SettingsManager.get('webhooks.stripe.payment_method_attached'),
          description: 'Process Stripe payment_method.attached events (payment method tracking)',
        },
        'customer.updated' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_updated'),
          description: 'Process Stripe customer.updated events (customer data synchronization)',
        },
        'customer.created' => {
          enabled: SettingsManager.get('webhooks.stripe.customer_created'),
          description: 'Process Stripe customer.created events (new customer tracking)',
        },
        'plan.created' => {
          enabled: SettingsManager.get('webhooks.stripe.plan_created'),
          description: 'Process Stripe plan.created events (subscription plan tracking)',
        },
        'price.created' => {
          enabled: SettingsManager.get('webhooks.stripe.price_created'),
          description: 'Process Stripe price.created events (pricing tier tracking)',
        },
        'product.created' => {
          enabled: SettingsManager.get('webhooks.stripe.product_created'),
          description: 'Process Stripe product.created events (product catalog sync)',
        },
        'setup_intent.created' => {
          enabled: SettingsManager.get('webhooks.stripe.setup_intent_created'),
          description: 'Process Stripe setup_intent.created events (payment setup tracking)',
        },
      },
      paypal: {
        enabled: SettingsManager.get('webhooks.paypal.enabled'),
        description: 'PayPal webhook processing',
      },
      notifications: {
        enabled: SettingsManager.get('webhooks.notifications.enabled'),
        email: SettingsManager.get('webhooks.notifications.email'),
        slack_webhook_url: SettingsManager.get('webhooks.notifications.slack_webhook_url'),
      },
      logging: {
        enabled: SettingsManager.get('webhooks.logging.enabled'),
        log_level: SettingsManager.get('webhooks.logging.log_level'),
        retain_days: SettingsManager.get('webhooks.logging.retain_days'),
      },
    }
  end

  def self.update_general_webhook_settings(settings)
    # Update general webhook settings
    SettingsManager.set('webhooks.enabled', settings['enabled'] == '1')
    SettingsManager.set('webhooks.base_url', settings['base_url']) if settings['base_url']
    SettingsManager.set('webhooks.timeout_seconds', settings['timeout'].to_i) if settings['timeout']
    SettingsManager.set('webhooks.retry_attempts', settings['retry_attempts'].to_i) if settings['retry_attempts']

    # Update notification settings
    SettingsManager.set('webhooks.notifications.enabled', settings['notifications_enabled'] == '1')
    if settings['notifications_email']
      SettingsManager.set('webhooks.notifications.email',
                          settings['notifications_email'])
    end
    if settings['slack_webhook_url']
      SettingsManager.set('webhooks.notifications.slack_webhook_url',
                          settings['slack_webhook_url'])
    end

    # Update logging settings
    SettingsManager.set('webhooks.logging.enabled', settings['logging_enabled'] == '1')
    SettingsManager.set('webhooks.logging.log_level', settings['log_level']) if settings['log_level']
    SettingsManager.set('webhooks.logging.retain_days', settings['retain_days'].to_i) if settings['retain_days']
  end

  def self.update_stripe_webhook_settings(settings)
    webhook_mappings = {
      'charge_succeeded' => 'webhooks.stripe.charge_succeeded',
      'charge_failed' => 'webhooks.stripe.charge_failed',
      'charge_refunded' => 'webhooks.stripe.charge_refunded',
      'customer_subscription_deleted' => 'webhooks.stripe.customer_subscription_deleted',
      'customer_subscription_created' => 'webhooks.stripe.customer_subscription_created',
      'customer_subscription_paused' => 'webhooks.stripe.customer_subscription_paused',
      'customer_subscription_resumed' => 'webhooks.stripe.customer_subscription_resumed',
      'customer_subscription_updated' => 'webhooks.stripe.customer_subscription_updated',
      'customer_subscription_trial_will_end' => 'webhooks.stripe.customer_subscription_trial_will_end',
      'payment_intent_created' => 'webhooks.stripe.payment_intent_created',
      'payment_intent_succeeded' => 'webhooks.stripe.payment_intent_succeeded',
      'charge_dispute_created' => 'webhooks.stripe.charge_dispute_created',
      'charge_dispute_updated' => 'webhooks.stripe.charge_dispute_updated',
      'charge_dispute_closed' => 'webhooks.stripe.charge_dispute_closed',
      'invoice_payment_failed' => 'webhooks.stripe.invoice_payment_failed',
      'invoice_payment_succeeded' => 'webhooks.stripe.invoice_payment_succeeded',
      'invoice_created' => 'webhooks.stripe.invoice_created',
      'payment_method_attached' => 'webhooks.stripe.payment_method_attached',
      'customer_updated' => 'webhooks.stripe.customer_updated',
      'customer_created' => 'webhooks.stripe.customer_created',
      'plan_created' => 'webhooks.stripe.plan_created',
      'price_created' => 'webhooks.stripe.price_created',
      'product_created' => 'webhooks.stripe.product_created',
      'setup_intent_created' => 'webhooks.stripe.setup_intent_created',
    }

    webhook_mappings.each do |form_key, setting_key|
      enabled = settings[form_key] == '1'
      SettingsManager.set(setting_key, enabled)

      # Log the setting change
      puts "WEBHOOK_SETTING: #{setting_key} = #{enabled}"
    end
  end

  def self.update_paypal_webhook_settings(settings)
    # PayPal webhook settings
    SettingsManager.set('webhooks.paypal.enabled', settings['enabled'] == '1')
    SettingsManager.set('webhooks.paypal.webhook_id', settings['webhook_id']) if settings['webhook_id']
  end

  def self.simulate_stripe_webhook(event_data)
    # Simulate processing for testing purposes
    event_type = event_data['type']

    case event_type
    when 'charge.succeeded'
      { success: true, message: 'Simulated charge.succeeded - License would be extended/renewed/issued' }
    when 'charge.failed'
      { success: true, message: 'Simulated charge.failed - User would be warned' }
    when 'charge.refunded'
      { success: true, message: 'Simulated charge.refunded - License would be revoked' }
    when 'customer.subscription.deleted'
      { success: true, message: 'Simulated subscription.deleted - License would be canceled' }
    when 'customer.subscription.created'
      { success: true, message: 'Simulated subscription.created - License would be activated' }
    when 'customer.subscription.paused'
      { success: true, message: 'Simulated subscription.paused - License would be suspended' }
    when 'customer.subscription.resumed'
      { success: true, message: 'Simulated subscription.resumed - License would be un-suspended' }
    when 'customer.subscription.updated'
      { success: true, message: 'Simulated subscription.updated - Subscription changes would be processed' }
    when 'customer.subscription.trial_will_end'
      { success: true, message: 'Simulated trial_will_end - Trial ending notification would be sent' }
    else
      { success: false, error: 'Unknown event type for simulation' }
    end
  end

  def self.simulate_paypal_webhook(event_data)
    payload = event_data.to_json

    # Minimal headers required by PayPal verification
    headers = {
      'PAYPAL-TRANSMISSION-ID' => "sim_#{SecureRandom.hex(8)}",
      'PAYPAL-TRANSMISSION-SIG' => 'simulated',
      'PAYPAL-AUTH-ALGO' => 'SHA256',
      'PAYPAL-CERT-ID' => 'simulated-cert',
      'PAYPAL-TRANSMISSION-TIME' => Time.now.iso8601,
    }

    # Temporarily stub verification to allow simulation in dev environment
    original_verify = begin
      Payments::PaypalProcessor.method(:verify_webhook_signature)
    rescue StandardError
      nil
    end
    Payments::PaypalProcessor.define_singleton_method(:verify_webhook_signature) do |_payload, _headers|
      true
    end

    result = Webhooks::PaypalWebhookHandler.handle_webhook(payload, headers)

    # Restore original method if present
    Payments::PaypalProcessor.define_singleton_method(:verify_webhook_signature, original_verify) if original_verify

    result
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

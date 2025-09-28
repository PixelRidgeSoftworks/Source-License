# frozen_string_literal: true

# Source-License: Webhook Settings Schema
# Defines webhook processing settings with their metadata

class Settings::Schemas::WebhookSchema
  WEBHOOK_SETTINGS = {
    # General Webhook Settings
    'webhooks.enabled' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Enable webhook processing globally',
      web_editable: true,
    },
    'webhooks.base_url' => {
      type: 'url',
      default: 'https://yourdomain.com',
      category: 'webhooks',
      description: 'Base URL for webhook endpoints (used for webhook URL generation)',
      web_editable: true,
    },
    'webhooks.security_token' => {
      type: 'password',
      default: '',
      category: 'webhooks',
      description: 'Global security token for webhook authentication',
      web_editable: true,
      sensitive: true,
    },
    'webhooks.retry_attempts' => {
      type: 'number',
      default: 3,
      category: 'webhooks',
      description: 'Number of retry attempts for failed webhook processing',
      web_editable: true,
    },
    'webhooks.timeout_seconds' => {
      type: 'number',
      default: 30,
      category: 'webhooks',
      description: 'Timeout for webhook processing in seconds',
      web_editable: true,
    },

    # Stripe Webhook Event Settings
    'webhooks.stripe.charge_succeeded' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.succeeded events',
      web_editable: true,
    },
    'webhooks.stripe.charge_failed' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.failed events',
      web_editable: true,
    },
    'webhooks.stripe.charge_refunded' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.refunded events',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_created' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.created events',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_deleted' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.deleted events',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_paused' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.paused events',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_resumed' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.resumed events',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_updated' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.updated events (billing changes, status updates)',
      web_editable: true,
    },
    'webhooks.stripe.customer_subscription_trial_will_end' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe customer.subscription.trial_will_end events (trial ending notifications)',
      web_editable: true,
    },
    'webhooks.stripe.payment_intent_created' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe payment_intent.created events (track payment initiation)',
      web_editable: true,
    },
    'webhooks.stripe.payment_intent_succeeded' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe payment_intent.succeeded events (complete orders)',
      web_editable: true,
    },

    # Additional Stripe Webhook Events (Production Critical)
    'webhooks.stripe.charge_dispute_created' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.dispute.created events (chargeback handling)',
      web_editable: true,
    },
    'webhooks.stripe.charge_dispute_updated' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.dispute.updated events (dispute progress tracking)',
      web_editable: true,
    },
    'webhooks.stripe.charge_dispute_closed' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe charge.dispute.closed events (dispute resolution)',
      web_editable: true,
    },
    'webhooks.stripe.invoice_payment_failed' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe invoice.payment_failed events (subscription payment failures)',
      web_editable: true,
    },
    'webhooks.stripe.invoice_payment_succeeded' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Process Stripe invoice.payment_succeeded events (subscription renewals)',
      web_editable: true,
    },
    'webhooks.stripe.payment_method_attached' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe payment_method.attached events (payment method tracking)',
      web_editable: true,
    },
    'webhooks.stripe.customer_updated' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe customer.updated events (customer data synchronization)',
      web_editable: true,
    },
    'webhooks.stripe.customer_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe customer.created events (new customer tracking)',
      web_editable: true,
    },
    'webhooks.stripe.plan_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe plan.created events (subscription plan tracking)',
      web_editable: true,
    },
    'webhooks.stripe.price_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe price.created events (pricing tier tracking)',
      web_editable: true,
    },
    'webhooks.stripe.product_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe product.created events (product catalog sync)',
      web_editable: true,
    },
    'webhooks.stripe.setup_intent_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe setup_intent.created events (payment setup tracking)',
      web_editable: true,
    },
    'webhooks.stripe.invoice_created' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Process Stripe invoice.created events (billing cycle tracking)',
      web_editable: true,
    },

    # PayPal Webhook Settings
    'webhooks.paypal.enabled' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Enable PayPal webhook processing',
      web_editable: true,
    },
    'webhooks.paypal.webhook_id' => {
      type: 'string',
      default: '',
      category: 'webhooks',
      description: 'PayPal webhook ID for verification',
      web_editable: true,
    },

    # Webhook Notifications
    'webhooks.notifications.enabled' => {
      type: 'boolean',
      default: false,
      category: 'webhooks',
      description: 'Send notifications for webhook events',
      web_editable: true,
    },
    'webhooks.notifications.email' => {
      type: 'email',
      default: '',
      category: 'webhooks',
      description: 'Email address for webhook notifications',
      web_editable: true,
    },
    'webhooks.notifications.slack_webhook_url' => {
      type: 'url',
      default: '',
      category: 'webhooks',
      description: 'Slack webhook URL for webhook notifications',
      web_editable: true,
      sensitive: true,
    },

    # Webhook Logging
    'webhooks.logging.enabled' => {
      type: 'boolean',
      default: true,
      category: 'webhooks',
      description: 'Enable detailed webhook event logging',
      web_editable: true,
    },
    'webhooks.logging.log_level' => {
      type: 'select',
      default: 'info',
      options: %w[debug info warn error],
      category: 'webhooks',
      description: 'Webhook logging level',
      web_editable: true,
    },
    'webhooks.logging.retain_days' => {
      type: 'number',
      default: 30,
      category: 'webhooks',
      description: 'Number of days to retain webhook logs',
      web_editable: true,
    },
  }.freeze

  class << self
    def settings
      WEBHOOK_SETTINGS
    end
  end
end

# frozen_string_literal: true

# Source-License: Payment Settings Schema
# Defines payment processing settings with their metadata

class Settings::Schemas::PaymentSchema
  PAYMENT_SETTINGS = {
    # Stripe Payment Settings
    'payment.stripe.publishable_key' => {
      type: 'string',
      default: '',
      category: 'payment',
      description: 'Stripe publishable key for payment processing',
      web_editable: true,
      sensitive: false,
    },
    'payment.stripe.secret_key' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'Stripe secret key for payment processing',
      web_editable: true,
      sensitive: true,
    },
    'payment.stripe.webhook_secret' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'Stripe webhook secret for security',
      web_editable: true,
      sensitive: true,
    },

    # PayPal Payment Settings
    'payment.paypal.client_id' => {
      type: 'string',
      default: '',
      category: 'payment',
      description: 'PayPal client ID for payment processing',
      web_editable: true,
      sensitive: false,
    },
    'payment.paypal.client_secret' => {
      type: 'password',
      default: '',
      category: 'payment',
      description: 'PayPal client secret for payment processing',
      web_editable: true,
      sensitive: true,
    },
    'payment.paypal.environment' => {
      type: 'select',
      default: 'sandbox',
      options: %w[sandbox production],
      category: 'payment',
      description: 'PayPal environment (sandbox for testing)',
      web_editable: true,
    },
    'payment.paypal.webhook_id' => {
      type: 'string',
      default: '',
      category: 'payment',
      description: 'PayPal webhook ID for payment notifications',
      web_editable: true,
      sensitive: false,
    },
  }.freeze

  class << self
    def settings
      PAYMENT_SETTINGS
    end
  end
end

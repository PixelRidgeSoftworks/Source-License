# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/webhooks/paypal_webhook_handler'
require_relative '../lib/payments/paypal_processor'

class PaypalWebhookTest < Minitest::Test
  def setup
    # Ensure PayPal webhook settings enabled for tests
    SettingsManager.set('webhooks.paypal.payment.sale.completed', true)
    SettingsManager.set('webhooks.paypal.billing.subscription.activated', true)
  end

  def teardown
    SettingsManager.set('webhooks.paypal.payment.sale.completed', false)
    SettingsManager.set('webhooks.paypal.billing.subscription.activated', false)
  end

  def test_invalid_signature_rejected
    payload = { id: 'evt_1', event_type: 'PAYMENT.SALE.COMPLETED' }.to_json
    headers = { 'PAYPAL-TRANSMISSION-ID' => 'tx_1' }

    # Stub verification to false
    Payments::PaypalProcessor.define_singleton_method(:verify_webhook_signature) do |_payload, _headers|
      false
    end

    result = Webhooks::PaypalWebhookHandler.handle_webhook(payload, headers)

    refute result[:success]
    assert_equal 'Invalid signature', result[:error]
  end

  def test_payment_completed_processes_license
    # Create a revoked license to test reactivation path
    order = create_test_order
    license = License.create(
      license_key: "TEST-#{SecureRandom.hex(8).upcase}",
      customer_email: 'paypalpayer@example.com',
      order_id: order.id,
      product_id: order.order_items.first.product_id,
      status: 'revoked',
      max_activations: 5,
      activation_count: 0,
      created_at: Time.now
    )

    payload = {
      id: 'evt_2',
      event_type: 'PAYMENT.SALE.COMPLETED',
      resource: {
        id: 'sale_123',
        amount: { total: '29.99', currency: 'USD' },
        payer: { payer_info: { email: 'paypalpayer@example.com' } },
      },
    }.to_json

    headers = {
      'PAYPAL-TRANSMISSION-ID' => 'tx_2',
      'PAYPAL-TRANSMISSION-SIG' => 'sig',
      'PAYPAL-AUTH-ALGO' => 'SHA256',
      'PAYPAL-CERT-ID' => 'cert',
      'PAYPAL-TRANSMISSION-TIME' => Time.now.iso8601,
    }

    # Stub verification to true
    Payments::PaypalProcessor.define_singleton_method(:verify_webhook_signature) do |_payload, _headers|
      true
    end

    result = Webhooks::PaypalWebhookHandler.handle_webhook(payload, headers)

    assert result[:success]
    assert_includes result[:message], 'Payment success processed'

    license.reload

    assert_predicate license, :active?
  end

  private

  def create_test_order
    product = Product.create(
      name: 'Test Product',
      price: 29.99,
      license_type: 'one_time',
      max_activations: 5,
      license_duration_days: 365
    )

    order = Order.create(
      email: 'test@example.com',
      amount: 29.99,
      currency: 'USD',
      status: 'completed',
      payment_method: 'paypal',
      created_at: Time.now
    )

    OrderItem.create(order_id: order.id, product_id: product.id, quantity: 1, price: 29.99)
    order
  end
end

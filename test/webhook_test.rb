# frozen_string_literal: true

# Source-License: Webhook Tests
# Tests for Stripe webhook functionality

require_relative 'test_helper'
require_relative '../lib/webhooks/stripe_webhook_handler'

class WebhookTest < Minitest::Test
  def setup
    # Enable webhook settings for testing
    SettingsManager.set('webhooks.stripe.charge_succeeded', true)
    SettingsManager.set('webhooks.stripe.charge_failed', true)
    SettingsManager.set('webhooks.stripe.charge_refunded', true)
    SettingsManager.set('webhooks.stripe.customer_subscription_deleted', true)
    SettingsManager.set('webhooks.stripe.customer_subscription_created', true)
    SettingsManager.set('webhooks.stripe.customer_subscription_paused', true)
    SettingsManager.set('webhooks.stripe.customer_subscription_resumed', true)
  end

  def teardown
    # Clean up webhook settings
    SettingsManager.set('webhooks.stripe.charge_succeeded', false)
    SettingsManager.set('webhooks.stripe.charge_failed', false)
    SettingsManager.set('webhooks.stripe.charge_refunded', false)
    SettingsManager.set('webhooks.stripe.customer_subscription_deleted', false)
    SettingsManager.set('webhooks.stripe.customer_subscription_created', false)
    SettingsManager.set('webhooks.stripe.customer_subscription_paused', false)
    SettingsManager.set('webhooks.stripe.customer_subscription_resumed', false)
  end

  def test_webhook_enabled_check
    # Test when webhook is enabled
    assert Webhooks::StripeWebhookHandler.send(:webhook_enabled?, 'charge.succeeded')

    # Test when webhook is disabled
    SettingsManager.set('webhooks.stripe.charge_succeeded', false)

    refute Webhooks::StripeWebhookHandler.send(:webhook_enabled?, 'charge.succeeded')
  end

  def test_find_license_for_charge_with_metadata
    # Create test license
    license = create_test_license

    # Mock charge with metadata
    charge = OpenStruct.new(
      metadata: { 'license_key' => license.license_key },
      customer: nil,
      payment_intent: nil
    )

    found_license = Webhooks::StripeWebhookHandler.send(:find_license_for_charge, charge)

    assert_equal license.id, found_license.id
  end

  def test_find_license_for_charge_with_order_metadata
    # Create test order and license
    order = create_test_order
    license = create_test_license(order: order)

    # Mock charge with order metadata
    charge = OpenStruct.new(
      metadata: { 'order_id' => order.id.to_s },
      customer: nil,
      payment_intent: nil
    )

    found_license = Webhooks::StripeWebhookHandler.send(:find_license_for_charge, charge)

    assert_equal license.id, found_license.id
  end

  def test_charge_succeeded_processing_disabled
    # Disable the webhook
    SettingsManager.set('webhooks.stripe.charge_succeeded', false)

    event = create_mock_event('charge.succeeded')
    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'disabled'
  end

  def test_charge_succeeded_processing_enabled
    # Create test license
    license = create_test_license

    # Mock event and charge
    event = create_mock_event('charge.succeeded')
    charge = create_mock_charge(license_key: license.license_key)
    event.data.object = charge

    # Mock the find_license_for_charge method
    Webhooks::StripeWebhookHandler.define_singleton_method(:find_license_for_charge) do |_charge|
      license
    end

    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'extended/renewed/issued'
  end

  def test_charge_failed_processing
    license = create_test_license

    event = create_mock_event('charge.failed')
    charge = create_mock_charge(license_key: license.license_key, failure_message: 'Card declined')
    event.data.object = charge

    # Mock the find_license_for_charge method
    Webhooks::StripeWebhookHandler.define_singleton_method(:find_license_for_charge) do |_charge|
      license
    end

    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'failure notification sent'
  end

  def test_charge_refunded_processing
    license = create_test_license

    event = create_mock_event('charge.refunded')
    charge = create_mock_charge(
      license_key: license.license_key,
      amount_refunded: 5000 # $50.00 in cents
    )
    event.data.object = charge

    # Mock the find_license_for_charge method
    Webhooks::StripeWebhookHandler.define_singleton_method(:find_license_for_charge) do |_charge|
      license
    end

    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'revoked due to charge refund'

    # Verify license was revoked
    license.reload

    assert_predicate license, :revoked?
  end

  def test_subscription_deleted_processing
    license = create_test_license_with_subscription
    subscription = license.subscription

    event = create_mock_event('customer.subscription.deleted')
    stripe_subscription = create_mock_subscription(subscription.external_subscription_id)
    event.data.object = stripe_subscription

    # Mock the find_subscription_by_external_id method
    Webhooks::StripeWebhookHandler.define_singleton_method(:find_subscription_by_external_id) do |_id|
      subscription
    end

    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'canceled and license revoked'

    # Verify subscription was canceled and license was revoked
    subscription.reload
    license.reload

    assert_predicate subscription, :canceled?
    assert_predicate license, :revoked?
  end

  def test_unhandled_event_type
    event = create_mock_event('unknown.event.type')
    result = Webhooks::StripeWebhookHandler.send(:process_webhook_event, event)

    assert result[:success]
    assert_includes result[:message], 'Unhandled event type'
  end

  private

  def create_test_license(order: nil)
    test_order = order || create_test_order
    License.create(
      license_key: "TEST-#{SecureRandom.hex(8).upcase}",
      customer_email: 'test@example.com',
      order_id: test_order.id,
      product_id: test_order.order_items.first.product_id,
      status: 'active',
      max_activations: 5,
      activation_count: 0,
      created_at: Time.now
    )
  end

  def create_test_license_with_subscription
    license = create_test_license
    Subscription.create(
      license_id: license.id,
      status: 'active',
      current_period_start: Time.now,
      current_period_end: Time.now + (30 * 24 * 60 * 60), # 30 days
      external_subscription_id: "sub_#{SecureRandom.hex(12)}"
    )
    license.reload
    license
  end

  def create_test_order
    product = create_test_product
    order = Order.create(
      email: 'test@example.com',
      amount: 29.99,
      currency: 'USD',
      status: 'completed',
      payment_method: 'stripe',
      created_at: Time.now
    )

    OrderItem.create(
      order_id: order.id,
      product_id: product.id,
      quantity: 1,
      price: 29.99
    )

    order
  end

  def create_test_product
    Product.create(
      name: 'Test Product',
      price: 29.99,
      license_type: 'subscription',
      max_activations: 5,
      license_duration_days: 30
    )
  end

  def create_mock_event(type)
    OpenStruct.new(
      id: "evt_#{SecureRandom.hex(12)}",
      type: type,
      data: OpenStruct.new(object: nil)
    )
  end

  def create_mock_charge(license_key: nil, failure_message: nil, amount_refunded: 0)
    OpenStruct.new(
      id: "ch_#{SecureRandom.hex(12)}",
      amount: 2999, # $29.99 in cents
      amount_refunded: amount_refunded,
      customer: "cus_#{SecureRandom.hex(8)}",
      payment_intent: "pi_#{SecureRandom.hex(12)}",
      failure_message: failure_message,
      metadata: license_key ? { 'license_key' => license_key } : {}
    )
  end

  def create_mock_subscription(external_id = nil)
    OpenStruct.new(
      id: external_id || "sub_#{SecureRandom.hex(12)}",
      status: 'active',
      customer: "cus_#{SecureRandom.hex(8)}",
      current_period_start: Time.now.to_i,
      current_period_end: (Time.now + (30 * 24 * 60 * 60)).to_i,
      cancel_at_period_end: false
    )
  end
end

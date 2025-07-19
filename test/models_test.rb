# frozen_string_literal: true

require_relative 'test_helper'

class ModelsTest < Minitest::Test
  def test_admin_model_creation
    admin = create(:admin, email: 'test@example.com')

    assert admin.id
    assert_equal 'test@example.com', admin.email
    assert admin.password_hash
    refute_nil admin.created_at
  end

  def test_admin_password_validation
    admin = create(:admin)

    # Test password checking (assuming we add this method)
    assert admin.password_hash.start_with?('$2a$')
  end

  def test_product_model_creation
    product = create(:product, name: 'Test Software', price: 99.99)

    assert product.id
    assert_equal 'Test Software', product.name
    assert_in_delta(99.99, product.price.to_f)
    assert_equal 'USD', product.currency
    assert product.active
    refute product.subscription
  end

  def test_product_features_list
    features = ['Feature 1', 'Feature 2', 'Feature 3']
    product = create(:product, features: features.to_json)

    # Test features_list method if implemented
    skip unless product.respond_to?(:features_list)


    assert_equal features, product.features_list
  end

  def test_subscription_product
    product = create(:product, :subscription)

    assert product.subscription
    assert_operator product.price, :<=, 50.0 # Subscription products should be cheaper
  end

  def test_order_model_creation
    order = create(:order, email: 'customer@example.com', amount: 149.99)

    assert order.id
    assert_equal 'customer@example.com', order.email
    assert_in_delta(149.99, order.amount.to_f)
    assert_equal 'pending', order.status
    assert_includes %w[stripe paypal], order.payment_method
  end

  def test_completed_order
    order = create(:order, :completed)

    assert_equal 'completed', order.status
    refute_nil order.completed_at
  end

  def test_order_item_association
    product = create(:product)
    order = create(:order)
    order_item = create(:order_item, order: order, product: product, quantity: 2)

    assert_equal order.id, order_item.order_id
    assert_equal product.id, order_item.product_id
    assert_equal 2, order_item.quantity
    assert_equal product.price, order_item.price
  end

  def test_license_model_creation
    scenario = create_complete_order_with_license
    license = scenario[:license]

    assert license.id
    assert_valid_license_key(license.license_key)
    assert_equal 'active', license.status
    assert_equal 0, license.activation_count
    assert_equal 0, license.download_count
    assert_operator license.max_activations, :>, 0
  end

  def test_license_key_uniqueness
    first_license = create(:license)

    # This should raise an error due to unique constraint
    assert_raises(Sequel::UniqueConstraintViolation, Sequel::DatabaseError) do
      create(:license, license_key: first_license.license_key)
    end
  end

  def test_license_expiration
    license = create(:license, :with_expiration)

    refute_nil license.expires_at
    assert_operator license.expires_at, :>, Time.now
  end

  def test_expired_license
    license = create(:license, :expired)

    assert_equal 'expired', license.status
    assert_operator license.expires_at, :<, Time.now
  end

  def test_license_validation_method
    license = create(:license)

    # Test valid? method if implemented
    skip unless license.respond_to?(:valid?)


    assert_predicate license, :valid?
  end

  def test_suspended_license_validation
    license = create(:license, :suspended)

    assert_equal 'suspended', license.status

    skip unless license.respond_to?(:valid?)


    refute_predicate license, :valid?
  end

  def test_subscription_model
    scenario = create_subscription_scenario
    subscription = scenario[:subscription]

    assert subscription.id
    assert subscription.license_id
    assert subscription.stripe_subscription_id
    assert_equal 'active', subscription.status
    assert_operator subscription.next_billing_date, :>, Time.now
  end

  def test_cancelled_subscription
    subscription = create(:subscription, :cancelled)

    assert_equal 'cancelled', subscription.status
    refute_nil subscription.cancelled_at
  end

  def test_license_activation_model
    license = create(:license)
    activation = create(:license_activation, license: license)

    assert activation.id
    assert_equal license.id, activation.license_id
    assert activation.machine_fingerprint
    assert activation.machine_name
    assert activation.os_info
    refute_nil activation.activated_at
  end

  def test_multiple_activations_for_license
    license = create(:license, max_activations: 3)

    activations = create_list(:license_activation, 2, license: license)

    assert_equal 2, activations.count
    activations.each do |activation|
      assert_equal license.id, activation.license_id
    end
  end

  def test_license_activation_platforms
    license = create(:license)

    windows_activation = create(:license_activation, :windows, license: license)
    macos_activation = create(:license_activation, :macos, license: license)
    linux_activation = create(:license_activation, :linux, license: license)

    assert_includes windows_activation.os_info, 'Windows'
    assert_includes macos_activation.os_info, 'macOS'
    assert_includes linux_activation.os_info.downcase, %w[ubuntu fedora centos debian]
  end

  def test_model_associations
    scenario = create_complete_order_with_license

    product = scenario[:product]
    order = scenario[:order]
    order_item = scenario[:order_item]
    license = scenario[:license]

    # Test associations if implemented
    assert_includes order.order_items.map(&:id), order_item.id if order.respond_to?(:order_items)

    assert_includes order.licenses.map(&:id), license.id if order.respond_to?(:licenses)

    assert_includes product.licenses.map(&:id), license.id if product.respond_to?(:licenses)

    assert_equal product.id, license.product.id if license.respond_to?(:product)

    skip unless license.respond_to?(:order)


    assert_equal order.id, license.order.id
  end

  def test_cascade_deletions
    scenario = create_complete_order_with_license
    order = scenario[:order]
    license = scenario[:license]

    # Create activation for the license
    activation = create(:license_activation, license: license)

    # Delete the order (should cascade to license and activations)
    order.id
    license_id = license.id
    activation_id = activation.id

    order.destroy

    # Verify cascading deletions
    assert_nil License[license_id]
    assert_nil LicenseActivation[activation_id]
  end

  def test_model_validations
    # Test creating models with invalid data

    # Admin without email should fail
    assert_raises(Sequel::NotNullConstraintViolation, Sequel::DatabaseError) do
      Admin.create(password_hash: 'test')
    end

    # Product without name should fail
    assert_raises(Sequel::NotNullConstraintViolation, Sequel::DatabaseError) do
      Product.create(price: 99.99)
    end

    # Order without email should fail
    assert_raises(Sequel::NotNullConstraintViolation, Sequel::DatabaseError) do
      Order.create(amount: 99.99)
    end

    # License without license_key should fail
    product = create(:product)
    assert_raises(Sequel::NotNullConstraintViolation, Sequel::DatabaseError) do
      License.create(product_id: product.id, email: 'test@example.com')
    end
  end

  def test_model_timestamps
    product = create(:product)

    assert product.created_at
    assert product.updated_at
    assert_in_delta Time.now.to_f, product.created_at.to_f, 5.0
  end

  def test_currency_handling
    # Test different currencies
    eur_product = create(:product, price: 89.99, currency: 'EUR')
    gbp_order = create(:order, amount: 149.99, currency: 'GBP')

    assert_equal 'EUR', eur_product.currency
    assert_equal 'GBP', gbp_order.currency
  end

  def test_large_datasets
    # Test handling larger numbers of records
    products = create_list(:product, 10)
    orders = create_list(:order, 5, :completed)

    assert_equal 10, products.count
    assert_equal 5, orders.count

    # All orders should be completed
    orders.each do |order|
      assert_equal 'completed', order.status
    end
  end
end

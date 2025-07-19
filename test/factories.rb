# frozen_string_literal: true

# Factory Bot factories for Source License test data
# Provides consistent test data generation

# Helper method to generate valid license keys
def generate_license_key
  Array.new(4) { Array.new(4) { [*'A'..'Z', *'0'..'9'].sample }.join }.join('-')
end

FactoryBot.define do
  # Admin factory
  factory :admin do
    email { Faker::Internet.email }
    password_hash { BCrypt::Password.create('password123') }
    created_at { Time.now }
    updated_at { Time.now }

    trait :with_custom_email do
      email { 'admin@test.com' }
    end
  end

  # Product factory
  factory :product do
    name { Faker::App.name }
    description { Faker::Lorem.paragraph(sentence_count: 3) }
    price { Faker::Commerce.price(range: 10.0..500.0) }
    currency { 'USD' }
    max_activations { [1, 3, 5, 10].sample }
    version { "#{Faker::Number.between(from: 1, to: 5)}.#{Faker::Number.between(from: 0, to: 9)}.#{Faker::Number.between(from: 0, to: 9)}" }
    download_file { Faker::File.file_name(dir: 'software', ext: 'zip').to_s }
    features { ['Feature 1', 'Feature 2', 'Feature 3'].to_json }
    license_type { 'one_time' }
    active { true }
    created_at { Time.now }
    updated_at { Time.now }

    trait :subscription do
      license_type { 'subscription' }
      license_duration_days { 30 }
      price { Faker::Commerce.price(range: 5.0..50.0) }
    end

    trait :inactive do
      active { false }
    end

    trait :expensive do
      price { Faker::Commerce.price(range: 500.0..2000.0) }
    end

    trait :with_many_activations do
      max_activations { 50 }
    end
  end

  # Order factory
  factory :order do
    email { Faker::Internet.email }
    amount { Faker::Commerce.price(range: 10.0..500.0) }
    currency { 'USD' }
    status { 'pending' }
    payment_method { %w[stripe paypal].sample }
    payment_intent_id { "pi_#{Faker::Alphanumeric.alphanumeric(number: 24)}" }
    created_at { Time.now }
    updated_at { Time.now }

    trait :completed do
      status { 'completed' }
      completed_at { Time.now }
    end

    trait :cancelled do
      status { 'cancelled' }
    end

    trait :processing do
      status { 'processing' }
    end

    trait :with_stripe do
      payment_method { 'stripe' }
      payment_intent_id { "pi_#{Faker::Alphanumeric.alphanumeric(number: 24)}" }
    end

    trait :with_paypal do
      payment_method { 'paypal' }
      payment_intent_id { "PAYID-#{Faker::Alphanumeric.alphanumeric(number: 16).upcase}" }
    end
  end

  # Order Item factory
  factory :order_item do
    order
    product
    quantity { Faker::Number.between(from: 1, to: 3) }
    price { product&.price || Faker::Commerce.price(range: 10.0..500.0) }
    created_at { Time.now }

    trait :multiple_quantity do
      quantity { Faker::Number.between(from: 5, to: 10) }
    end
  end

  # License factory
  factory :license do
    license_key { generate_license_key }
    product
    order factory: %i[order completed]
    customer_email { order&.email || Faker::Internet.email }
    status { 'active' }
    max_activations { product&.max_activations || 3 }
    activation_count { 0 }
    download_count { 0 }
    expires_at { nil }
    created_at { Time.now }
    updated_at { Time.now }

    trait :expired do
      expires_at { 1.day.ago }
      status { 'expired' }
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :revoked do
      status { 'revoked' }
    end

    trait :with_expiration do
      expires_at { 1.year.from_now }
    end

    trait :fully_activated do
      activation_count { max_activations }
    end

    trait :partially_activated do
      activation_count { [max_activations / 2, 1].max }
    end

    trait :frequently_downloaded do
      download_count { Faker::Number.between(from: 10, to: 50) }
      last_downloaded_at { Faker::Time.between(from: 1.month.ago, to: Time.now) }
    end

    trait :recently_activated do
      activation_count { 1 }
      last_activated_at { Faker::Time.between(from: 1.week.ago, to: Time.now) }
    end
  end

  # Subscription factory
  factory :subscription do
    license
    stripe_subscription_id { "sub_#{Faker::Alphanumeric.alphanumeric(number: 24)}" }
    status { 'active' }
    current_period_start { Time.now }
    current_period_end { 1.month.from_now }
    auto_renew { true }
    created_at { Time.now }
    updated_at { Time.now }

    trait :cancelled do
      status { 'cancelled' }
      cancelled_at { Time.now }
    end

    trait :past_due do
      status { 'past_due' }
      current_period_end { 1.week.ago }
    end

    trait :with_paypal do
      stripe_subscription_id { nil }
      paypal_subscription_id { "I-#{Faker::Alphanumeric.alphanumeric(number: 13).upcase}" }
    end

    trait :expiring_soon do
      current_period_end { 3.days.from_now }
    end
  end

  # License Activation factory
  factory :license_activation do
    license
    machine_fingerprint { Faker::Crypto.sha256[0..31] }
    machine_name { Faker::Computer.name }
    os_info { "#{Faker::Computer.os} #{Faker::Computer.version}" }
    activated_at { Faker::Time.between(from: 1.month.ago, to: Time.now) }
    last_seen_at { Faker::Time.between(from: 1.week.ago, to: Time.now) }

    trait :windows do
      os_info { "Windows #{%w[10 11].sample} #{%w[Home Pro Enterprise].sample}" }
    end

    trait :macos do
      os_info { "macOS #{%w[Monterey Ventura Sonoma].sample}" }
    end

    trait :linux do
      os_info { "#{%w[Ubuntu Fedora CentOS Debian].sample} #{Faker::Number.between(from: 18, to: 23)}" }
    end

    trait :recently_seen do
      last_seen_at { Faker::Time.between(from: 1.hour.ago, to: Time.now) }
    end

    trait :stale do
      last_seen_at { Faker::Time.between(from: 6.months.ago, to: 3.months.ago) }
    end
  end

  # Sequences for unique values
  sequence :email do |n|
    "user#{n}@example.com"
  end

  sequence :license_key do |n|
    key_parts = Array.new(4) { Array.new(4) { [*'A'..'Z', *'0'..'9'].sample }.join }
    key_parts[0] = format('%04d', n % 10_000) if n < 10_000
    key_parts.join('-')
  end

  sequence :product_name do |n|
    "#{Faker::App.name} v#{n}"
  end

  sequence :order_id do |n|
    1000 + n
  end

  # Traits for common scenarios
  trait :recent do
    created_at { Faker::Time.between(from: 1.week.ago, to: Time.now) }
    updated_at { created_at }
  end

  trait :old do
    created_at { Faker::Time.between(from: 2.years.ago, to: 1.year.ago) }
    updated_at { Faker::Time.between(from: created_at, to: 6.months.ago) }
  end
end

# Helper methods for factories
module FactoryHelpers
  def create_complete_order_with_license
    product = create(:product)
    order = create(:order, :completed)
    order_item = create(:order_item, order: order, product: product)
    license = create(:license, product: product, order: order, customer_email: order.email)

    { product: product, order: order, order_item: order_item, license: license }
  end

  def create_subscription_scenario
    product = create(:product, :subscription)
    order = create(:order, :completed)
    order_item = create(:order_item, order: order, product: product)
    license = create(:license, product: product, order: order, customer_email: order.email)
    subscription = create(:subscription, license: license)

    { product: product, order: order, order_item: order_item, license: license, subscription: subscription }
  end

  def create_activated_license_scenario
    scenario = create_complete_order_with_license
    license = scenario[:license]

    # Create some activations
    activations = create_list(:license_activation, 2, license: license)
    license.update(activation_count: activations.count, last_activated_at: activations.last.activated_at)

    scenario.merge(activations: activations)
  end

  def create_expired_license_scenario
    scenario = create_complete_order_with_license
    license = scenario[:license]
    license.update(status: 'expired', expires_at: 1.week.ago)

    scenario
  end
end

# Include helper methods in test classes
class Minitest::Test
  include FactoryHelpers
end

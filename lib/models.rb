# frozen_string_literal: true

# Source-License: Database Models
# Sequel models for all database entities

require 'sequel'
require 'bcrypt'
require 'json'

# Base model with common functionality
module BaseModelMethods
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Automatically set updated_at timestamp
  def before_update
    super
    self.updated_at = Time.now if respond_to?(:updated_at)
  end

  # Convert to hash for JSON serialization
  def to_hash_for_api
    values.reject { |k, _| k.to_s.include?('password') }
  end

  module ClassMethods
    # Add any class methods here if needed
  end
end

# Customer/user accounts for license management
class User < Sequel::Model
  include BaseModelMethods
  set_dataset :users
  one_to_many :licenses

  # Hash password before saving
  def password=(new_password)
    self.password_hash = BCrypt::Password.create(new_password)
    self.password_changed_at = Time.now
  end

  # Check if provided password matches
  def password_matches?(password)
    BCrypt::Password.new(password_hash) == password
  end

  # Update last login timestamp
  def update_last_login!(ip_address = nil, user_agent = nil)
    update(
      last_login_at: Time.now,
      last_login_ip: ip_address,
      last_login_user_agent: user_agent,
      login_count: (login_count || 0) + 1
    )
  end

  # Check if account is active
  def active?
    # Support both status field and active boolean field
    if respond_to?(:active) && !self[:active].nil?
      self[:active] == true
    else
      status == 'active'
    end
  end

  # Account status management
  def activate!
    update(status: 'active', activated_at: Time.now)
  end

  def deactivate!
    update(status: 'inactive', deactivated_at: Time.now)
  end

  def suspend!
    update(status: 'suspended', suspended_at: Time.now)
  end

  # Email verification
  def verify_email!
    update(
      email_verified: true,
      email_verified_at: Time.now,
      email_verification_token: nil,
      email_verification_sent_at: nil
    )
  end

  def email_verified?
    email_verified == true
  end

  # Password management
  def clear_password_reset_token!
    update(
      password_reset_token: nil,
      password_reset_sent_at: nil
    )
  end

  def password_reset_token_valid?
    return false unless password_reset_token && password_reset_sent_at

    # Token expires after 1 hour
    Time.now - password_reset_sent_at < 3600
  end

  # Get user's active licenses
  def active_licenses
    licenses_dataset.where(status: 'active')
  end

  # Get user's license count
  def license_count
    licenses_dataset.count
  end

  # Display name (name or email)
  def display_name
    name && !name.empty? ? name : email.split('@').first
  end

  # Account summary
  def account_summary
    {
      total_licenses: license_count,
      active_licenses: active_licenses.count,
      last_login: last_login_at,
      account_age_days: created_at ? ((Time.now - created_at) / (24 * 60 * 60)).ceil : 0,
      email_verified: email_verified?,
    }
  end

  # Validation
  def validate
    super
    errors.add(:email, 'cannot be empty') if !email || email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(email)
      errors.add(:email, 'must be valid email format')
    end
    errors.add(:password_hash, 'cannot be empty') if !password_hash || password_hash.strip.empty?

    # Status validation
    valid_statuses = %w[active inactive suspended]
    errors.add(:status, "must be one of: #{valid_statuses.join(', ')}") unless valid_statuses.include?(status)

    # Email uniqueness validation
    return unless email && User.where(email: email.strip.downcase).exclude(id: id).any?

    errors.add(:email, 'is already taken')
  end

  # Before save hooks
  def before_save
    super
    self.email = email.strip.downcase if email
    self.status ||= 'active'
    self.created_at ||= Time.now
  end

  # Don't expose sensitive data in JSON
  def to_hash_for_api
    super.except(
      :password_hash,
      :password_reset_token,
      :email_verification_token,
      :last_login_user_agent
    )
  end

  # Secure user creation
  def self.create_secure_user(email, password, name = nil)
    user = new
    user.email = email.strip.downcase
    user.password = password
    user.name = name&.strip
    user.status = 'active'
    user.email_verified = false
    user.created_at = Time.now
    user.password_changed_at = Time.now

    user.save_changes if user.valid?

    user
  end
end

# Admin users for managing the system
class Admin < Sequel::Model
  include BaseModelMethods
  set_dataset :admins
  # Hash password before saving
  def password=(new_password)
    self.password_hash = BCrypt::Password.create(new_password)
    self.password_changed_at = Time.now
  end

  # Check if provided password matches
  def password_matches?(password)
    BCrypt::Password.new(password_hash) == password
  end

  # Update last login timestamp with additional info
  def update_last_login!(ip_address = nil, user_agent = nil)
    update(
      last_login_at: Time.now,
      last_login_ip: ip_address,
      last_login_user_agent: user_agent,
      login_count: (login_count || 0) + 1
    )
  end

  # Check if account is active
  def active?
    status == 'active'
  end

  # Account status management
  def activate!
    update(status: 'active', activated_at: Time.now)
  end

  def deactivate!
    update(status: 'inactive', deactivated_at: Time.now)
  end

  def lock!
    update(status: 'locked', locked_at: Time.now)
  end

  def unlock!
    update(status: 'active', unlocked_at: Time.now)
  end

  # Password management
  def force_password_change!
    update(must_change_password: true)
  end

  def password_changed!
    update(must_change_password: false, password_changed_at: Time.now)
  end

  def password_expires_at
    return nil unless password_changed_at

    password_changed_at + (90 * 24 * 60 * 60) # 90 days
  end

  def password_expired?
    return false unless password_expires_at

    Time.now > password_expires_at
  end

  def days_until_password_expires
    return nil unless password_expires_at

    days = ((password_expires_at - Time.now) / (24 * 60 * 60)).ceil
    [days, 0].max
  end

  # Two-factor authentication
  def enable_2fa!(secret)
    update(
      two_factor_secret: secret,
      two_factor_enabled: true,
      two_factor_enabled_at: Time.now
    )
  end

  def disable_2fa!
    update(
      two_factor_secret: nil,
      two_factor_enabled: false,
      two_factor_disabled_at: Time.now
    )
  end

  def two_factor_enabled?
    two_factor_enabled && !two_factor_secret.nil?
  end

  # Account security
  def generate_password_reset_token!
    token = SecureRandom.hex(32)
    update(
      password_reset_token: token,
      password_reset_sent_at: Time.now
    )
    token
  end

  def clear_password_reset_token!
    update(
      password_reset_token: nil,
      password_reset_sent_at: nil
    )
  end

  def password_reset_token_valid?
    return false unless password_reset_token && password_reset_sent_at

    # Token expires after 1 hour
    Time.now - password_reset_sent_at < 3600
  end

  # Security role management
  def role?(role_name)
    roles_list.include?(role_name.to_s)
  end

  def add_role!(role_name)
    current_roles = roles_list
    current_roles << role_name.to_s unless current_roles.include?(role_name.to_s)
    update(roles: current_roles.join(','))
  end

  def remove_role!(role_name)
    current_roles = roles_list
    current_roles.delete(role_name.to_s)
    update(roles: current_roles.join(','))
  end

  def roles_list
    (roles || 'admin').split(',').map(&:strip)
  end

  # Account activity
  def last_activity_summary
    {
      last_login: last_login_at,
      last_ip: last_login_ip,
      login_count: login_count || 0,
      account_age_days: created_at ? ((Time.now - created_at) / (24 * 60 * 60)).ceil : 0,
    }
  end

  # Security validation
  def validate
    super
    errors.add(:email, 'cannot be empty') if !email || email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(email)
      errors.add(:email, 'must be valid email format')
    end
    errors.add(:password_hash, 'cannot be empty') if !password_hash || password_hash.strip.empty?

    # Status validation
    valid_statuses = %w[active inactive locked suspended]
    errors.add(:status, "must be one of: #{valid_statuses.join(', ')}") unless valid_statuses.include?(status)

    # Email uniqueness validation
    return unless email && Admin.where(email: email.strip.downcase).exclude(id: id).any?

    errors.add(:email, 'is already taken')
  end

  # Before save hooks
  def before_save
    super
    self.email = email.strip.downcase if email
    self.status ||= 'active'
    self.created_at ||= Time.now
  end

  # Don't expose sensitive data in JSON
  def to_hash_for_api
    super.except(
      :password_hash,
      :two_factor_secret,
      :password_reset_token,
      :last_login_user_agent
    )
  end

  # Secure admin creation
  def self.create_secure_admin(email, password, roles = ['admin'])
    # Normalize email first to check for existing
    normalized_email = email.strip.downcase
    
    # Check if admin already exists with this email
    existing_admin = Admin.first(email: normalized_email)
    if existing_admin
      puts "Admin with email #{normalized_email} already exists (ID: #{existing_admin.id})"
      return existing_admin
    end

    admin = new
    admin.email = normalized_email
    admin.password = password
    admin.roles = roles.join(',')
    admin.status = 'active'
    admin.created_at = Time.now
    admin.password_changed_at = Time.now

    if admin.valid?
      admin.save_changes
      puts "Created new admin: #{normalized_email} (ID: #{admin.id})"
    else
      puts "Failed to create admin: #{admin.errors.full_messages.join(', ')}"
    end

    admin
  end
end

# Products available for purchase
class Product < Sequel::Model
  include BaseModelMethods
  set_dataset :products
  one_to_many :order_items
  one_to_many :licenses

  # Parse features from JSON
  def features_list
    return [] unless features

    JSON.parse(features)
  rescue JSON::ParserError
    []
  end

  # Set features as JSON
  def features_list=(list)
    self.features = list.to_json
  end

  # Check if product is subscription-based
  def subscription?
    license_type == 'subscription'
  end

  # Check if product is one-time purchase
  def one_time?
    license_type == 'one_time'
  end

  # Get formatted price
  def formatted_price
    "$#{format('%.2f', price)}"
  end

  # Get download file path
  def download_file_path
    return nil unless download_file

    File.join(ENV['DOWNLOADS_PATH'] || './downloads', download_file)
  end

  # Check if download file exists
  def download_file_exists?
    return false unless download_file

    File.exist?(download_file_path)
  end

  # Get billing cycle object
  def billing_cycle_object
    return nil unless billing_cycle

    BillingCycle.by_name(billing_cycle)
  end

  # Get formatted setup fee
  def formatted_setup_fee
    return nil unless setup_fee&.positive?

    "$#{format('%.2f', setup_fee)}"
  end

  # Get total first payment (price + setup fee)
  def total_first_payment
    base_price = price || 0
    fee = setup_fee || 0
    base_price + fee
  end

  # Get formatted total first payment
  def formatted_total_first_payment
    "$#{format('%.2f', total_first_payment)}"
  end

  # Check if product has trial period
  def trial?
    trial_period_days&.positive?
  end

  # Get trial period text
  def trial_period_text
    return 'No trial' unless has_trial?

    if trial_period_days == 1
      '1 day trial'
    elsif trial_period_days < 30
      "#{trial_period_days} day trial"
    elsif trial_period_days == 30
      '1 month trial'
    else
      months = trial_period_days / 30
      remainder = trial_period_days % 30
      if remainder.zero?
        "#{months} month trial"
      else
        "#{months} month, #{remainder} day trial"
      end
    end
  end

  # Get billing frequency text
  def billing_frequency_text
    cycle = billing_cycle_object
    return 'One-time payment' unless cycle

    interval = billing_interval || 1
    if interval == 1
      cycle.display_name
    else
      "Every #{interval} #{cycle.display_name.downcase}"
    end
  end

  # Calculate next billing date from a start date
  def next_billing_date(from_date = Time.now)
    cycle = billing_cycle_object
    return nil unless cycle

    interval = billing_interval || 1
    cycle.next_billing_date(from_date + ((interval - 1) * cycle.days * 24 * 60 * 60))
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:price, 'must be greater than or equal to 0') if !price || price.negative?
    errors.add(:license_type, 'must be one_time or subscription') unless %w[one_time
                                                                            subscription].include?(license_type)
    errors.add(:max_activations, 'must be greater than 0') if !max_activations || max_activations <= 0

    return unless subscription? && (!license_duration_days || license_duration_days <= 0)

    errors.add(:license_duration_days, 'must be set for subscription products')
  end
end

# Customer orders
class Order < Sequel::Model
  include BaseModelMethods
  set_dataset :orders
  one_to_many :order_items
  one_to_many :licenses
  one_to_many :order_taxes

  # Parse payment details from JSON
  def payment_details_hash
    return {} unless payment_details

    JSON.parse(payment_details)
  rescue JSON::ParserError
    {}
  end

  # Set payment details as JSON
  def payment_details_hash=(hash)
    self.payment_details = hash.to_json
  end

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Get formatted subtotal (before taxes)
  def formatted_subtotal
    "$#{format('%.2f', subtotal || 0)}"
  end

  # Get formatted tax total
  def formatted_tax_total
    "$#{format('%.2f', tax_total || 0)}"
  end

  # Check order status
  def pending?
    status == 'pending'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def refunded?
    status == 'refunded'
  end

  # Mark order as completed
  def complete!
    update(status: 'completed', completed_at: Time.now)
  end

  # Calculate subtotal from order items (before taxes)
  def calculate_subtotal
    order_items.sum { |item| item.price * item.quantity }
  end

  # Calculate tax total from order taxes
  def calculate_tax_total
    order_taxes.sum(&:amount)
  end

  # Calculate total (subtotal + taxes)
  def calculate_total
    calculate_subtotal + calculate_tax_total
  end

  # Apply taxes to order
  def apply_taxes!
    # Check if taxes are enabled globally
    return 0.0 unless SettingsManager.get('tax.enable_taxes')

    # Clear existing taxes
    order_taxes_dataset.delete

    subtotal_amount = calculate_subtotal
    return 0.0 if subtotal_amount <= 0

    total_tax = 0.0

    # Only apply taxes if auto-apply is enabled
    if SettingsManager.get('tax.auto_apply_taxes')
      # Apply all active taxes
      Tax.active.each do |tax|
        tax_amount = tax.calculate_amount(subtotal_amount)
        next if tax_amount <= 0

        # Round tax amount if setting is enabled
        if SettingsManager.get('tax.round_tax_amounts')
          tax_amount = tax_amount.round(2)
        end

        add_order_tax(
          tax_id: tax.id,
          tax_name: tax.name,
          rate: tax.rate,
          amount: tax_amount
        )

        total_tax += tax_amount
      end
    end

    # Update order totals
    update(
      subtotal: subtotal_amount,
      tax_total: total_tax,
      amount: subtotal_amount + total_tax,
      tax_applied: true
    )

    total_tax
  end

  # Apply specific taxes to order (for manual tax application)
  def apply_specific_taxes!(tax_ids)
    # Check if taxes are enabled globally
    return 0.0 unless SettingsManager.get('tax.enable_taxes')

    # Clear existing taxes
    order_taxes_dataset.delete

    subtotal_amount = calculate_subtotal
    return 0.0 if subtotal_amount <= 0

    total_tax = 0.0

    # Apply only specified taxes
    Tax.where(id: tax_ids, status: 'active').each do |tax|
      tax_amount = tax.calculate_amount(subtotal_amount)
      next if tax_amount <= 0

      # Round tax amount if setting is enabled
      if SettingsManager.get('tax.round_tax_amounts')
        tax_amount = tax_amount.round(2)
      end

      add_order_tax(
        tax_id: tax.id,
        tax_name: tax.name,
        rate: tax.rate,
        amount: tax_amount
      )

      total_tax += tax_amount
    end

    # Update order totals
    update(
      subtotal: subtotal_amount,
      tax_total: total_tax,
      amount: subtotal_amount + total_tax,
      tax_applied: true
    )

    total_tax
  end

  # Check if taxes are enabled and should be displayed
  def should_display_taxes?
    SettingsManager.get('tax.enable_taxes') && SettingsManager.get('tax.display_tax_breakdown')
  end

  # Check if prices include tax
  def tax_inclusive_pricing?
    SettingsManager.get('tax.include_tax_in_price')
  end

  # Get payment URL (would be set during payment processing)
  def payment_url
    case payment_method
    when 'stripe'
      # This would be set by Stripe payment intent
      payment_details_hash['payment_intent_url'] || payment_details_hash['payment_url']
    when 'paypal'
      # This would be set by PayPal order
      payment_details_hash['approval_url'] || payment_details_hash['payment_url']
    end
  end

  # Add order item to this order
  def add_order_item(product:, quantity:, price:)
    OrderItem.create(
      order_id: id,
      product_id: product.id,
      quantity: quantity,
      price: price
    )
  end

  # Get tax breakdown as hash
  def tax_breakdown
    order_taxes.map do |order_tax|
      {
        name: order_tax.tax_name,
        rate: order_tax.rate,
        amount: order_tax.amount,
        formatted_amount: order_tax.formatted_amount
      }
    end
  end

  # Validation
  def validate
    super
    errors.add(:email, 'cannot be empty') if !email || email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(email)
      errors.add(:email,
                 'must be valid email format')
    end
    errors.add(:amount, 'must be greater than or equal to 0') if !amount || amount.negative?
    errors.add(:status, 'invalid status') unless %w[pending completed failed refunded].include?(status)
    errors.add(:payment_method, 'invalid payment method') unless %w[stripe paypal free manual].include?(payment_method)
  end
end

# Individual items within an order
class OrderItem < Sequel::Model
  include BaseModelMethods
  set_dataset :order_items
  many_to_one :order
  many_to_one :product

  # Calculate line total
  def total
    price * quantity
  end

  # Get formatted price
  def formatted_price
    "$#{format('%.2f', price)}"
  end

  # Get formatted total
  def formatted_total
    "$#{format('%.2f', total)}"
  end

  # Validation
  def validate
    super
    errors.add(:quantity, 'must be greater than 0') if !quantity || quantity <= 0
    errors.add(:price, 'must be greater than or equal to 0') if !price || price.negative?
  end
end

# Software licenses
class License < Sequel::Model
  include BaseModelMethods
  set_dataset :licenses
  many_to_one :order
  many_to_one :product
  many_to_one :user
  one_to_many :license_activations
  one_to_one :subscription

  # Check if license is valid
  def valid?
    return false unless active?
    return false if expired?

    true
  end

  # Check if license is active
  def active?
    status == 'active'
  end

  # Check if license is expired
  def expired?
    return false unless expires_at

    expires_at < Time.now
  end

  # Check if license is revoked
  def revoked?
    status == 'revoked'
  end

  # Check if license is suspended
  def suspended?
    status == 'suspended'
  end

  # Check if more activations are available
  def activations_available?
    activation_count < effective_max_activations
  end

  # Get remaining activations
  def remaining_activations
    effective_max_activations - activation_count
  end

  # Get effective max activations (custom override or product default)
  def effective_max_activations
    custom_max_activations || max_activations || product&.max_activations || 1
  end

  # Get effective expiration date (custom override or product-based)
  def effective_expires_at
    custom_expires_at || expires_at
  end

  # Check if license has custom configuration
  def custom_config?
    custom_max_activations || custom_expires_at
  end

  # Check license type
  def perpetual?
    license_type == 'perpetual'
  end

  def subscription_based?
    license_type == 'subscription'
  end

  def trial?
    license_type == 'trial'
  end

  # Check trial status
  def trial_active?
    trial? && trial_ends_at && trial_ends_at > Time.now
  end

  def trial_expired?
    trial? && trial_ends_at && trial_ends_at <= Time.now
  end

  # Check grace period status
  def in_grace_period?
    grace_period_ends_at && grace_period_ends_at > Time.now
  end

  def grace_period_expired?
    grace_period_ends_at && grace_period_ends_at <= Time.now
  end

  # Start trial period
  def start_trial!(days = nil)
    trial_days = days || product&.trial_period_days || 0
    return false if trial_days <= 0

    update(
      license_type: 'trial',
      trial_ends_at: Time.now + (trial_days * 24 * 60 * 60),
      status: 'active'
    )
  end

  # Convert trial to subscription
  def convert_trial_to_subscription!
    return false unless trial?

    update(
      license_type: 'subscription',
      trial_ends_at: nil
    )

    # Set up subscription if product is subscription-based
    return unless product&.subscription?

    create_subscription_from_product!
  end

  # Enter grace period after failed payment
  def enter_grace_period!
    grace_days = product&.grace_period_days || 7
    update(
      grace_period_ends_at: Time.now + (grace_days * 24 * 60 * 60),
      status: 'active' # Keep active during grace period
    )
  end

  # Create subscription record from product configuration
  def create_subscription_from_product!
    return unless product&.subscription?
    return if subscription # Already has subscription

    cycle = product.billing_cycle_object
    return unless cycle

    now = Time.now
    period_end = cycle.next_billing_date(now)

    Subscription.create(
      license_id: id,
      status: 'active',
      current_period_start: now,
      current_period_end: period_end,
      billing_cycle: product.billing_cycle,
      billing_interval: product.billing_interval || 1,
      next_billing_date: period_end,
      auto_renew: true
    )
  end

  # Activate license for a machine
  def activate!(machine_fingerprint, ip_address = nil, user_agent = nil, system_info = {})
    return false unless valid?
    return false unless activations_available?

    # Check if already activated on this machine
    existing = license_activations_dataset.where(
      machine_fingerprint: machine_fingerprint,
      active: true
    ).first

    return false if existing

    DB.transaction do
      # Create activation record
      add_license_activation(
        machine_fingerprint: machine_fingerprint,
        ip_address: ip_address,
        user_agent: user_agent,
        system_info: system_info.to_json,
        active: true
      )

      # Update activation count
      update(
        activation_count: activation_count + 1,
        last_activated_at: Time.now
      )
    end

    true
  end

  # Deactivate license for a machine
  def deactivate!(machine_fingerprint)
    activation = license_activations_dataset.where(
      machine_fingerprint: machine_fingerprint,
      active: true
    ).first

    return false unless activation

    DB.transaction do
      activation.update(active: false, deactivated_at: Time.now)
      update(activation_count: [0, activation_count - 1].max)
    end

    true
  end

  # Revoke license
  def revoke!
    update(status: 'revoked')
    # Deactivate all activations
    license_activations_dataset.where(active: true).update(
      active: false,
      deactivated_at: Time.now
    )
  end

  # Suspend license
  def suspend!
    update(status: 'suspended')
  end

  # Reactivate suspended license
  def reactivate!
    update(status: 'active')
  end

  # Set expiration date based on product
  def set_expiration_from_product!
    return unless product.subscription? && product.license_duration_days

    start_date = subscription&.current_period_start || created_at
    self.expires_at = start_date + (product.license_duration_days * 24 * 60 * 60)
    save_changes
  end

  # Extend license (for renewals)
  def extend!(days)
    current_expiry = expires_at || Time.now
    self.expires_at = current_expiry + (days * 24 * 60 * 60)
    save_changes
  end

  # Validation
  def validate
    super
    errors.add(:license_key, 'cannot be empty') if !license_key || license_key.strip.empty?
    errors.add(:customer_email, 'cannot be empty') if !customer_email || customer_email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(customer_email)
      errors.add(:customer_email,
                 'must be valid email format')
    end
    errors.add(:status, 'invalid status') unless %w[active suspended revoked expired].include?(status)
    errors.add(:max_activations, 'must be greater than 0') if !max_activations || max_activations <= 0
  end
end

# Subscription management for recurring licenses
class Subscription < Sequel::Model
  include BaseModelMethods
  set_dataset :subscriptions
  many_to_one :license

  # Check if subscription is active
  def active?
    status == 'active' && current_period_end > Time.now
  end

  # Check if subscription is canceled
  def canceled?
    status == 'canceled'
  end

  # Check if subscription is past due
  def past_due?
    status == 'past_due'
  end

  # Check if subscription is in current period
  def in_current_period?
    now = Time.now
    now.between?(current_period_start, current_period_end)
  end

  # Cancel subscription
  def cancel!
    update(status: 'canceled', canceled_at: Time.now, auto_renew: false)
  end

  # Renew subscription for next period
  def renew!(next_period_start, next_period_end)
    update(
      current_period_start: next_period_start,
      current_period_end: next_period_end,
      status: 'active'
    )

    # Extend license
    license.extend!(license.product.license_duration_days)
  end

  # Validation
  def validate
    super
    errors.add(:status, 'invalid status') unless %w[active canceled past_due unpaid].include?(status)
    errors.add(:current_period_start, 'cannot be empty') unless current_period_start
    errors.add(:current_period_end, 'cannot be empty') unless current_period_end
    return unless current_period_end && current_period_start && current_period_end <= current_period_start

    errors.add(:current_period_end,
               'must be after start')
  end
end

# License activation tracking
class LicenseActivation < Sequel::Model
  include BaseModelMethods
  set_dataset :license_activations
  many_to_one :license

  # Parse system info from JSON
  def system_info_hash
    return {} unless system_info

    JSON.parse(system_info)
  rescue JSON::ParserError
    {}
  end

  # Set system info as JSON
  def system_info_hash=(hash)
    self.system_info = hash.to_json
  end

  # Deactivate this activation
  def deactivate!
    update(active: false, deactivated_at: Time.now)
  end

  # Validation
  def validate
    super
    errors.add(:machine_fingerprint, 'cannot be empty') if !machine_fingerprint || machine_fingerprint.strip.empty?
  end
end

# Billing cycles for subscription management
class BillingCycle < Sequel::Model
  include BaseModelMethods
  set_dataset :billing_cycles

  # Get all active billing cycles
  def self.active
    where(active: true)
  end

  # Get billing cycle by name
  def self.by_name(name)
    where(name: name).first
  end

  # Calculate next billing date from a start date
  def next_billing_date(from_date = Time.now)
    from_date + (days * 24 * 60 * 60)
  end

  # Get Stripe-compatible interval
  def stripe_pricing_config
    {
      interval: stripe_interval,
      interval_count: stripe_interval_count,
    }
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:display_name, 'cannot be empty') if !display_name || display_name.strip.empty?
    errors.add(:days, 'must be greater than 0') if !days || days <= 0
    errors.add(:stripe_interval, 'must be week, month, or year') unless %w[week month year].include?(stripe_interval)
    errors.add(:stripe_interval_count, 'must be greater than 0') if !stripe_interval_count || stripe_interval_count <= 0
  end
end

# Subscription billing history tracking
class SubscriptionBillingHistory < Sequel::Model
  include BaseModelMethods
  set_dataset :subscription_billing_histories
  many_to_one :subscription

  # Check payment status
  def paid?
    status == 'paid'
  end

  def failed?
    status == 'failed'
  end

  def pending?
    status == 'pending'
  end

  def refunded?
    status == 'refunded'
  end

  # Mark as paid
  def mark_paid!(payment_date = Time.now)
    update(status: 'paid', paid_at: payment_date)
  end

  # Mark as failed
  def mark_failed!(reason = nil)
    update(status: 'failed', failed_at: Time.now, failure_reason: reason)
  end

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Get billing period duration in days
  def period_duration_days
    ((billing_period_end - billing_period_start) / (24 * 60 * 60)).round
  end

  # Validation
  def validate
    super
    errors.add(:amount, 'must be greater than 0') if !amount || amount <= 0
    errors.add(:status, 'invalid status') unless %w[pending paid failed refunded].include?(status)
    errors.add(:billing_period_start, 'cannot be empty') unless billing_period_start
    errors.add(:billing_period_end, 'cannot be empty') unless billing_period_end
    return unless billing_period_end && billing_period_start && billing_period_end <= billing_period_start

    errors.add(:billing_period_end, 'must be after start')
  end
end

# Tax configurations for orders
class Tax < Sequel::Model
  include BaseModelMethods
  set_dataset :taxes
  one_to_many :order_taxes

  # Check if tax is active
  def active?
    status == 'active'
  end

  # Get formatted rate as percentage
  def formatted_rate
    "#{format('%.2f', rate)}%"
  end

  # Calculate tax amount for a given subtotal
  def calculate_amount(subtotal)
    return 0.0 unless active? && rate > 0

    (subtotal * rate / 100.0).round(2)
  end

  # Activate tax
  def activate!
    update(status: 'active')
  end

  # Deactivate tax
  def deactivate!
    update(status: 'inactive')
  end

  # Get all active taxes
  def self.active
    where(status: 'active').order(:name)
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:rate, 'must be greater than or equal to 0') if !rate || rate < 0
    errors.add(:rate, 'must be less than 100') if rate && rate >= 100
    errors.add(:status, 'invalid status') unless %w[active inactive].include?(status)
  end

  # Before save hooks
  def before_save
    super
    self.name = name.strip if name
    self.status ||= 'active'
    self.created_at ||= Time.now
  end
end

# Order tax tracking
class OrderTax < Sequel::Model
  include BaseModelMethods
  set_dataset :order_taxes
  many_to_one :order
  many_to_one :tax

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Validation
  def validate
    super
    errors.add(:amount, 'must be greater than or equal to 0') if !amount || amount < 0
    errors.add(:rate, 'must be greater than or equal to 0') if !rate || rate < 0
  end
end

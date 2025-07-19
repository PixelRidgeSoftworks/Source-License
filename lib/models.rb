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
  def has_role?(role_name)
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
    admin = new
    admin.email = email.strip.downcase
    admin.password = password
    admin.roles = roles.join(',')
    admin.status = 'active'
    admin.created_at = Time.now
    admin.password_changed_at = Time.now

    admin.save_changes if admin.valid?

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

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:price, 'must be greater than 0') if !price || price <= 0
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

  # Calculate total from order items
  def calculate_total
    order_items.sum { |item| item.price * item.quantity }
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

  # Validation
  def validate
    super
    errors.add(:email, 'cannot be empty') if !email || email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(email)
      errors.add(:email,
                 'must be valid email format')
    end
    errors.add(:amount, 'must be greater than 0') if !amount || amount <= 0
    errors.add(:status, 'invalid status') unless %w[pending completed failed refunded].include?(status)
    errors.add(:payment_method, 'invalid payment method') unless %w[stripe paypal].include?(payment_method)
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
    errors.add(:price, 'must be greater than 0') if !price || price <= 0
  end
end

# Software licenses
class License < Sequel::Model
  include BaseModelMethods
  set_dataset :licenses
  many_to_one :order
  many_to_one :product
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
    activation_count < max_activations
  end

  # Get remaining activations
  def remaining_activations
    max_activations - activation_count
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

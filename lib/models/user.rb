# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'
require 'bcrypt'

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
    unless /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i.match?(email)
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

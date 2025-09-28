# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'
require 'bcrypt'
require 'securerandom'

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
    unless /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i.match?(email)
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

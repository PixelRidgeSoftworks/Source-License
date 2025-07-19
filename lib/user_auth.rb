# frozen_string_literal: true

# Source-License: User Authentication System
# Handles customer/user authentication for license management

require 'bcrypt'
require 'securerandom'

module UserAuthHelpers
  # Check if user is logged in via session
  def user_logged_in?
    session[:user_logged_in] == true && session[:user_id]
  end

  # Get current user ID from session
  def current_user_id
    session[:user_id]
  end

  # Get current user object
  def current_user
    return nil unless user_logged_in?

    @current_user ||= User.first(id: current_user_id)
  end

  # Require user authentication for protected routes
  def require_user_auth
    return if user_logged_in?

    if request.xhr? || content_type == 'application/json'
      halt 401, { error: 'Authentication required' }.to_json
    else
      session[:return_to] = request.fullpath
      redirect '/login'
    end
  end

  # Create user session
  def create_user_session(user)
    session[:user_logged_in] = true
    session[:user_id] = user.id
    session[:user_email] = user.email
  end

  # Clear user session
  def clear_user_session
    session.delete(:user_logged_in)
    session.delete(:user_id)
    session.delete(:user_email)
  end

  # Authenticate user credentials
  def authenticate_user(email, password)
    return { success: false, error: 'Email and password required' } unless email && password

    user = User.first(email: email.strip.downcase)
    return { success: false, error: 'Invalid email or password' } unless user
    return { success: false, error: 'Account is not active' } unless user.active?
    return { success: false, error: 'Invalid email or password' } unless user.password_matches?(password)

    # Update last login
    user.update_last_login!(request.ip, request.user_agent)

    { success: true, user: user }
  end

  # Register new user
  def register_user(email, password, name = nil)
    return { success: false, error: 'Email and password required' } unless email && password
    return { success: false, error: 'Password must be at least 8 characters' } if password.length < 8

    email = email.strip.downcase

    # Check if user already exists
    return { success: false, error: 'An account with this email already exists' } if User.first(email: email)

    begin
      user = User.create(
        email: email,
        name: name&.strip,
        password: password,
        status: 'active',
        email_verified: false, # Will need email verification
        created_at: Time.now
      )

      if user.valid?
        { success: true, user: user }
      else
        { success: false, error: user.errors.full_messages.join(', ') }
      end
    rescue StandardError => e
      { success: false, error: "Registration failed: #{e.message}" }
    end
  end

  # Generate email verification token
  def generate_email_verification_token(user)
    token = SecureRandom.hex(32)
    user.update(
      email_verification_token: token,
      email_verification_sent_at: Time.now
    )
    token
  end

  # Verify email verification token
  def verify_email_token(token)
    return nil unless token

    user = User.first(email_verification_token: token)
    return nil unless user
    return nil unless user.email_verification_sent_at

    # Token expires after 24 hours
    return nil if Time.now - user.email_verification_sent_at > 24 * 60 * 60

    user
  end

  # Generate password reset token
  def generate_password_reset_token(email)
    user = User.first(email: email.strip.downcase)
    return nil unless user

    token = SecureRandom.hex(32)
    user.update(
      password_reset_token: token,
      password_reset_sent_at: Time.now
    )

    { user: user, token: token }
  end

  # Verify password reset token
  def verify_password_reset_token(token)
    return nil unless token

    user = User.first(password_reset_token: token)
    return nil unless user
    return nil unless user.password_reset_sent_at

    # Token expires after 1 hour
    return nil if Time.now - user.password_reset_sent_at > 60 * 60

    user
  end

  # Reset password with token
  def reset_password_with_token(token, new_password)
    user = verify_password_reset_token(token)
    return { success: false, error: 'Invalid or expired reset token' } unless user
    return { success: false, error: 'Password must be at least 8 characters' } if new_password.length < 8

    user.password = new_password
    user.password_reset_token = nil
    user.password_reset_sent_at = nil
    user.password_changed_at = Time.now

    if user.save_changes
      { success: true, user: user }
    else
      { success: false, error: user.errors.full_messages.join(', ') }
    end
  end

  # Check if user owns a specific license
  def user_owns_license?(user, license)
    return false unless user && license

    license.user_id == user.id
  end

  # Get user's licenses
  def get_user_licenses(user)
    return [] unless user

    License.where(user_id: user.id).order(Sequel.desc(:created_at))
  end

  # Transfer licenses from email to user account
  def transfer_licenses_to_user(user, email)
    return 0 unless user && email

    # Find licenses that match the email but don't have a user_id yet
    licenses = License.where(customer_email: email.strip.downcase, user_id: nil)
    count = licenses.count

    # Update all matching licenses to belong to this user
    licenses.update(user_id: user.id) if count.positive?

    count
  end

  # Rate limiting for login attempts
  def check_login_rate_limit(_email)
    # Simple rate limiting: max 5 attempts per 15 minutes per email

    # In a real implementation, you'd use Redis or a proper cache
    # For now, we'll use a simple file-based approach or just return false (no limit)
    false # No rate limit exceeded
  end

  # Record failed login attempt
  def record_failed_login(email)
    # Record the failed attempt for rate limiting
    # Implementation would depend on your caching strategy
  end
end

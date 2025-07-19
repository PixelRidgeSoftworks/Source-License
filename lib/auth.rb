# frozen_string_literal: true

# Source-License: Authentication Helpers
# Handles admin authentication and JWT token management

require 'jwt'
require 'bcrypt'

module AuthHelpers
  # Check if admin is logged in via session
  def admin_logged_in?
    session[:admin_logged_in] == true
  end

  # Get current admin email from session
  def current_admin_email
    session[:admin_email]
  end

  # Get current admin object
  def current_admin
    return nil unless admin_logged_in?

    @current_admin ||= Admin.first(email: current_admin_email)
  end

  # Require admin authentication for protected routes
  def require_admin_auth
    return if admin_logged_in?

    if request.xhr? || content_type == 'application/json'
      halt 401, { error: 'Authentication required' }.to_json
    else
      session[:return_to] = request.fullpath
      redirect '/admin/login'
    end
  end

  # Authenticate admin credentials
  def authenticate_admin(email, password)
    return false unless email && password

    admin = Admin.first(email: email.strip.downcase)
    return false unless admin&.active
    return false unless admin.password_matches?(password)

    # Update last login timestamp
    admin.update_last_login!

    true
  end

  # Generate JWT token for API authentication
  # 24 hours default
  def generate_jwt_token(email, expires_in = 24 * 60 * 60)
    payload = {
      email: email,
      exp: Time.now.to_i + expires_in,
      iat: Time.now.to_i,
    }

    JWT.encode(payload, jwt_secret, 'HS256')
  end

  # Verify JWT token
  def verify_jwt_token(token)
    JWT.decode(token, jwt_secret, true, { algorithm: 'HS256' })
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end

  # Extract JWT token from request headers
  def extract_jwt_token
    auth_header = request.env['HTTP_AUTHORIZATION']
    return nil unless auth_header

    # Expected format: "Bearer <token>"
    parts = auth_header.split
    return nil unless parts.length == 2 && parts[0] == 'Bearer'

    parts[1]
  end

  # Require valid JWT token for API endpoints
  def require_valid_api_token
    token = extract_jwt_token
    halt 401, { error: 'Authorization header required' }.to_json unless token

    decoded = verify_jwt_token(token)
    halt 401, { error: 'Invalid or expired token' }.to_json unless decoded

    # Store admin info for use in the request
    @api_admin_email = decoded[0]['email']
    @api_admin = Admin.first(email: @api_admin_email)

    return if @api_admin&.active

    halt 401, { error: 'Invalid user' }.to_json
  end

  # Get current API admin
  def current_api_admin
    @api_admin
  end

  # Generate secure random password
  def generate_secure_password(length = 16)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['!', '@', '#', '$', '%', '^', '&', '*']
    Array.new(length) { chars.sample }.join
  end

  # Hash password using BCrypt
  def hash_password(password)
    BCrypt::Password.create(password)
  end

  # Verify password against hash
  def verify_password(password, hash)
    BCrypt::Password.new(hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Generate API key for external integrations
  def generate_api_key
    SecureRandom.hex(32)
  end

  # Rate limiting helpers (basic implementation)
  def rate_limit_key(identifier = nil)
    identifier ||= request.ip
    "rate_limit:#{identifier}"
  end

  def rate_limit_exceeded?(_max_requests = 100, _window = 3600, _identifier = nil)
    # This is a basic implementation - in production you might want to use Redis
    # For now, we'll just return false (no rate limiting - not exceeded)
    false
  end

  private

  # Get JWT secret from environment or generate one
  def jwt_secret
    ENV['JWT_SECRET'] || ENV['APP_SECRET'] || 'default_jwt_secret_change_me'
  end
end

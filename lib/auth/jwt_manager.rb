# frozen_string_literal: true

# Source-License: JWT Token Management Module
# Handles JWT token generation, validation, and API authentication

module Auth::JWTManager
  include BaseAuth

  #
  # JWT TOKEN MANAGEMENT
  #

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

  #
  # API KEY MANAGEMENT
  #

  # Generate API key for external integrations
  def generate_api_key
    SecureRandom.hex(32)
  end
end

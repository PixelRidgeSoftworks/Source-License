# frozen_string_literal: true

# Source-License: CSRF Protection Module
# Centralized CSRF token management and validation

require 'securerandom'

# CSRF Protection module - handles token generation and validation
# Usage: Include as helper in Sinatra app, use before filter for validation
module CsrfProtection
  # HTTP methods that don't require CSRF protection (safe/idempotent)
  SAFE_METHODS = %w[GET HEAD OPTIONS TRACE].freeze

  # Canonical parameter name for CSRF tokens
  TOKEN_PARAM = 'csrf_token'

  # Header name for AJAX requests
  TOKEN_HEADER = 'HTTP_X_CSRF_TOKEN'

  # Legacy parameter names to check (for backward compatibility)
  LEGACY_PARAMS = %w[_token authenticity_token].freeze

  class << self
    # Check if HTTP method is safe (doesn't modify state)
    def safe_method?(method)
      SAFE_METHODS.include?(method.to_s.upcase)
    end

    # Validate CSRF token from request
    # @param session [Hash] Rack session
    # @param params [Hash] Request parameters
    # @param request [Sinatra::Request] The request object
    # @return [Boolean] true if token is valid
    def valid_token?(session, params, request)
      expected_token = session[:csrf_token]
      return false unless expected_token

      # Check canonical parameter first
      submitted_token = params[TOKEN_PARAM]

      # Check header (for AJAX requests)
      submitted_token ||= request.env[TOKEN_HEADER]

      # Check legacy parameter names for backward compatibility
      LEGACY_PARAMS.each do |legacy_param|
        submitted_token ||= params[legacy_param]
      end

      return false unless submitted_token

      # Secure constant-time comparison to prevent timing attacks
      secure_compare?(submitted_token.to_s, expected_token.to_s)
    end

    # Generate a new CSRF token
    # @return [String] 64-character hex token
    def generate_token
      SecureRandom.hex(32)
    end

    private

    # Constant-time string comparison to prevent timing attacks
    def secure_compare?(str_a, str_b)
      return false unless str_a.bytesize == str_b.bytesize

      l = str_a.unpack('C*')
      r = 0
      i = -1
      str_b.each_byte { |v| r |= v ^ l[i += 1] }
      r.zero?
    end
  end
end

# Helper methods to include in Sinatra app
module CsrfHelpers
  # Get or generate CSRF token for current session
  def csrf_token
    session[:csrf_token] ||= CsrfProtection.generate_token
  end

  # Generate hidden input field with CSRF token (include legacy authenticity_token)
  def csrf_input
    %(<input type="hidden" name="authenticity_token" value="#{csrf_token}">) +
      %(<input type="hidden" name="#{CsrfProtection::TOKEN_PARAM}" value="#{csrf_token}">)
  end

  # Generate meta tag for JavaScript access
  def csrf_meta_tag
    %(<meta name="csrf-token" content="#{csrf_token}">)
  end

  # Check if current request method is safe
  def csrf_safe_request?
    CsrfProtection.safe_method?(request.request_method)
  end

  # Validate CSRF token for current request
  # @return [Boolean] true if valid or safe method
  def valid_csrf_token?
    return true if csrf_safe_request?

    CsrfProtection.valid_token?(session, params, request)
  end

  # Halt with 403 if CSRF token is invalid
  def require_valid_csrf_token!
    return if valid_csrf_token?

    if request.xhr? || request.content_type&.include?('application/json')
      halt 403, { 'Content-Type' => 'application/json' }, { success: false, error: 'Invalid CSRF token' }.to_json
    else
      halt 403, 'Invalid CSRF token'
    end
  end
end

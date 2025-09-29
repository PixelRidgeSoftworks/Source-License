# frozen_string_literal: true

# Source-License: Unified Authentication System
# Comprehensive authentication with security features, JWT support, and admin/user management

# Define the Auth module namespace first
module Auth
end

# Load all authentication modules
require_relative 'auth/base_auth'
require_relative 'auth/legacy_auth'
require_relative 'auth/secure_auth'
require_relative 'auth/session_manager'
require_relative 'auth/security_features'
require_relative 'auth/jwt_manager'
require_relative 'auth/password_manager'

module AuthHelpers
  # Include all authentication modules to maintain backward compatibility
  include Auth::BaseAuth
  include Auth::LegacyAuth
  include Auth::SecureAuth
  include Auth::SessionManager
  include Auth::SecurityFeatures
  include Auth::JWTManager
  include Auth::PasswordManager
end

# Alias for backward compatibility
EnhancedAuthHelpers = AuthHelpers

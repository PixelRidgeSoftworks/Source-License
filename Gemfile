# frozen_string_literal: true

source 'https://rubygems.org'

# Ruby version
ruby '3.4.7'

# Core web framework
gem 'puma'
gem 'rack'
gem 'rack-cors'
gem 'rack-protection'
gem 'rack-ssl-enforcer'
gem 'rackup'
gem 'sinatra'
gem 'sinatra-contrib'

# Database
gem 'mysql2' # MySQL driver
# gem 'pg', '~> 1.5'             # PostgreSQL driver (temporarily disabled)
gem 'sequel'
# SQLite3 - using specific version that compiles properly on Ruby 3.4
gem 'sqlite3', '~> 2.8.0'

# Authentication & Security
gem 'bcrypt'
gem 'jwt'
gem 'rack-attack'

# Two-Factor Authentication
gem 'rotp'           # TOTP (Time-based One-Time Password)
gem 'rqrcode'        # QR Code generation for TOTP setup
gem 'webauthn'       # WebAuthn for hardware keys and biometric auth

# HTTP & JSON
gem 'json'
gem 'net-http'

# Email
gem 'mail'

# Environment & Configuration
gem 'dotenv'

# Payment Processing
gem 'stripe'

# Utilities
gem 'securerandom'

# API Documentation
gem 'rswag'
gem 'rswag-api'
gem 'rswag-ui'

# Optional caching and session storage
gem 'redis', require: false

group :development, :test do
  # Code Quality & Linting
  gem 'erb_lint'
  gem 'fiddle'
  gem 'rubocop'
  gem 'rubocop-factory_bot'
  gem 'rubocop-minitest'
  gem 'rubocop-performance'
  gem 'rubocop-sequel'


  # Testing Framework
  gem 'database_cleaner-sequel'
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'rack-test'
  # Test Data & Mocking
  gem 'factory_bot'
  gem 'faker'
  gem 'vcr'
  gem 'webmock'

  # Coverage
  gem 'simplecov'
  gem 'simplecov-console'
end

group :development do
  # Development tools
  gem 'rerun'
end

group :test do
  # Test-specific gems
end

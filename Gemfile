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
gem 'sqlite3' # SQLite driver for development/testing

# Authentication & Security
gem 'bcrypt'
gem 'jwt'
gem 'rack-attack'

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

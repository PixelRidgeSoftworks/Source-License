# frozen_string_literal: true

source 'https://rubygems.org'

# Ruby version
ruby '3.4.4'

# Core web framework
gem 'puma', '~> 6.4'
gem 'rack', '~> 3.2.3'
gem 'rack-cors', '~> 2.0'
gem 'rack-protection', '~> 4.2.1'
gem 'rack-ssl-enforcer', '~> 0.2'
gem 'rackup', '~> 2.2'
gem 'sinatra', '~> 4.2'
gem 'sinatra-contrib', '~> 4.2'

# Database
gem 'mysql2', '~> 0.5.5' # MySQL driver
# gem 'pg', '~> 1.5'             # PostgreSQL driver (temporarily disabled)
gem 'sequel', '~> 5.97'
gem 'sqlite3', '~> 1.6' # SQLite driver for development/testing

# Authentication & Security
gem 'bcrypt', '~> 3.1'
gem 'jwt', '~> 2.7'
gem 'rack-attack', '~> 6.7'

# HTTP & JSON
gem 'json', '~> 2.15'
gem 'net-http', '~> 0.4'

# Email
gem 'mail', '~> 2.8'

# Environment & Configuration
gem 'dotenv', '~> 3.1'

# Payment Processing
gem 'stripe', '~> 10.0'

# Utilities
gem 'securerandom', '~> 0.3'

# Optional caching and session storage
gem 'redis', '~> 5.0', require: false

group :development, :test do
  # Code Quality & Linting
  gem 'erb_lint', '~> 0.9.0'
  gem 'fiddle'
  gem 'rubocop', '~> 1.57'
  gem 'rubocop-factory_bot', '~> 2.27'
  gem 'rubocop-minitest', '~> 0.32'
  gem 'rubocop-performance', '~> 1.19'
  gem 'rubocop-sequel', '~> 0.3'


  # Testing Framework
  gem 'database_cleaner-sequel', '~> 2.0'
  gem 'minitest', '~> 5.20'
  gem 'minitest-reporters', '~> 1.6'
  gem 'rack-test', '~> 2.1'

  # Test Data & Mocking
  gem 'factory_bot', '~> 6.4'
  gem 'faker', '~> 3.2'
  gem 'vcr', '~> 6.2'
  gem 'webmock', '~> 3.19'

  # Coverage
  gem 'simplecov', '~> 0.22'
  gem 'simplecov-console', '~> 0.9'
end

group :development do
  # Development tools
  gem 'rerun', '~> 0.14'
end

group :test do
  # Test-specific gems
end

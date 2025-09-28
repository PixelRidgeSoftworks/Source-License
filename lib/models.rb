# frozen_string_literal: true

# Source-License: Database Models
# Sequel models for all database entities

require 'sequel'
require 'bcrypt'
require 'json'

# Require all individual model files
require_relative 'models/base_model_methods'
require_relative 'models/user'
require_relative 'models/admin'
require_relative 'models/product'
require_relative 'models/order'
require_relative 'models/order_item'
require_relative 'models/license'
require_relative 'models/subscription'
require_relative 'models/license_activation'
require_relative 'models/billing_cycle'
require_relative 'models/subscription_billing_history'
require_relative 'models/tax'
require_relative 'models/order_tax'

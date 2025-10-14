#!/usr/bin/env ruby
# frozen_string_literal: true

# Source-License: Main Application File
# Ruby/Sinatra License Management System
# This is the main entry point for the application

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cookies'
require 'dotenv/load'
require 'bcrypt'
require 'jwt'
require 'json'
require 'sequel'
require 'securerandom'
require 'mail'
require 'fileutils'

# Load application modules
require_relative 'lib/database'

# Set up database connection BEFORE loading models
Database.setup

require_relative 'lib/models'
require_relative 'lib/helpers'
require_relative 'lib/customization'
require_relative 'lib/payment_processor'
require_relative 'lib/license_generator'
require_relative 'lib/auth'
require_relative 'lib/user_auth'
require_relative 'lib/security'
require_relative 'lib/logger'
require_relative 'lib/settings_manager'

# Load the modularized application
require_relative 'lib/controllers/application'
require_relative 'lib/controllers/swagger_controller'

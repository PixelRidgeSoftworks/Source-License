# frozen_string_literal: true

require_relative '../../csrf_protection'

# Base controller class for Source License
# All controllers should inherit from this or include BaseController module
#
# This provides:
# - Security headers
# - Rate limiting
# - Common helper modules
# - Error handling for API vs web endpoints
#
# Usage for modular controllers (current pattern):
#   module MyController
#     def self.included(base)
#       base.include BaseController
#       base.configure_controller
#     end
#   end
#
# Usage for class-based controllers (Sinatra subclass pattern):
#   class MyController < BaseControllerClass
#     get '/my-route' do
#       # route logic
#     end
#   end
module BaseController
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Configure common settings for all controllers
    def configure_controller
      # Set security headers and rate limiting for all requests
      before do
        # Skip security features in test environment only
        is_test = ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'
        next if is_test

        set_security_headers

        # Rate limiting for sensitive endpoints
        if request.path_info.start_with?('/admin', '/api')
          enforce_rate_limit(50, 3600) # 50 requests per hour for admin/api
        else
          enforce_rate_limit(200, 3600) # 200 requests per hour for public
        end
      end

      # Include helper modules
      helpers do
        include AuthHelpers
        include EnhancedAuthHelpers
        include UserAuthHelpers
        include TemplateHelpers
        include LicenseHelpers
        include OrderHelpers
        include CustomerHelpers
        include AdminHelpers
        include CustomizationHelpers
        include SecurityHelpers
        include ReportsHelpers
        include CsrfHelpers
      end

      # Error handling - different responses for API vs web endpoints
      error 404 do
        if request.path_info.start_with?('/api/')
          content_type :json
          status 404
          { success: false, error: 'Not found' }.to_json
        else
          erb :'../errors/404', layout: :'layouts/main_layout'
        end
      end

      error 500 do
        if request.path_info.start_with?('/api/')
          content_type :json
          status 500
          { success: false, error: 'Internal server error' }.to_json
        else
          erb :'../errors/500', layout: :'layouts/main_layout'
        end
      end
    end
  end
end

# Class-based controller for future refactoring
# Controllers can inherit from this instead of using the module pattern
class BaseControllerClass < Sinatra::Base
  register Sinatra::Contrib

  # Include all helper modules
  helpers do
    include AuthHelpers
    include EnhancedAuthHelpers
    include UserAuthHelpers
    include TemplateHelpers
    include LicenseHelpers
    include OrderHelpers
    include CustomerHelpers
    include AdminHelpers
    include CustomizationHelpers
    include SecurityHelpers
    include ReportsHelpers
    include CsrfHelpers
  end

  # Security headers and rate limiting
  before do
    is_test = ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'
    next if is_test

    set_security_headers if respond_to?(:set_security_headers)

    # Rate limiting for sensitive endpoints
    if respond_to?(:enforce_rate_limit)
      if request.path_info.start_with?('/admin', '/api')
        enforce_rate_limit(50, 3600)
      else
        enforce_rate_limit(200, 3600)
      end
    end
  end

  # Error handling
  error 404 do
    if request.path_info.start_with?('/api/')
      content_type :json
      status 404
      { success: false, error: 'Not found' }.to_json
    else
      erb :'errors/404', layout: :'layouts/main_layout'
    end
  end

  error 500 do
    if request.path_info.start_with?('/api/')
      content_type :json
      status 500
      { success: false, error: 'Internal server error' }.to_json
    else
      erb :'errors/500', layout: :'layouts/main_layout'
    end
  end
end

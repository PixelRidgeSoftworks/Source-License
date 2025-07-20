# frozen_string_literal: true

# Base controller with common functionality
module BaseController
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Configure common settings for all controllers
    def configure_controller
      # Set security headers and rate limiting for all requests
      before do
        # Skip security features in test environment
        next if ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test' || ENV['APP_ENV'] == 'development'

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
        include CustomizationHelpers
        include SecurityHelpers
        include ReportsHelpers
      end

      # Error handling
      error 404 do
        erb :'errors/404', layout: :'layouts/main_layout'
      end

      error 500 do
        erb :'errors/500', layout: :'layouts/main_layout'
      end
    end
  end
end

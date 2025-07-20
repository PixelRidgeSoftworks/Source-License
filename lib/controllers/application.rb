# frozen_string_literal: true

# Main application controller that includes all other controllers
require_relative 'base_controller'
require_relative 'public_controller'
require_relative 'user_auth_controller'
require_relative 'admin_controller'
require_relative 'admin_namespace'
require_relative 'admin/products_controller'
require_relative 'admin/licenses_controller'
require_relative 'admin/features_controller'
require_relative 'api_controller'

class SourceLicenseApp < Sinatra::Base
  # Security middleware (only in production)
  use SecurityMiddleware unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test' || ENV['APP_ENV'] == 'development' || ENV['RACK_ENV'] == 'development'
  
  # Configure mail delivery
  def self.configure_mail
    Mail.defaults do
      delivery_method :smtp, {
        address: ENV.fetch('SMTP_HOST', nil),
        port: ENV['SMTP_PORT'].to_i,
        user_name: ENV.fetch('SMTP_USERNAME', nil),
        password: ENV.fetch('SMTP_PASSWORD', nil),
        authentication: 'plain',
        enable_starttls_auto: ENV['SMTP_TLS'] == 'true',
      }
    end
  end

  # Configure Sinatra
  configure do
    # Always disable Rack::Protection's HostAuthorization since we handle it in SecurityMiddleware
    set :protection, except: [:host_authorization]
  end

  # Configure host authorization per environment
  configure :development do
    # Disable host authorization completely in development
    set :host_authorization, { permitted_hosts: [] }
  end

  configure :production do
    # Enable host authorization in production with allowed hosts
    if ENV['ALLOWED_HOSTS']
      permitted_hosts = ENV['ALLOWED_HOSTS'].split(',').map(&:strip)
      set :host_authorization, { permitted_hosts: permitted_hosts }
    else
      # If no ALLOWED_HOSTS set, disable it for backward compatibility
      set :host_authorization, { permitted_hosts: [] }
    end
  end

  configure do
    
    set :root, File.dirname(__FILE__ + '/../..')
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
    set :show_exceptions, false
    set :logging, true

    # Enable method override for REST-like routes
    set :method_override, true

    # Secure session configuration
    if ENV['APP_ENV'] == 'production'
      use Rack::Session::Cookie, {
        key: '_source_license_session',
        secret: ENV.fetch('APP_SECRET') { raise 'APP_SECRET must be set' },
        secure: true, # HTTPS only
        httponly: true, # Prevent XSS
        same_site: :strict, # CSRF protection
        expire_after: 24 * 60 * 60, # 24 hours
      }
    else
      # Development session configuration with proper SameSite
      use Rack::Session::Cookie, {
        key: 'rack.session',
        secret: ENV.fetch('APP_SECRET',
                          'dev_secret_change_me_this_is_a_much_longer_fallback_secret_that_meets_the_64_character_minimum_requirement'),
        httponly: true,
        same_site: :lax, # Proper SameSite for development
        expire_after: 24 * 60 * 60,
      }
    end

    # Configure mail settings
    configure_mail if ENV['SMTP_HOST']
  end

  # Include all controller modules
  include PublicController
  include UserAuthController
  include AdminController
  include AdminControllers::ProductsController
  include AdminControllers::LicensesController
  include AdminControllers::FeaturesController
  include ApiController

  # Set up all routes
  PublicController.setup_routes(self)
  UserAuthController.setup_routes(self)
  AdminController.setup_routes(self)
  AdminControllers::ProductsController.setup_routes(self)
  AdminControllers::LicensesController.setup_routes(self)
  AdminControllers::FeaturesController.setup_routes(self)
  ApiController.setup_routes(self)
end

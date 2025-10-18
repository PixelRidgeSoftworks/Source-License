# frozen_string_literal: true

# Main application controller that includes all other controllers
require_relative 'base_controller'
require_relative '../public/public_controller'
require_relative '../auth/user_auth_controller'
require_relative '../admin/admin_controller'
require_relative '../admin/admin_namespace'
require_relative '../admin/products_controller'
require_relative '../admin/licenses_controller'
require_relative '../admin/customers_controller'
require_relative '../admin/categories_controller'
require_relative '../admin/reports_controller'
require_relative '../admin/customization_controller'
require_relative '../admin/webhook_settings_controller'
require_relative '../admin/orders_controller'
require_relative '../../services/admin/order_service'
require_relative '../webhooks/webhooks_controller'
require_relative '../public/subscription_controller'
require_relative '../api/api_controller'
require_relative '../api/secure_api_controller'
require_relative '../public/user_addresses_controller'
require_relative '../auth/two_factor_auth_controller'

class SourceLicenseApp < Sinatra::Base
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
    # No SecurityMiddleware in development
  end

  configure :test do
    # Disable host authorization in test environment
    set :host_authorization, { permitted_hosts: [] }
    # No SecurityMiddleware in test
  end

  configure :production do
    # Enable SecurityMiddleware for production security
    use SecurityMiddleware

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
    set :root, File.expand_path('../..', __dir__)
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
    set :show_exceptions, false
    set :logging, true

    # Enable method override for REST-like routes
    set :method_override, true

    # Secure session configuration
    is_production = ENV['APP_ENV'] == 'production' || ENV['RACK_ENV'] == 'production'
    is_render = ENV['RENDER'] == 'true'
    is_https = ENV['HTTPS'] == 'true' || ENV['RAILS_FORCE_SSL'] == 'true' || is_render

    # Use more permissive session settings for Render deployments (even in development)
    # to handle load balancer/proxy scenarios
    use Rack::Session::Cookie, {
      key: is_production ? '_source_license_session' : 'rack.session',
      secret: ENV.fetch('APP_SECRET') do
        raise 'APP_SECRET must be set in production' if is_production


        'dev_secret_change_me_this_is_a_much_longer_fallback_secret_that_meets_the_64_character_minimum_requirement'
      end,
      secure: is_https, # HTTPS when available
      httponly: true, # Prevent XSS
      same_site: is_render ? :none : :lax, # Use :none for Render to handle proxy/load balancer
      expire_after: 24 * 60 * 60, # 24 hours
    }

    # Configure mail settings
    configure_mail if ENV['SMTP_HOST']
  end

  # Include all controller modules
  include PublicController
  include UserAuthController
  include AdminController
  include AdminControllers::ProductsController
  include AdminControllers::LicensesController
  include AdminControllers::CustomersController
  include Admin::CategoriesController
  include AdminControllers::ReportsController
  include AdminControllers::CustomizationController
  include AdminControllers::WebhookSettingsController
  include Admin::OrdersController
  include WebhooksController
  include ApiController

  # Set up all routes - API routes FIRST to avoid conflicts
  ApiController.setup_routes(self)
  UserAddressesController.setup_routes(self)
  WebhooksController.setup_routes(self)
  SubscriptionController.setup_routes(self)
  TwoFactorAuthController.setup_routes(self)
  AdminController.setup_routes(self)
  AdminControllers::ProductsController.setup_routes(self)
  AdminControllers::LicensesController.setup_routes(self)
  AdminControllers::CustomersController.setup_routes(self)
  Admin::CategoriesController.setup_routes(self)
  AdminControllers::ReportsController.setup_routes(self)
  AdminControllers::CustomizationController.setup_routes(self)
  AdminControllers::WebhookSettingsController.setup_routes(self)
  Admin::OrdersController.setup_routes(self)
  UserAuthController.setup_routes(self)
  PublicController.setup_routes(self)
end

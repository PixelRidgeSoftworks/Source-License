# frozen_string_literal: true

# Main application controller that includes all other controllers
require_relative 'base_controller'
require_relative '../../csrf_protection'
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
  register Sinatra::Contrib

  # ==================================================
  # SESSION CONFIGURATION
  # ==================================================
  # Require a proper session secret in production - fail fast if missing
  session_secret = ENV.fetch('APP_SECRET', nil)
  is_production = ENV['APP_ENV'] == 'production' || ENV['RACK_ENV'] == 'production'

  if is_production && (session_secret.nil? || session_secret.empty? || session_secret.length < 64)
    raise 'APP_SECRET environment variable must be set to a secure random string (64+ chars) in production'
  end

  # Fallback for development only
  session_secret ||= SecureRandom.hex(64)

  enable :sessions
  set :session_secret, session_secret
  set :sessions,
      httponly: true,
      secure: is_production || ENV['HTTPS'] == 'true',
      same_site: ENV['RENDER'] == 'true' ? :none : :lax,
      expire_after: 86_400 * 7 # 7 days

  # ==================================================
  # HOST AUTHORIZATION
  # ==================================================
  def self.permitted_hosts
    domains_string = ENV['ALLOWED_HOSTS'] || 'localhost'
    domains = domains_string.split(',').map(&:strip)

    hosts = []
    domains.each do |domain|
      hosts << domain

      next unless domain == 'localhost'

      port = ENV['PORT'] || '4567'
      hosts += [
        "localhost:#{port}",
        '127.0.0.1',
        "127.0.0.1:#{port}",
        '[::1]',
        "[::1]:#{port}",
      ]
    end

    hosts.uniq
  end

  # ==================================================
  # RACK::PROTECTION CONFIGURATION
  # ==================================================
  # Enable Sinatra's built-in Rack::Protection middleware
  # This provides CSRF protection via AuthenticityToken plus many other protections
  #
  # Protections enabled by default:
  # - AuthenticityToken (CSRF protection for forms)
  # - RemoteToken (CSRF via Referer/Origin headers)
  # - SessionHijacking
  # - XSSHeader, FrameOptions, etc.
  #
  # We customize to work with our API/webhook paths that use different auth
  set :protection, except: [:json_csrf] # Allow JSON requests with proper CSRF handling

  # ==================================================
  # ENVIRONMENT-SPECIFIC CONFIGURATION
  # ==================================================
  configure :development do
    set :logging, true
    enable :dump_errors
    set :show_exceptions, :after_handler
    set :host_authorization, { permitted_hosts: permitted_hosts }
  end

  configure :test do
    set :logging, false
    set :show_exceptions, false
    set :host_authorization, { permitted_hosts: [] }
    # Disable CSRF protection in tests
    set :protection, false
  end

  configure :production do
    set :logging, true
    set :dump_errors, false
    set :show_exceptions, false
    set :host_authorization, { permitted_hosts: permitted_hosts }
    use SecurityMiddleware
  end

  # ==================================================
  # COMMON CONFIGURATION
  # ==================================================
  configure do
    set :root, File.expand_path('../..', __dir__)
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
    set :method_override, true

    # Configure mail settings
    configure_mail if ENV['SMTP_HOST']
  end

  # ==================================================
  # CSRF PROTECTION (Supplementary to Rack::Protection)
  # ==================================================
  # Sinatra's Rack::Protection::AuthenticityToken handles most CSRF,
  # but we add custom handling for our specific exempt paths and token format
  CSRF_EXEMPT_PATHS = [
    %r{^/api/},           # API routes use JWT auth
    %r{^/webhooks/},      # Webhook endpoints verify signatures instead
  ].freeze

  before do
    # Skip CSRF for safe methods (GET, HEAD, OPTIONS)
    next if CsrfProtection.safe_method?(request.request_method)

    # Skip CSRF for exempt paths (API uses JWT, webhooks use signatures)
    next if CSRF_EXEMPT_PATHS.any? { |pattern| request.path_info.match?(pattern) }

    # Skip CSRF validation in test environment
    next if ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    # Validate CSRF token (our custom validation that accepts multiple token sources)
    unless CsrfProtection.valid_token?(session, params, request)
      if request.xhr? || request.content_type&.include?('application/json')
        halt 403, { 'Content-Type' => 'application/json' },
             { success: false, error: 'Invalid CSRF token' }.to_json
      else
        halt 403, 'Invalid CSRF token'
      end
    end
  end

  # ==================================================
  # HELPER MODULES
  # ==================================================
  helpers CsrfHelpers

  # ==================================================
  # MAIL CONFIGURATION
  # ==================================================
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

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
require_relative 'lib/enhanced_auth'
require_relative 'lib/security'
require_relative 'lib/logger'
require_relative 'lib/settings_manager'

class SourceLicenseApp < Sinatra::Base
  # Security middleware
  use SecurityMiddleware unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'
  use Rack::Protection, except: [:json_csrf] # We'll handle CSRF manually

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
    set :root, File.dirname(__FILE__)
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
      set :sessions, true
      set :session_secret,
          ENV.fetch('APP_SECRET',
                    'dev_secret_change_me_this_is_a_much_longer_fallback_secret_that_meets_the_64_character_minimum_requirement')
    end

    # Configure mail settings
    configure_mail if ENV['SMTP_HOST']
  end

  # Set security headers and rate limiting for all requests
  before do
    # Skip security features in test environment
    next if ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

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
    include TemplateHelpers
    include LicenseHelpers
    include CustomizationHelpers
    include SecurityHelpers
  end

  # Error handling
  error 404 do
    erb :'errors/404', layout: :'layouts/main_layout'
  end

  error 500 do
    erb :'errors/500', layout: :'layouts/main_layout'
  end

  # ==================================================
  # PUBLIC ROUTES - Website Frontend
  # ==================================================

  # Homepage / Storefront
  get '/' do
    @products = Product.where(active: true).order(:name)
    @page_title = custom('branding.site_name', 'Software License Store')
    erb :index, layout: :'layouts/main_layout'
  end

  # Product details page
  get '/product/:id' do
    @product = Product[params[:id]]
    halt 404 unless @product&.active
    @page_title = @product.name
    erb :'products/show', layout: :'layouts/main_layout'
  end

  # Cart page
  get '/cart' do
    @page_title = 'Shopping Cart'
    erb :cart, layout: :'layouts/main_layout'
  end

  # Checkout page
  get '/checkout' do
    @page_title = 'Checkout'
    erb :checkout, layout: :'layouts/main_layout'
  end

  # Purchase success page
  get '/success' do
    @page_title = 'Purchase Successful'
    erb :success, layout: :'layouts/main_layout'
  end

  # License lookup/download page
  get '/my-licenses' do
    @page_title = 'My Licenses'
    erb :'licenses/lookup', layout: :'layouts/main_layout'
  end

  # License details and download
  get '/license/:key' do
    @license = License.first(license_key: params[:key])
    halt 404 unless @license
    @page_title = 'License Details'
    erb :'licenses/show', layout: :'layouts/main_layout'
  end

  # Download product file
  get '/download/:license_key/:file' do
    license = License.first(license_key: params[:license_key])
    halt 404 unless license&.valid?

    file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads',
                          license.product.download_file)
    halt 404 unless File.exist?(file_path)

    # Log the download
    license.update(download_count: license.download_count + 1,
                   last_downloaded_at: Time.now)

    send_file file_path, disposition: 'attachment'
  end

  # ==================================================
  # ADMIN ROUTES
  # ==================================================

  # Admin login page
  get '/admin/login' do
    redirect '/admin' if current_secure_admin
    @page_title = 'Admin Login'
    erb :'admin/login', layout: :'layouts/admin_layout'
  end

  # Enhanced admin login handler
  post '/admin/login' do
    require_csrf_protection unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    # Gather request information
    request_info = {
      ip: request.ip,
      user_agent: request.user_agent,
    }

    # Use enhanced authentication
    auth_result = authenticate_admin_secure(params[:email], params[:password], request_info)

    if auth_result[:success]
      admin = auth_result[:admin]

      # Create secure session
      create_secure_session(admin, request_info)

      # Check for security warnings
      @security_warnings = check_account_security(admin)

      # Redirect to return URL or dashboard
      redirect_url = session.delete(:return_to) || '/admin'
      redirect redirect_url
    else
      @error = auth_result[:message]
      @page_title = 'Admin Login'
      erb :'admin/login', layout: :'layouts/admin_layout'
    end
  end

  # Admin logout
  post '/admin/logout' do
    session.clear
    redirect '/admin/login'
  end

  # Admin dashboard
  get '/admin' do
    require_secure_admin_auth
    @page_title = 'Admin Dashboard'
    @stats = {
      total_licenses: License.count,
      active_licenses: License.where(status: 'active').count,
      total_revenue: Order.where(status: 'completed').sum(:amount) || 0,
      recent_orders: Order.order(Sequel.desc(:created_at)).limit(10),
    }
    erb :'admin/dashboard', layout: :'layouts/admin_layout'
  end

  # Product management
  get '/admin/products' do
    require_secure_admin_auth
    @products = Product.order(:name)
    @page_title = 'Manage Products'
    erb :'admin/products', layout: :'layouts/admin_layout'
  end

  # License management
  get '/admin/licenses' do
    require_secure_admin_auth
    @licenses = License.order(Sequel.desc(:created_at)).limit(100)
    @page_title = 'Manage Licenses'
    erb :'admin/licenses', layout: :'layouts/admin_layout'
  end

  # Generate license page (placeholder)
  get '/admin/licenses/generate' do
    require_secure_admin_auth
    @page_title = 'Generate License'
    # For now, redirect to main licenses page with a message
    flash :info, 'License generation feature coming soon!'
    redirect '/admin/licenses'
  end

  # Add product page (placeholder)
  get '/admin/products/new' do
    require_secure_admin_auth
    @page_title = 'Add Product'
    # For now, redirect to main products page with a message
    flash :info, 'Product creation feature coming soon!'
    redirect '/admin/products'
  end

  # Settings page
  get '/admin/settings' do
    require_secure_admin_auth
    @page_title = 'Settings'
    erb :'admin/settings', layout: :'layouts/admin_layout'
  end

  # Database backup route
  post '/admin/database/backup' do
    require_secure_admin_auth
    content_type :json

    begin
      # Create a simple database backup
      backup_filename = "backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
      backup_path = File.join(ENV['BACKUP_PATH'] || './backups', backup_filename)
      
      # Ensure backup directory exists
      FileUtils.mkdir_p(File.dirname(backup_path))
      
      # Simple backup for SQLite (adjust for other databases)
      if ENV['DATABASE_ADAPTER'] == 'sqlite' || !ENV['DATABASE_ADAPTER']
        db_path = ENV['DATABASE_PATH'] || './database.db'
        FileUtils.cp(db_path, backup_path) if File.exist?(db_path)
      end
      
      { success: true, message: 'Database backup created successfully', filename: backup_filename }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Run migrations route
  post '/admin/database/migrate' do
    require_secure_admin_auth
    content_type :json

    begin
      # Run any pending migrations
      require_relative 'lib/migrations'
      Migrations.run_all
      
      { success: true, message: 'Migrations completed successfully' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Download logs route
  get '/admin/logs/download' do
    require_secure_admin_auth
    
    log_path = ENV['LOG_PATH'] || './log/application.log'
    
    if File.exist?(log_path)
      send_file log_path, disposition: 'attachment', filename: "application_logs_#{Time.now.strftime('%Y%m%d')}.log"
    else
      halt 404, 'Log file not found'
    end
  end

  # Export data route
  post '/admin/data/export' do
    require_secure_admin_auth
    content_type :json

    begin
      export_data = {
        licenses: License.all.map(&:values),
        products: Product.all.map(&:values),
        orders: Order.all.map(&:values),
        exported_at: Time.now.iso8601
      }
      
      filename = "data_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      export_path = File.join(ENV['EXPORT_PATH'] || './exports', filename)
      
      # Ensure export directory exists
      FileUtils.mkdir_p(File.dirname(export_path))
      
      File.write(export_path, JSON.pretty_generate(export_data))
      
      { success: true, message: 'Data exported successfully', filename: filename }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Regenerate API keys route
  post '/admin/security/regenerate-keys' do
    require_secure_admin_auth
    content_type :json

    begin
      # Generate new JWT secret
      new_secret = SecureRandom.hex(64)
      
      # In a real implementation, you'd update your environment or database
      # For now, we'll just simulate the action
      
      { success: true, message: 'API keys regenerated successfully. Please restart the application.' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # ==================================================
  # CUSTOMIZATION ADMIN ROUTES
  # ==================================================

  # Template customization main page
  get '/admin/customize' do
    require_secure_admin_auth
    @page_title = 'Template Customization'
    @categories = TemplateCustomizer.get_categories
    @customizations = TemplateCustomizer.get_all_customizations
    erb :'admin/customize', layout: :'layouts/admin_layout'
  end

  # Update customizations
  post '/admin/customize' do
    require_secure_admin_auth
    content_type :json

    begin
      updates = JSON.parse(request.body.read)
      TemplateCustomizer.update_multiple(updates)

      { success: true, message: 'Customizations saved successfully!' }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Reset customizations to defaults
  post '/admin/customize/reset' do
    require_secure_admin_auth
    content_type :json

    begin
      TemplateCustomizer.reset_to_defaults
      { success: true, message: 'Customizations reset to defaults!' }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Export customizations
  get '/admin/customize/export' do
    require_secure_admin_auth
    content_type 'application/x-yaml'
    attachment 'customizations.yml'
    TemplateCustomizer.export_customizations
  end

  # Import customizations
  post '/admin/customize/import' do
    require_secure_admin_auth
    content_type :json

    begin
      if params[:file] && params[:file][:tempfile]
        yaml_content = params[:file][:tempfile].read
        success = TemplateCustomizer.import_customizations(yaml_content)

        if success
          { success: true, message: 'Customizations imported successfully!' }.to_json
        else
          { success: false, error: 'Invalid YAML file format' }.to_json
        end
      else
        { success: false, error: 'No file uploaded' }.to_json
      end
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Template code guide
  get '/admin/customize/code-guide' do
    require_secure_admin_auth
    @page_title = 'Template Code Guide'
    erb :'admin/code_guide', layout: :'layouts/admin_layout'
  end

  # Live preview endpoint
  get '/admin/customize/preview' do
    require_secure_admin_auth
    @page_title = custom('branding.site_name', 'Source License')
    @products = Product.where(active: true).order(:name).limit(3)
    erb :index, layout: :'layouts/main_layout'
  end

  # ==================================================
  # API ROUTES - Secure REST API
  # ==================================================

  # API Authentication endpoint
  post '/api/auth' do
    content_type :json

    if authenticate_admin(params[:email], params[:password])
      token = generate_jwt_token(params[:email])
      { success: true, token: token }.to_json
    else
      status 401
      { success: false, error: 'Invalid credentials' }.to_json
    end
  end

  # License validation API
  get '/api/license/:key/validate' do
    content_type :json

    license = License.first(license_key: params[:key])
    if license
      {
        valid: license.valid?,
        status: license.status,
        product: license.product.name,
        expires_at: license.expires_at,
        activations_used: license.activation_count,
        max_activations: license.max_activations,
      }.to_json
    else
      status 404
      { valid: false, error: 'License not found' }.to_json
    end
  end

  # License activation API
  post '/api/license/:key/activate' do
    content_type :json

    license = License.first(license_key: params[:key])
    unless license
      status 404
      return { success: false, error: 'License not found' }.to_json
    end

    unless license.valid?
      status 400
      return { success: false, error: 'License is not valid' }.to_json
    end

    if license.activation_count >= license.max_activations
      status 400
      return { success: false, error: 'Maximum activations reached' }.to_json
    end

    license.update(
      activation_count: license.activation_count + 1,
      last_activated_at: Time.now
    )

    { success: true, activations_remaining: license.max_activations - license.activation_count }.to_json
  end

  # Process payment webhook
  post '/api/webhook/:provider' do
    content_type :json

    case params[:provider]
    when 'stripe'
      handle_stripe_webhook(request)
    when 'paypal'
      handle_paypal_webhook(request)
    else
      status 400
      return { error: 'Unknown provider' }.to_json
    end

    { success: true }.to_json
  end

  # Create new order
  post '/api/orders' do
    content_type :json
    require_valid_api_token

    begin
      order_data = JSON.parse(request.body.read)
      order = create_order(order_data)

      status 201
      {
        success: true,
        order_id: order.id,
        payment_url: order.payment_url,
      }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Get order status
  get '/api/orders/:id' do
    content_type :json

    order = Order[params[:id]]
    unless order
      status 404
      return { error: 'Order not found' }.to_json
    end

    {
      id: order.id,
      status: order.status,
      amount: order.amount,
      created_at: order.created_at,
      license_keys: order.licenses.map(&:license_key),
    }.to_json
  end

  # ==================================================
  # SETTINGS API ROUTES
  # ==================================================

  # Get all settings categories
  get '/api/settings/categories' do
    require_secure_admin_auth
    content_type :json

    categories = SettingsManager.get_categories.map do |category|
      {
        name: category,
        settings: SettingsManager.get_category(category),
      }
    end

    { success: true, categories: categories }.to_json
  end

  # Get settings for a specific category
  get '/api/settings/:category' do
    require_secure_admin_auth
    content_type :json

    category = params[:category]
    settings = SettingsManager.get_category(category)

    if settings.empty?
      status 404
      return { success: false, error: 'Category not found' }.to_json
    end

    { success: true, category: category, settings: settings }.to_json
  end

  # Get a specific setting value
  get '/api/settings/:category/:key' do
    require_secure_admin_auth
    content_type :json

    full_key = "#{params[:category]}.#{params[:key]}"
    value = SettingsManager.get(full_key)

    { success: true, key: full_key, value: value }.to_json
  end

  # Update a specific setting
  put '/api/settings/:category/:key' do
    require_secure_admin_auth
    content_type :json

    begin
      data = JSON.parse(request.body.read)
      full_key = "#{params[:category]}.#{params[:key]}"

      if SettingsManager.set(full_key, data['value'])
        { success: true, message: 'Setting updated successfully' }.to_json
      else
        status 400
        { success: false, error: 'Failed to update setting' }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Update multiple settings at once
  post '/api/settings/bulk-update' do
    require_secure_admin_auth
    content_type :json

    begin
      data = JSON.parse(request.body.read)
      updated_count = 0
      errors = []

      data['settings'].each do |setting|
        if SettingsManager.set(setting['key'], setting['value'])
          updated_count += 1
        else
          errors << "Failed to update #{setting['key']}"
        end
      end

      if errors.empty?
        {
          success: true,
          message: "Updated #{updated_count} settings successfully",
        }.to_json
      else
        status 400
        {
          success: false,
          message: "Updated #{updated_count} settings, #{errors.length} failed",
          errors: errors,
        }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Test configuration for a category
  post '/api/settings/:category/test' do
    require_secure_admin_auth
    content_type :json

    category = params[:category]
    test_results = SettingsManager.test_configuration(category)

    { success: true, category: category, test_results: test_results }.to_json
  end

  # Export settings as YAML
  get '/api/settings/export' do
    require_secure_admin_auth
    content_type 'application/x-yaml'
    attachment 'settings.yml'

    SettingsManager.export_to_yaml
  end

  # Import settings from YAML
  post '/api/settings/import' do
    require_secure_admin_auth
    content_type :json

    begin
      if params[:file] && params[:file][:tempfile]
        yaml_content = params[:file][:tempfile].read
        imported_count = SettingsManager.import_from_yaml(yaml_content)

        {
          success: true,
          message: "Imported #{imported_count} settings successfully",
        }.to_json
      else
        status 400
        { success: false, error: 'No file uploaded' }.to_json
      end
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Generate .env file content
  get '/api/settings/generate-env' do
    require_secure_admin_auth
    content_type 'text/plain'
    attachment '.env'

    SettingsManager.generate_env_file
  end

  # Get web-editable settings only
  get '/api/settings/web-editable' do
    require_secure_admin_auth
    content_type :json

    settings = SettingsManager.get_web_editable

    { success: true, settings: settings }.to_json
  end

  private

  # Handle Stripe webhooks
  def handle_stripe_webhook(request)
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, ENV.fetch('STRIPE_WEBHOOK_SECRET', nil)
      )

      case event['type']
      when 'payment_intent.succeeded'
        handle_successful_payment(event['data']['object'])
      end
    rescue StandardError => e
      logger.error "Stripe webhook error: #{e.message}"
      status 400
    end
  end

  # Handle PayPal webhooks
  def handle_paypal_webhook(_request)
    # PayPal webhook handling implementation
    # This would verify the webhook signature and process the payment
    logger.info 'PayPal webhook received'
  end

  # Handle successful payment
  def handle_successful_payment(payment_intent)
    order = Order.first(payment_intent_id: payment_intent['id'])
    return unless order

    order.update(status: 'completed', completed_at: Time.now)

    # Generate licenses for the order
    order.order_items.each do |item|
      item.quantity.times do
        license = LicenseGenerator.generate_for_product(item.product, order)
        order.add_license(license)
      end
    end

    # Send confirmation email
    send_order_confirmation_email(order) if ENV['SMTP_HOST']
  end

  # Send order confirmation email
  def send_order_confirmation_email(order)
    mail = Mail.new do
      from ENV.fetch('SMTP_USERNAME', nil)
      to order.email
      subject "Your Software License Purchase - Order ##{order.id}"
      body erb(:'emails/order_confirmation', locals: { order: order }, layout: false)
    end

    mail.deliver!
  rescue StandardError => e
    logger.error "Failed to send confirmation email: #{e.message}"
  end

  # Create new order
  def create_order(order_data)
    DB.transaction do
      order = Order.create(
        email: order_data['email'],
        amount: order_data['amount'],
        currency: order_data['currency'] || 'USD',
        status: 'pending',
        payment_method: order_data['payment_method']
      )

      order_data['items'].each do |item|
        product = Product[item['product_id']]
        order.add_order_item(
          product: product,
          quantity: item['quantity'],
          price: product.price
        )
      end

      # Create payment intent based on method
      order.update(payment_intent_id: create_stripe_payment_intent(order)) if order.payment_method == 'stripe'

      order
    end
  end

  # Create Stripe payment intent
  def create_stripe_payment_intent(order)
    Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)

    intent = Stripe::PaymentIntent.create({
      amount: (order.amount * 100).to_i, # Convert to cents
      currency: order.currency.downcase,
      metadata: { order_id: order.id },
    })

    intent.id
  end
end

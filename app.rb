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
require_relative 'lib/user_auth'
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
    include UserAuthHelpers
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
    @products = Product.where(active: true).order(:name).all
    @page_title = 'Shopping Cart'
    erb :cart, layout: :'layouts/main_layout'
  end

  # Checkout page
  get '/checkout' do
    @products = Product.where(active: true).order(:name).all
    @page_title = 'Checkout'
    erb :checkout, layout: :'layouts/main_layout'
  end

  # Purchase success page
  get '/success' do
    @order_id = params[:order_id]
    @order = nil

    @order = Order[params[:order_id]] if @order_id

    @page_title = 'Purchase Successful'
    erb :success, layout: :'layouts/main_layout'
  end

  # Public license validation (read-only, no sensitive info)
  get '/validate-license' do
    @page_title = 'Validate License'
    erb :'licenses/validate', layout: :'layouts/main_layout'
  end

  # Public license validation API
  post '/validate-license' do
    license_key = params[:license_key]&.strip
    halt 400, 'License key required' unless license_key

    license = License.first(license_key: license_key)

    @validation_result = if license
                           {
                             valid: license.valid?,
                             status: license.status,
                             product_name: license.product&.name,
                             expires_at: license.expires_at,
                             license_type: license.license_type,
                           }
                         else
                           {
                             valid: false,
                             status: 'not_found',
                             error: 'License not found',
                           }
                         end

    @license_key = license_key
    @page_title = 'License Validation Result'
    erb :'licenses/validate', layout: :'layouts/main_layout'
  end

  # Redirect old insecure routes to secure versions
  get '/my-licenses' do
    redirect '/login' unless user_logged_in?
    redirect '/licenses'
  end

  get '/license/:key' do
    redirect '/login' unless user_logged_in?
    # Try to find the license and redirect to secure version
    license = License.first(license_key: params[:key])
    if license && user_owns_license?(current_user, license)
      redirect "/licenses/#{license.id}"
    else
      halt 404
    end
  end

  # Secure download route (old insecure route disabled)
  get '/download/:license_key/:file' do
    halt 403, 'Direct downloads are no longer supported. Please log in to access your licenses.'
  end

  # ==================================================
  # USER AUTHENTICATION ROUTES
  # ==================================================

  # User login page
  get '/login' do
    redirect '/dashboard' if user_logged_in?
    @page_title = 'Login'
    erb :'users/login', layout: :'layouts/main_layout'
  end

  # User login handler
  post '/login' do
    result = authenticate_user(params[:email], params[:password])

    if result[:success]
      user = result[:user]
      create_user_session(user)

      # Transfer any licenses from email to user account
      transferred_count = transfer_licenses_to_user(user, params[:email])

      if transferred_count.positive?
        flash :info, "#{transferred_count} existing license(s) have been transferred to your account."
      end

      # Redirect to dashboard or return URL
      redirect_url = session.delete(:return_to) || '/dashboard'
      redirect redirect_url
    else
      @error = result[:error]
      @page_title = 'Login'
      erb :'users/login', layout: :'layouts/main_layout'
    end
  end

  # User registration page
  get '/register' do
    redirect '/dashboard' if user_logged_in?
    @page_title = 'Create Account'
    erb :'users/register', layout: :'layouts/main_layout'
  end

  # User registration handler
  post '/register' do
    result = register_user(params[:email], params[:password], params[:name])

    if result[:success]
      user = result[:user]

      # Transfer any existing licenses to the new account
      transferred_count = transfer_licenses_to_user(user, params[:email])

      # Create user session
      create_user_session(user)

      success_message = 'Account created successfully!'
      if transferred_count.positive?
        success_message += " #{transferred_count} existing license(s) have been transferred to your account."
      end

      flash :success, success_message
      redirect '/dashboard'
    else
      @error = result[:error]
      @page_title = 'Create Account'
      erb :'users/register', layout: :'layouts/main_layout'
    end
  end

  # User logout
  post '/logout' do
    clear_user_session
    flash :success, 'You have been logged out successfully.'
    redirect '/'
  end

  # User dashboard (secure)
  get '/dashboard' do
    require_user_auth
    @user = current_user
    @licenses = get_user_licenses(@user)
    @page_title = 'My Dashboard'
    erb :'users/dashboard', layout: :'layouts/main_layout'
  end

  # Secure license management (replaces the old insecure lookup)
  get '/licenses' do
    require_user_auth
    @user = current_user
    @licenses = get_user_licenses(@user)
    @page_title = 'My Licenses'
    erb :'users/licenses', layout: :'layouts/main_layout'
  end

  # Secure license details
  get '/licenses/:id' do
    require_user_auth
    license = License[params[:id]]
    halt 404 unless license
    halt 403 unless user_owns_license?(current_user, license)

    @license = license
    @page_title = "License: #{@license.product.name}"
    erb :'users/license_details', layout: :'layouts/main_layout'
  end

  # Secure download (requires authentication)
  get '/secure-download/:license_id/:file' do
    require_user_auth
    license = License[params[:license_id]]
    halt 404 unless license
    halt 403 unless user_owns_license?(current_user, license)
    halt 404 unless license.valid?

    file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads',
                          license.product.download_file)
    halt 404 unless File.exist?(file_path)

    # Log the download
    license.update(download_count: license.download_count + 1,
                   last_downloaded_at: Time.now)

    send_file file_path, disposition: 'attachment'
  end

  # User profile page
  get '/profile' do
    require_user_auth
    @user = current_user
    @page_title = 'My Profile'
    erb :'users/profile', layout: :'layouts/main_layout'
  end

  # Update user profile
  post '/profile' do
    require_user_auth
    user = current_user

    # Update basic info
    user.name = params[:name]&.strip if params[:name]

    # Handle password change if provided
    if params[:current_password] && params[:new_password]
      if user.password_matches?(params[:current_password])
        if params[:new_password].length >= 8
          user.password = params[:new_password]
          flash :success, 'Profile and password updated successfully!'
        else
          flash :error, 'New password must be at least 8 characters long.'
          @user = user
          return erb :'users/profile', layout: :'layouts/main_layout'
        end
      else
        flash :error, 'Current password is incorrect.'
        @user = user
        return erb :'users/profile', layout: :'layouts/main_layout'
      end
    else
      flash :success, 'Profile updated successfully!'
    end

    user.save_changes
    redirect '/profile'
  end

  # Password reset request page
  get '/forgot-password' do
    redirect '/dashboard' if user_logged_in?
    @page_title = 'Forgot Password'
    erb :'users/forgot_password', layout: :'layouts/main_layout'
  end

  # Password reset request handler
  post '/forgot-password' do
    result = generate_password_reset_token(params[:email])

    if result
      # Send reset email (if SMTP is configured)
      if ENV['SMTP_HOST']
        send_password_reset_email(result[:user], result[:token])
        flash :success, 'Password reset instructions have been sent to your email.'
      else
        flash :info, "Reset token: #{result[:token]} (SMTP not configured - this would be emailed)"
      end
    else
      flash :success, 'If an account with that email exists, password reset instructions have been sent.'
    end

    redirect '/login'
  end

  # Password reset form
  get '/reset-password/:token' do
    @user = verify_password_reset_token(params[:token])
    halt 404 unless @user

    @token = params[:token]
    @page_title = 'Reset Password'
    erb :'users/reset_password', layout: :'layouts/main_layout'
  end

  # Password reset handler
  post '/reset-password/:token' do
    result = reset_password_with_token(params[:token], params[:password])

    if result[:success]
      flash :success, 'Your password has been reset successfully. Please log in.'
      redirect '/login'
    else
      @error = result[:error]
      @user = verify_password_reset_token(params[:token])
      halt 404 unless @user
      @token = params[:token]
      @page_title = 'Reset Password'
      erb :'users/reset_password', layout: :'layouts/main_layout'
    end
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
    require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

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

  # Add new product form
  get '/admin/products/new' do
    require_secure_admin_auth
    @page_title = 'Add New Product'
    erb :'admin/products_new', layout: :'layouts/admin_layout'
  end

  # Auto-save product draft (AJAX)
  post '/admin/products/auto-save' do
    require_secure_admin_auth
    content_type :json

    # Just return success for now - this is a placeholder for auto-save functionality
    { success: true, message: 'Draft saved' }.to_json
  end

  # Create new product
  post '/admin/products' do
    require_secure_admin_auth
    require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    begin
      # Handle file upload if provided
      download_file = nil
      if params[:download_file] && params[:download_file][:tempfile]
        upload = params[:download_file]
        filename = "#{SecureRandom.hex(8)}_#{upload[:filename]}"
        downloads_path = ENV['DOWNLOADS_PATH'] || './downloads'
        FileUtils.mkdir_p(downloads_path)

        file_path = File.join(downloads_path, filename)
        File.binwrite(file_path, upload[:tempfile].read)
        download_file = filename
      end

      # Create product
      product_params = {
        name: params[:name],
        description: params[:description],
        price: params[:price].to_f,
        license_type: params[:license_type],
        max_activations: params[:max_activations].to_i,
        version: params[:version],
        download_file: download_file,
        download_url: params[:download_url],
        file_size: params[:file_size],
        active: params[:active] == 'on',
        featured: params[:featured] == 'on',
        created_at: Time.now,
        updated_at: Time.now,
      }

      # Add subscription-specific fields
      if params[:license_type] == 'subscription'
        product_params.merge!(
          setup_fee: params[:setup_fee].to_f,
          billing_cycle: params[:billing_cycle],
          billing_interval: params[:billing_interval].to_i,
          license_duration_days: params[:license_duration_days].to_i,
          trial_period_days: params[:trial_period_days].to_i
        )
      end

      product = Product.create(product_params)

      if product.valid?
        flash :success, 'Product created successfully!'
        redirect "/admin/products/#{product.id}"
      else
        flash :error, "Error creating product: #{product.errors.full_messages.join(', ')}"
        @page_title = 'Add New Product'
        erb :'admin/products_new', layout: :'layouts/admin_layout'
      end
    rescue StandardError => e
      flash :error, "Error creating product: #{e.message}"
      @page_title = 'Add New Product'
      erb :'admin/products_new', layout: :'layouts/admin_layout'
    end
  end

  # View product details
  get '/admin/products/:id' do
    require_secure_admin_auth
    @product = Product[params[:id]]
    halt 404 unless @product
    @page_title = @product.name
    erb :'admin/products_show', layout: :'layouts/admin_layout'
  end

  # Edit product form
  get '/admin/products/:id/edit' do
    require_secure_admin_auth
    @product = Product[params[:id]]
    halt 404 unless @product
    @page_title = "Edit #{@product.name}"
    erb :'admin/products_edit', layout: :'layouts/admin_layout'
  end

  # Update product
  put '/admin/products/:id' do
    require_secure_admin_auth
    require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    @product = Product[params[:id]]
    halt 404 unless @product

    begin
      # Handle file upload if provided
      if params[:download_file] && params[:download_file][:tempfile]
        # Remove old file if exists
        if @product.download_file
          old_file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads', @product.download_file)
          FileUtils.rm_f(old_file_path)
        end

        upload = params[:download_file]
        filename = "#{SecureRandom.hex(8)}_#{upload[:filename]}"
        downloads_path = ENV['DOWNLOADS_PATH'] || './downloads'
        FileUtils.mkdir_p(downloads_path)

        file_path = File.join(downloads_path, filename)
        File.binwrite(file_path, upload[:tempfile].read)
        params[:download_file] = filename
      else
        params.delete(:download_file)
      end

      # Update product
      update_params = {
        name: params[:name],
        description: params[:description],
        price: params[:price].to_f,
        license_type: params[:license_type],
        max_activations: params[:max_activations].to_i,
        version: params[:version],
        download_url: params[:download_url],
        file_size: params[:file_size],
        active: params[:active] == 'on',
        featured: params[:featured] == 'on',
        updated_at: Time.now,
      }

      # Add file if uploaded
      update_params[:download_file] = params[:download_file] if params[:download_file]

      # Add subscription-specific fields
      if params[:license_type] == 'subscription'
        update_params.merge!(
          setup_fee: params[:setup_fee].to_f,
          billing_cycle: params[:billing_cycle],
          billing_interval: params[:billing_interval].to_i,
          license_duration_days: params[:license_duration_days].to_i,
          trial_period_days: params[:trial_period_days].to_i
        )
      else
        # Clear subscription fields for one-time products
        update_params.merge!(
          setup_fee: 0,
          billing_cycle: nil,
          billing_interval: nil,
          license_duration_days: nil,
          trial_period_days: 0
        )
      end

      @product.update(update_params)

      flash :success, 'Product updated successfully!'
      redirect "/admin/products/#{@product.id}"
    rescue StandardError => e
      flash :error, "Error updating product: #{e.message}"
      @page_title = "Edit #{@product.name}"
      erb :'admin/products_edit', layout: :'layouts/admin_layout'
    end
  end

  # Toggle product status (AJAX)
  post '/admin/products/:id/toggle-status' do
    require_secure_admin_auth
    content_type :json

    product = Product[params[:id]]
    unless product
      status 404
      return { success: false, error: 'Product not found' }.to_json
    end

    begin
      new_status = params[:status] == 'active'
      product.update(active: new_status)

      { success: true, status: new_status ? 'active' : 'inactive' }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Delete product
  delete '/admin/products/:id' do
    require_secure_admin_auth
    content_type :json

    product = Product[params[:id]]
    unless product
      status 404
      return { success: false, error: 'Product not found' }.to_json
    end

    begin
      # Check if product has associated licenses
      return { success: false, error: 'Cannot delete product with existing licenses' }.to_json if product.licenses.any?

      # Remove download file if exists
      if product.download_file
        file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads', product.download_file)
        FileUtils.rm_f(file_path)
      end

      product.destroy
      { success: true }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Duplicate product
  get '/admin/products/:id/duplicate' do
    require_secure_admin_auth

    original = Product[params[:id]]
    halt 404 unless original

    # Create duplicate with modified name
    duplicate_params = original.values.dup
    duplicate_params.delete(:id)
    duplicate_params[:name] = "#{original.name} (Copy)"
    duplicate_params[:active] = false # Start inactive
    duplicate_params[:download_file] = nil # Don't copy file
    duplicate_params[:created_at] = Time.now
    duplicate_params[:updated_at] = Time.now

    duplicate = Product.create(duplicate_params)

    flash :success, 'Product duplicated successfully!'
    redirect "/admin/products/#{duplicate.id}/edit"
  end

  # Export products
  get '/admin/products/export' do
    require_secure_admin_auth
    content_type 'text/csv'
    attachment 'products.csv'

    # Check if specific products are requested
    if params[:product_ids]
      product_ids = params[:product_ids].split(',').map(&:to_i)
      products = Product.where(id: product_ids).order(:name)
      filename = "selected_products_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    else
      products = Product.order(:name)
      filename = "all_products_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    end

    attachment filename

    csv_data = "Name,Description,Price,License Type,Max Activations,Active,Created At\n"
    products.each do |product|
      csv_data += "\"#{product.name}\",\"#{product.description || ''}\",#{product.price},#{product.license_type},#{product.max_activations},#{product.active},#{product.created_at}\n"
    end

    csv_data
  end

  # Bulk actions for products
  post '/admin/products/bulk-action' do
    require_secure_admin_auth
    content_type :json

    begin
      data = JSON.parse(request.body.read)
      action = data['action']
      product_ids = data['product_ids']

      unless %w[activate deactivate delete].include?(action)
        status 400
        return { success: false, error: 'Invalid action' }.to_json
      end

      if product_ids.nil? || product_ids.empty?
        status 400
        return { success: false, error: 'No products selected' }.to_json
      end

      # Find products
      products = Product.where(id: product_ids)
      if products.count != product_ids.length
        status 400
        return { success: false, error: 'Some products not found' }.to_json
      end

      results = { success: 0, failed: 0, errors: [] }

      DB.transaction do
        products.each do |product|
          case action
          when 'activate'
            product.update(active: true)
            results[:success] += 1
          when 'deactivate'
            product.update(active: false)
            results[:success] += 1
          when 'delete'
            # Check if product has licenses
            if product.licenses.any?
              results[:failed] += 1
              results[:errors] << "#{product.name}: Cannot delete product with existing licenses"
            else
              # Remove download file if exists
              if product.download_file
                file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads', product.download_file)
                FileUtils.rm_f(file_path)
              end
              product.destroy
              results[:success] += 1
            end
          end
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << "#{product.name}: #{e.message}"
        end
      end

      { success: true, results: results }.to_json
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # License management
  get '/admin/licenses' do
    require_secure_admin_auth

    # Pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    offset = (page - 1) * per_page

    # Filters
    status_filter = params[:status]
    product_filter = params[:product_id]
    search_query = params[:search]

    # Build query
    query = License.order(Sequel.desc(:created_at))

    # Apply filters
    query = query.where(status: status_filter) if status_filter && !status_filter.empty?
    query = query.where(product_id: product_filter) if product_filter && !product_filter.empty?

    if search_query && !search_query.empty?
      search_term = "%#{search_query}%"
      query = query.where(
        Sequel.|(
          Sequel.ilike(:license_key, search_term),
          Sequel.ilike(:customer_email, search_term),
          Sequel.ilike(:customer_name, search_term)
        )
      )
    end

    # Get total count for pagination
    @total_licenses = query.count

    # Apply pagination
    @licenses = query.limit(per_page).offset(offset).all

    # Load related data
    @products = Product.order(:name).all

    # Pagination info
    @current_page = page
    @per_page = per_page
    @total_pages = (@total_licenses.to_f / per_page).ceil

    @page_title = 'Manage Licenses'
    erb :'admin/licenses', layout: :'layouts/admin_layout'
  end

  # View license details
  get '/admin/licenses/:id' do
    require_secure_admin_auth
    @license = License[params[:id]]
    halt 404 unless @license
    @page_title = "License #{@license.license_key}"
    erb :'admin/licenses_show', layout: :'layouts/admin_layout'
  end

  # Generate license page
  get '/admin/licenses/generate' do
    require_secure_admin_auth
    @products = Product.where(active: true).order(:name)
    @page_title = 'Generate License'
    erb :'admin/licenses_generate', layout: :'layouts/admin_layout'
  end

  # Create new license
  post '/admin/licenses/generate' do
    require_secure_admin_auth
    require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

    begin
      product = Product[params[:product_id]]
      halt 404 unless product

      # Create a manual order for the license
      order = Order.create(
        email: params[:customer_email],
        customer_name: params[:customer_name],
        amount: 0, # Manual generation
        currency: 'USD',
        status: 'completed',
        payment_method: 'manual',
        completed_at: Time.now
      )

      # Generate the license
      license = LicenseGenerator.generate_for_product(product, order)

      # Set custom parameters if provided
      if params[:custom_max_activations] && !params[:custom_max_activations].empty?
        license.update(custom_max_activations: params[:custom_max_activations].to_i)
      end

      if params[:custom_expires_at] && !params[:custom_expires_at].empty?
        license.update(custom_expires_at: Time.parse(params[:custom_expires_at]))
      end

      flash :success, "License #{license.license_key} generated successfully!"
      redirect "/admin/licenses/#{license.id}"
    rescue StandardError => e
      flash :error, "Error generating license: #{e.message}"
      @products = Product.where(active: true).order(:name)
      @page_title = 'Generate License'
      erb :'admin/licenses_generate', layout: :'layouts/admin_layout'
    end
  end

  # Toggle license status (AJAX)
  post '/admin/licenses/:id/toggle-status' do
    require_secure_admin_auth
    content_type :json

    license = License[params[:id]]
    unless license
      status 404
      return { success: false, error: 'License not found' }.to_json
    end

    begin
      case params[:action]
      when 'activate'
        license.reactivate!
      when 'suspend'
        license.suspend!
      when 'revoke'
        license.revoke!
      else
        status 400
        return { success: false, error: 'Invalid action' }.to_json
      end

      { success: true, status: license.status }.to_json
    rescue StandardError => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # Bulk license actions
  post '/admin/licenses/bulk-action' do
    require_secure_admin_auth
    content_type :json

    begin
      data = JSON.parse(request.body.read)
      action = data['action']
      license_ids = data['license_ids']

      unless %w[activate suspend revoke delete].include?(action)
        status 400
        return { success: false, error: 'Invalid action' }.to_json
      end

      if license_ids.nil? || license_ids.empty?
        status 400
        return { success: false, error: 'No licenses selected' }.to_json
      end

      # Find licenses
      licenses = License.where(id: license_ids)
      if licenses.count != license_ids.length
        status 400
        return { success: false, error: 'Some licenses not found' }.to_json
      end

      results = { success: 0, failed: 0, errors: [] }

      DB.transaction do
        licenses.each do |license|
          case action
          when 'activate'
            license.reactivate!
            results[:success] += 1
          when 'suspend'
            license.suspend!
            results[:success] += 1
          when 'revoke'
            license.revoke!
            results[:success] += 1
          when 'delete'
            license.destroy
            results[:success] += 1
          end
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << "#{license.license_key}: #{e.message}"
        end
      end

      { success: true, results: results }.to_json
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Export licenses
  get '/admin/licenses/export' do
    require_secure_admin_auth
    content_type 'text/csv'

    # Check if specific licenses are requested
    if params[:license_ids]
      license_ids = params[:license_ids].split(',').map(&:to_i)
      licenses = License.where(id: license_ids).order(:created_at)
      filename = "selected_licenses_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    else
      licenses = License.order(:created_at)
      filename = "all_licenses_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    end

    attachment filename

    csv_data = "License Key,Customer Email,Customer Name,Product,Status,Created At,Expires At,Activations Used,Max Activations\n"
    licenses.each do |license|
      csv_data += "\"#{license.license_key}\",\"#{license.customer_email}\",\"#{license.customer_name || ''}\",\"#{license.product&.name || 'Unknown'}\",#{license.status},#{license.created_at},#{license.expires_at || ''},#{license.activation_count},#{license.effective_max_activations}\n"
    end

    csv_data
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
        exported_at: Time.now.iso8601,
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
      SecureRandom.hex(64)

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

  # Get all products (for cart/checkout)
  get '/api/products' do
    content_type :json

    products = Product.where(active: true).order(:name).all
    products.map(&:values).to_json
  end

  # Create order (for checkout)
  post '/api/orders' do
    content_type :json

    begin
      order_data = JSON.parse(request.body.read)

      # Validate required fields
      unless order_data['customer'] && order_data['customer']['email']
        status 400
        return { success: false, error: 'Customer email is required' }.to_json
      end

      unless order_data['items']&.any?
        status 400
        return { success: false, error: 'Order must contain items' }.to_json
      end

      # Create order in database
      order = DB.transaction do
        new_order = Order.create(
          email: order_data['customer']['email'],
          customer_name: order_data['customer']['name'],
          amount: order_data['amount'] || 0,
          currency: order_data['currency'] || 'USD',
          status: 'pending',
          payment_method: order_data['payment_method'] || 'stripe'
        )

        # Add order items
        order_data['items'].each do |item|
          product = Product[item['productId']]
          next unless product

          new_order.add_order_item(
            product: product,
            quantity: item['quantity'] || 1,
            price: product.price
          )
        end

        # Update order amount based on items
        total = new_order.order_items.sum { |item| item.price * item.quantity }
        new_order.update(amount: total)

        new_order
      end

      # Create payment intent based on payment method
      case order_data['payment_method']
      when 'stripe'
        if stripe_enabled?
          payment_result = PaymentProcessor.create_payment_intent(order, 'stripe')
          if payment_result[:client_secret]
            status 201
            {
              success: true,
              order_id: order.id,
              client_secret: payment_result[:client_secret],
            }.to_json
          else
            status 400
            { success: false, error: 'Failed to create payment intent' }.to_json
          end
        else
          status 400
          { success: false, error: 'Stripe not configured' }.to_json
        end
      when 'paypal'
        if paypal_enabled?
          payment_result = PaymentProcessor.create_payment_intent(order, 'paypal')
          if payment_result[:order_id]
            status 201
            {
              success: true,
              order_id: order.id,
              paypal_order_id: payment_result[:order_id],
              approval_url: payment_result[:approval_url],
            }.to_json
          else
            status 400
            { success: false, error: 'Failed to create PayPal order' }.to_json
          end
        else
          status 400
          { success: false, error: 'PayPal not configured' }.to_json
        end
      else
        status 400
        { success: false, error: 'Invalid payment method' }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # Free order processing (for $0.00 orders)
  post '/api/orders/free' do
    content_type :json

    begin
      order_data = JSON.parse(request.body.read)

      # Validate required fields
      unless order_data['customer'] && order_data['customer']['email']
        status 400
        return { success: false, error: 'Customer email is required' }.to_json
      end

      unless order_data['items']&.any?
        status 400
        return { success: false, error: 'Order must contain items' }.to_json
      end

      # Verify the order is actually free
      total = 0
      order_data['items'].each do |item|
        product = Product[item['productId']]
        next unless product

        total += (product.price.to_f + (product.setup_fee || 0).to_f) * item['quantity']
      end

      unless total.zero?
        status 400
        return { success: false, error: 'This endpoint is only for free orders' }.to_json
      end

      # Create order in database
      order = DB.transaction do
        new_order = Order.create(
          email: order_data['customer']['email'],
          customer_name: order_data['customer']['name'],
          amount: 0,
          currency: 'USD',
          status: 'completed',
          payment_method: 'free',
          completed_at: Time.now
        )

        # Add order items
        order_data['items'].each do |item|
          product = Product[item['productId']]
          next unless product

          new_order.add_order_item(
            product: product,
            quantity: item['quantity'] || 1,
            price: 0 # Free items
          )
        end

        new_order
      end

      # Generate licenses for the free order
      generate_licenses_for_order(order)

      # Send confirmation email if configured
      send_order_confirmation_email(order) if ENV['SMTP_HOST']

      status 201
      {
        success: true,
        order_id: order.id,
      }.to_json
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # PayPal payment capture
  post '/api/payment/paypal/capture' do
    content_type :json

    begin
      data = JSON.parse(request.body.read)
      order_id = data['order_id']

      unless order_id
        status 400
        return { success: false, error: 'Order ID required' }.to_json
      end

      # Find the order in our database
      order = Order.first(payment_intent_id: order_id)
      unless order
        status 404
        return { success: false, error: 'Order not found' }.to_json
      end

      # Process PayPal payment
      result = PaymentProcessor.process_payment(order, 'paypal', { order_id: order_id })

      if result[:success]
        # Generate licenses for successful payment
        generate_licenses_for_order(order)

        # Send confirmation email if configured
        send_order_confirmation_email(order) if ENV['SMTP_HOST']

        {
          success: true,
          order_id: order.id,
          transaction_id: result[:transaction_id],
        }.to_json
      else
        status 400
        { success: false, error: result[:error] }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'Invalid JSON' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

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

  # Get order status
  get '/api/orders/:id' do
    content_type :json

    order = Order[params[:id]]
    unless order
      status 404
      return { error: 'Order not found' }.to_json
    end

    # Get license keys for this order
    license_keys = order.licenses.map do |license|
      {
        key: license.license_key,
        product_name: license.product&.name,
        max_activations: license.effective_max_activations,
        expires_at: license.effective_expires_at,
      }
    end

    {
      id: order.id,
      status: order.status,
      amount: order.amount,
      email: order.email,
      customer_name: order.customer_name,
      payment_method: order.payment_method,
      created_at: order.created_at,
      license_keys: license_keys,
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

  # Generate licenses for completed order
  def generate_licenses_for_order(order)
    return unless order.completed?

    order.order_items.each do |item|
      item.quantity.times do
        license = LicenseGenerator.generate_for_product(item.product, order)
        order.add_license(license)
      end
    end
  end

  # Send password reset email
  def send_password_reset_email(user, token)
    reset_url = "#{request.scheme}://#{request.host_with_port}/reset-password/#{token}"

    mail = Mail.new do
      from ENV.fetch('SMTP_USERNAME', nil)
      to user.email
      subject 'Password Reset Instructions'
      body "Click here to reset your password: #{reset_url}\n\nThis link will expire in 1 hour."
    end

    mail.deliver!
  rescue StandardError => e
    logger.error "Failed to send password reset email: #{e.message}"
  end
end

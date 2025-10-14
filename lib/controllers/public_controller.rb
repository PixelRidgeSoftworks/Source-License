# frozen_string_literal: true

require_relative 'route_primitive'

# Controller for public storefront routes
module PublicController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # PUBLIC ROUTES - Website Frontend
    # ==================================================

    # Main frontend routes
    homepage_route(app)
    products_listing_route(app)
    product_details_route(app)
    cart_page_route(app)
    checkout_page_route(app)
    success_page_route(app)

    # License validation
    license_validation_page_route(app)
    license_validation_api_route(app)

    # Legacy redirects
    legacy_my_licenses_route(app)
    legacy_license_route(app)
    legacy_download_route(app)
  end

  # Homepage / Landing page
  def self.homepage_route(app)
    app.get '/' do
      @page_title = custom('branding.site_name', 'Software License Store')
      erb :index, layout: :'layouts/main_layout'
    end
  end

  # Products listing page
  def self.products_listing_route(app)
    app.get '/products' do
      @products = Product.where(active: true).where(Sequel.~(name: nil)).where(Sequel.~(name: '')).order(:name).all
      @categories = ProductCategory.order(:name).all
      @page_title = custom('text.products_title', 'Our Software Products')
      erb :products, layout: :'layouts/main_layout'
    end
  end

  # Product details page
  def self.product_details_route(app)
    app.get '/product/:id' do
      @product = Product[params[:id]]
      halt 404 unless @product&.active
      @page_title = @product.name
      erb :'products/show', layout: :'layouts/main_layout'
    end
  end

  # Cart page
  def self.cart_page_route(app)
    app.get '/cart' do
      @products = Product.where(active: true).where(Sequel.~(name: nil)).where(Sequel.~(name: '')).order(:name).all
      @page_title = 'Shopping Cart'
      erb :cart, layout: :'layouts/main_layout'
    end
  end

  # Checkout page
  def self.checkout_page_route(app)
    app.get '/checkout' do
      @products = Product.where(active: true).where(Sequel.~(name: nil)).where(Sequel.~(name: '')).order(:name).all
      @page_title = 'Checkout'
      erb :checkout, layout: :'layouts/main_layout'
    end
  end

  # Purchase success page
  def self.success_page_route(app)
    app.get '/success' do
      @order_id = params[:order_id]
      @order = nil

      @order = Order[params[:order_id]] if @order_id

      @page_title = 'Purchase Successful'
      erb :success, layout: :'layouts/main_layout'
    end
  end

  # Public license validation page (read-only, no sensitive info)
  def self.license_validation_page_route(app)
    app.get '/validate-license' do
      @page_title = 'Validate License'
      erb :'licenses/validate', layout: :'layouts/main_layout'
    end
  end

  # Public license validation API
  def self.license_validation_api_route(app)
    app.post '/validate-license' do
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
  end

  # Legacy redirect for /my-licenses
  def self.legacy_my_licenses_route(app)
    app.get '/my-licenses' do
      redirect '/login' unless user_logged_in?
      redirect '/licenses'
    end
  end

  # Legacy redirect for individual license access
  def self.legacy_license_route(app)
    app.get '/license/:key' do
      redirect '/login' unless user_logged_in?
      # Try to find the license and redirect to secure version
      license = License.first(license_key: params[:key])
      if license && user_owns_license?(current_user, license)
        redirect "/licenses/#{license.id}"
      else
        halt 404
      end
    end
  end

  # Legacy download route (security disabled)
  def self.legacy_download_route(app)
    app.get '/download/:license_key/:file' do
      halt 403, 'Direct downloads are no longer supported. Please log in to access your licenses.'
    end
  end
end

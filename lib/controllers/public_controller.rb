# frozen_string_literal: true

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

    # Homepage / Storefront
    app.get '/' do
      @products = Product.where(active: true).order(:name)
      @page_title = custom('branding.site_name', 'Software License Store')
      erb :index, layout: :'layouts/main_layout'
    end

    # Product details page
    app.get '/product/:id' do
      @product = Product[params[:id]]
      halt 404 unless @product&.active
      @page_title = @product.name
      erb :'products/show', layout: :'layouts/main_layout'
    end

    # Cart page
    app.get '/cart' do
      @products = Product.where(active: true).order(:name).all
      @page_title = 'Shopping Cart'
      erb :cart, layout: :'layouts/main_layout'
    end

    # Checkout page
    app.get '/checkout' do
      @products = Product.where(active: true).order(:name).all
      @page_title = 'Checkout'
      erb :checkout, layout: :'layouts/main_layout'
    end

    # Purchase success page
    app.get '/success' do
      @order_id = params[:order_id]
      @order = nil

      @order = Order[params[:order_id]] if @order_id

      @page_title = 'Purchase Successful'
      erb :success, layout: :'layouts/main_layout'
    end

    # Public license validation (read-only, no sensitive info)
    app.get '/validate-license' do
      @page_title = 'Validate License'
      erb :'licenses/validate', layout: :'layouts/main_layout'
    end

    # Public license validation API
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

    # Redirect old insecure routes to secure versions
    app.get '/my-licenses' do
      redirect '/login' unless user_logged_in?
      redirect '/licenses'
    end

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

    # Secure download route (old insecure route disabled)
    app.get '/download/:license_key/:file' do
      halt 403, 'Direct downloads are no longer supported. Please log in to access your licenses.'
    end
  end
end

# frozen_string_literal: true

# Controller for admin product management routes
module AdminControllers::ProductsController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # ADMIN PRODUCT MANAGEMENT ROUTES
    # ==================================================

    # Product management
    app.get '/admin/products' do
      require_secure_admin_auth
      @products = Product.order(:name)
      @page_title = 'Manage Products'
      erb :'admin/products', layout: :'layouts/admin_layout'
    end

    # Add new product form
    app.get '/admin/products/new' do
      require_secure_admin_auth
      @page_title = 'Add New Product'
      erb :'admin/products_new', layout: :'layouts/admin_layout'
    end

    # Auto-save product draft (AJAX)
    app.post '/admin/products/auto-save' do
      require_secure_admin_auth
      content_type :json

      # Just return success for now - this is a placeholder for auto-save functionality
      { success: true, message: 'Draft saved' }.to_json
    end

    # Create new product
    app.post '/admin/products' do
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
    app.get '/admin/products/:id' do
      require_secure_admin_auth
      @product = Product[params[:id]]
      halt 404 unless @product
      @page_title = @product.name
      erb :'admin/products_show', layout: :'layouts/admin_layout'
    end

    # Edit product form
    app.get '/admin/products/:id/edit' do
      require_secure_admin_auth
      @product = Product[params[:id]]
      halt 404 unless @product
      @page_title = "Edit #{@product.name}"
      erb :'admin/products_edit', layout: :'layouts/admin_layout'
    end

    # Update product
    app.put '/admin/products/:id' do
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
    app.post '/admin/products/:id/toggle-status' do
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
    app.delete '/admin/products/:id' do
      require_secure_admin_auth
      content_type :json

      product = Product[params[:id]]
      unless product
        status 404
        return { success: false, error: 'Product not found' }.to_json
      end

      begin
        # Check if product has associated licenses
        if product.licenses.any?
          return { success: false,
                   error: 'Cannot delete product with existing licenses', }.to_json
        end

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
    app.get '/admin/products/:id/duplicate' do
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
    app.get '/admin/products/export' do
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
    app.post '/admin/products/bulk-action' do
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
  end
end

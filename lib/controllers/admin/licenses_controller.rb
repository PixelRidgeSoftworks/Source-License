# frozen_string_literal: true

# Controller for admin license management routes
module AdminControllers::LicensesController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # ADMIN LICENSE MANAGEMENT ROUTES
    # ==================================================

    # License management
    app.get '/admin/licenses' do
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
    app.get '/admin/licenses/:id' do
      require_secure_admin_auth
      @license = License[params[:id]]
      halt 404 unless @license
      @page_title = "License #{@license.license_key}"
      erb :'admin/licenses_show', layout: :'layouts/admin_layout'
    end

    # Generate license page
    app.get '/admin/licenses/generate' do
      require_secure_admin_auth
      @products = Product.where(active: true).order(:name)
      @page_title = 'Generate License'
      erb :'admin/licenses_generate', layout: :'layouts/admin_layout'
    end

    # Create new license
    app.post '/admin/licenses/generate' do
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
    app.post '/admin/licenses/:id/toggle-status' do
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
    app.post '/admin/licenses/bulk-action' do
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
    app.get '/admin/licenses/export' do
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
  end
end

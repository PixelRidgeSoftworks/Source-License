# frozen_string_literal: true

require_relative '../core/route_primitive'

# Admin Customers Controller
# Handles customer management operations

module AdminControllers::CustomersController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # Customer management routes
    customers_list_route(app)
    customer_details_route(app)
    customer_toggle_status_route(app)
    customer_edit_page_route(app)
    customer_update_route(app)
    customers_bulk_action_route(app)
    customers_export_route(app)
  end

  # Customer management list with pagination and filters
  def self.customers_list_route(app)
    app.get '/admin/customers' do
      require_secure_admin_auth

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 50).to_i
      offset = (page - 1) * per_page

      # Filters
      status_filter = params[:status]
      search_query = params[:search]
      date_filter = params[:date_filter]

      # Build query
      query = User.order(Sequel.desc(:created_at))

      # Apply filters
      query = query.where(status: status_filter) if status_filter && !status_filter.empty?

      if search_query && !search_query.empty?
        search_term = "%#{search_query}%"
        query = query.where(
          Sequel.|(
            Sequel.ilike(:email, search_term),
            Sequel.ilike(:name, search_term)
          )
        )
      end

      # Date filtering
      if date_filter && !date_filter.empty?
        case date_filter
        when 'today'
          query = query.where(created_at: Date.today..(Date.today + 1))
        when 'week'
          query = query.where(created_at: (Date.today - 7)..(Date.today + 1))
        when 'month'
          query = query.where(created_at: (Date.today - 30)..(Date.today + 1))
        when 'year'
          query = query.where(created_at: (Date.today - 365)..(Date.today + 1))
        end
      end

      # Get total count for pagination
      @total_customers = query.count

      # Apply pagination
      @customers = query.limit(per_page).offset(offset).all

      # Pagination info
      @current_page = page
      @per_page = per_page
      @total_pages = (@total_customers.to_f / per_page).ceil

      @page_title = 'Manage Customers'
      erb :'admin/customers', layout: :'layouts/admin_layout'
    end
  end

  # View customer details
  def self.customer_details_route(app)
    app.get '/admin/customers/:id' do
      require_secure_admin_auth
      @customer = User[params[:id]]
      halt 404 unless @customer
      @page_title = "Customer: #{@customer.display_name}"
      erb :'admin/customers_show', layout: :'layouts/admin_layout'
    end
  end

  # Toggle customer status (AJAX)
  def self.customer_toggle_status_route(app)
    app.post '/admin/customers/:id/toggle-status' do
      require_secure_admin_auth
      content_type :json

      customer = User[params[:id]]
      unless customer
        status 404
        return { success: false, error: 'Customer not found' }.to_json
      end

      begin
        case params[:action]
        when 'activate'
          customer.activate!
        when 'deactivate'
          customer.deactivate!
        when 'suspend'
          customer.suspend!
        else
          status 400
          return { success: false, error: 'Invalid action' }.to_json
        end

        { success: true, status: customer.status }.to_json
      rescue StandardError => e
        status 400
        { success: false, error: e.message }.to_json
      end
    end
  end

  # Edit customer form
  def self.customer_edit_page_route(app)
    app.get '/admin/customers/:id/edit' do
      require_secure_admin_auth
      @customer = User[params[:id]]
      halt 404 unless @customer
      @page_title = "Edit Customer: #{@customer.display_name}"
      erb :'admin/customers_edit', layout: :'layouts/admin_layout'
    end
  end

  # Update customer details
  def self.customer_update_route(app)
    app.put '/admin/customers/:id' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

      @customer = User[params[:id]]
      halt 404 unless @customer

      begin
        # Update customer details
        update_params = {
          name: params[:name]&.strip,
          email: params[:email]&.strip&.downcase,
          status: params[:status],
          updated_at: Time.now,
        }

        # Handle password change if provided
        if params[:new_password] && !params[:new_password].empty?
          if params[:new_password].length >= 8
            @customer.password = params[:new_password]
            update_params[:password_changed_at] = Time.now
          else
            flash :error, 'Password must be at least 8 characters long.'
            @page_title = "Edit Customer: #{@customer.display_name}"
            return erb :'admin/customers_edit', layout: :'layouts/admin_layout'
          end
        end

        @customer.update(update_params)

        if @customer.valid?
          flash :success, 'Customer updated successfully!'
          redirect "/admin/customers/#{@customer.id}"
        else
          flash :error, "Error updating customer: #{@customer.errors.full_messages.join(', ')}"
          @page_title = "Edit Customer: #{@customer.display_name}"
          erb :'admin/customers_edit', layout: :'layouts/admin_layout'
        end
      rescue StandardError => e
        flash :error, "Error updating customer: #{e.message}"
        @page_title = "Edit Customer: #{@customer.display_name}"
        erb :'admin/customers_edit', layout: :'layouts/admin_layout'
      end
    end
  end

  # Bulk customer actions
  def self.customers_bulk_action_route(app)
    app.post '/admin/customers/bulk-action' do
      require_secure_admin_auth
      content_type :json

      begin
        data = JSON.parse(request.body.read)
        action = data['action']
        customer_ids = data['customer_ids']

        unless %w[activate deactivate suspend delete].include?(action)
          status 400
          return { success: false, error: 'Invalid action' }.to_json
        end

        if customer_ids.nil? || customer_ids.empty?
          status 400
          return { success: false, error: 'No customers selected' }.to_json
        end

        # Find customers
        customers = User.where(id: customer_ids)
        if customers.count != customer_ids.length
          status 400
          return { success: false, error: 'Some customers not found' }.to_json
        end

        results = { success: 0, failed: 0, errors: [] }

        DB.transaction do
          customers.each do |customer|
            case action
            when 'activate'
              customer.activate!
              results[:success] += 1
            when 'deactivate'
              customer.deactivate!
              results[:success] += 1
            when 'suspend'
              customer.suspend!
              results[:success] += 1
            when 'delete'
              # Check if customer has licenses or orders
              if customer.licenses.any?
                results[:failed] += 1
                results[:errors] << "#{customer.display_name}: Cannot delete customer with existing licenses"
              else
                customer.destroy
                results[:success] += 1
              end
            end
          rescue StandardError => e
            results[:failed] += 1
            results[:errors] << "#{customer.display_name}: #{e.message}"
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

  # Export customers
  def self.customers_export_route(app)
    app.get '/admin/customers/export' do
      require_secure_admin_auth
      content_type 'text/csv'

      # Check if specific customers are requested
      if params[:customer_ids]
        customer_ids = params[:customer_ids].split(',').map(&:to_i)
        customers = User.where(id: customer_ids).order(:created_at)
        filename = "selected_customers_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
      else
        customers = User.order(:created_at)
        filename = "all_customers_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
      end

      attachment filename

      csv_data = "ID,Name,Email,Status,Email Verified,License Count,Total Orders,Last Login,Created At\n"
      customers.each do |customer|
        csv_data += "#{customer.id},\"#{customer.name || ''}\",\"#{customer.email}\",#{customer.status},#{customer.email_verified?},#{customer.license_count},#{Order.where(email: customer.email).count},#{customer.last_login_at || ''},#{customer.created_at}\n"
      end

      csv_data
    end
  end
end

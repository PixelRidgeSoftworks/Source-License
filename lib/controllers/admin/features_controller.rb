# frozen_string_literal: true

# Controller for admin order, customer, report, and customization routes
module AdminControllers::FeaturesController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # ORDER MANAGEMENT ROUTES
    # ==================================================

    # Order management
    app.get '/admin/orders' do
      require_secure_admin_auth

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 50).to_i
      offset = (page - 1) * per_page

      # Filters
      status_filter = params[:status]
      payment_method_filter = params[:payment_method]
      search_query = params[:search]
      date_filter = params[:date_filter]

      # Build query
      query = Order.order(Sequel.desc(:created_at))

      # Apply filters
      query = query.where(status: status_filter) if status_filter && !status_filter.empty?
      if payment_method_filter && !payment_method_filter.empty?
        query = query.where(payment_method: payment_method_filter)
      end

      if search_query && !search_query.empty?
        search_term = "%#{search_query}%"
        query = query.where(
          Sequel.|(
            Sequel.ilike(:email, search_term),
            Sequel.ilike(:customer_name, search_term),
            Sequel.like(:id, search_term)
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
      @total_orders = query.count

      # Apply pagination
      @orders = query.limit(per_page).offset(offset).all

      # Pagination info
      @current_page = page
      @per_page = per_page
      @total_pages = (@total_orders.to_f / per_page).ceil

      @page_title = 'Manage Orders'
      erb :'admin/orders', layout: :'layouts/admin_layout'
    end

    # View order details
    app.get '/admin/orders/:id' do
      require_secure_admin_auth
      @order = Order[params[:id]]
      halt 404 unless @order
      @page_title = "Order ##{@order.id}"
      erb :'admin/orders_show', layout: :'layouts/admin_layout'
    end

    # Update order status
    app.post '/admin/orders/:id/update-status' do
      require_secure_admin_auth
      content_type :json

      order = Order[params[:id]]
      unless order
        status 404
        return { success: false, error: 'Order not found' }.to_json
      end

      new_status = params[:status]
      unless %w[pending completed failed refunded].include?(new_status)
        status 400
        return { success: false, error: 'Invalid status' }.to_json
      end

      begin
        case new_status
        when 'completed'
          order.complete!
          # Generate licenses if not already generated
          generate_licenses_for_order(order) if order.licenses.empty?
        when 'refunded'
          order.update(status: 'refunded', refunded_at: Time.now)
          # Revoke associated licenses
          order.licenses.each(&:revoke!)
        else
          order.update(status: new_status)
        end

        { success: true, status: order.status }.to_json
      rescue StandardError => e
        status 400
        { success: false, error: e.message }.to_json
      end
    end

    # Bulk order actions
    app.post '/admin/orders/bulk-action' do
      require_secure_admin_auth
      content_type :json

      begin
        data = JSON.parse(request.body.read)
        action = data['action']
        order_ids = data['order_ids']

        unless %w[complete refund delete].include?(action)
          status 400
          return { success: false, error: 'Invalid action' }.to_json
        end

        if order_ids.nil? || order_ids.empty?
          status 400
          return { success: false, error: 'No orders selected' }.to_json
        end

        # Find orders
        orders = Order.where(id: order_ids)
        if orders.count != order_ids.length
          status 400
          return { success: false, error: 'Some orders not found' }.to_json
        end

        results = { success: 0, failed: 0, errors: [] }

        DB.transaction do
          orders.each do |order|
            case action
            when 'complete'
              if order.pending?
                order.complete!
                generate_licenses_for_order(order) if order.licenses.empty?
                results[:success] += 1
              else
                results[:failed] += 1
                results[:errors] << "Order ##{order.id}: Already #{order.status}"
              end
            when 'refund'
              if order.completed?
                order.update(status: 'refunded', refunded_at: Time.now)
                order.licenses.each(&:revoke!)
                results[:success] += 1
              else
                results[:failed] += 1
                results[:errors] << "Order ##{order.id}: Cannot refund #{order.status} order"
              end
            when 'delete'
              if order.pending? || order.failed?
                # Remove associated licenses if any
                order.licenses.each(&:destroy)
                order.destroy
                results[:success] += 1
              else
                results[:failed] += 1
                results[:errors] << "Order ##{order.id}: Cannot delete #{order.status} order"
              end
            end
          rescue StandardError => e
            results[:failed] += 1
            results[:errors] << "Order ##{order.id}: #{e.message}"
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

    # Export orders
    app.get '/admin/orders/export' do
      require_secure_admin_auth
      content_type 'text/csv'

      # Check if specific orders are requested
      if params[:order_ids]
        order_ids = params[:order_ids].split(',').map(&:to_i)
        orders = Order.where(id: order_ids).order(:created_at)
        filename = "selected_orders_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
      else
        orders = Order.order(:created_at)
        filename = "all_orders_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
      end

      attachment filename

      csv_data = "Order ID,Customer Email,Customer Name,Amount,Currency,Status,Payment Method,Created At,Completed At,Items\n"
      orders.each do |order|
        items = order.order_items.map { |item| "#{item.product&.name} (#{item.quantity}x)" }.join('; ')
        csv_data += "#{order.id},\"#{order.email}\",\"#{order.customer_name || ''}\",#{order.amount},#{order.currency},#{order.status},#{order.payment_method},#{order.created_at},#{order.completed_at || ''},\"#{items}\"\n"
      end

      csv_data
    end

    # ==================================================
    # CUSTOMER MANAGEMENT ROUTES
    # ==================================================

    # Customer management
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

    # View customer details
    app.get '/admin/customers/:id' do
      require_secure_admin_auth
      @customer = User[params[:id]]
      halt 404 unless @customer
      @page_title = "Customer: #{@customer.display_name}"
      erb :'admin/customers_show', layout: :'layouts/admin_layout'
    end

    # Toggle customer status (AJAX)
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

    # Edit customer form
    app.get '/admin/customers/:id/edit' do
      require_secure_admin_auth
      @customer = User[params[:id]]
      halt 404 unless @customer
      @page_title = "Edit Customer: #{@customer.display_name}"
      erb :'admin/customers_edit', layout: :'layouts/admin_layout'
    end

    # Update customer details
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

    # Bulk customer actions
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

    # Export customers
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

    # ==================================================
    # REPORTS ADMIN ROUTES
    # ==================================================

    # Admin reports dashboard
    app.get '/admin/reports' do
      require_secure_admin_auth
      @page_title = 'Reports & Analytics'

      # Date range parameters
      start_date = params[:start_date] ? Date.parse(params[:start_date]) : Date.today - 30
      end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today

      # Convert dates to time objects for database queries
      start_time = start_date.to_time
      end_time = end_date.to_time + (24 * 60 * 60) - 1 # End of day

      @date_range = { start: start_date, end: end_date }

      # Revenue metrics
      @revenue_stats = calculate_revenue_stats(start_time, end_time)

      # License metrics
      @license_stats = calculate_license_stats(start_time, end_time)

      # Order metrics
      @order_stats = calculate_order_stats(start_time, end_time)

      # Customer metrics
      @customer_stats = calculate_customer_stats(start_time, end_time)

      # Product performance
      @product_performance = calculate_product_performance(start_time, end_time)

      # Chart data for frontend
      @chart_data = {
        revenue_trend: calculate_revenue_trend(start_time, end_time),
        license_distribution: calculate_license_distribution,
        order_status_distribution: calculate_order_status_distribution(start_time, end_time),
        monthly_growth: calculate_monthly_growth_data,
      }

      erb :'admin/reports', layout: :'layouts/admin_layout'
    end

    # Export reports data
    app.get '/admin/reports/export' do
      require_secure_admin_auth

      format = params[:format] || 'csv'
      report_type = params[:type] || 'summary'
      start_date = params[:start_date] ? Date.parse(params[:start_date]) : Date.today - 30
      end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today

      start_time = start_date.to_time
      end_time = end_date.to_time + (24 * 60 * 60) - 1

      case format
      when 'csv'
        content_type 'text/csv'
        attachment "#{report_type}_report_#{start_date}_to_#{end_date}.csv"

        case report_type
        when 'revenue'
          generate_revenue_csv_report(start_time, end_time)
        when 'licenses'
          generate_licenses_csv_report(start_time, end_time)
        when 'orders'
          generate_orders_csv_report(start_time, end_time)
        when 'customers'
          generate_customers_csv_report(start_time, end_time)
        else
          generate_summary_csv_report(start_time, end_time)
        end
      when 'json'
        content_type :json
        attachment "#{report_type}_report_#{start_date}_to_#{end_date}.json"

        {
          report_type: report_type,
          date_range: { start: start_date, end: end_date },
          revenue_stats: calculate_revenue_stats(start_time, end_time),
          license_stats: calculate_license_stats(start_time, end_time),
          order_stats: calculate_order_stats(start_time, end_time),
          customer_stats: calculate_customer_stats(start_time, end_time),
          product_performance: calculate_product_performance(start_time, end_time),
        }.to_json
      else
        halt 400, 'Invalid format'
      end
    end

    # ==================================================
    # CUSTOMIZATION ADMIN ROUTES
    # ==================================================

    # Template customization main page
    app.get '/admin/customize' do
      require_secure_admin_auth
      @page_title = 'Template Customization'
      @categories = TemplateCustomizer.get_categories
      @customizations = TemplateCustomizer.get_all_customizations
      erb :'admin/customize', layout: :'layouts/admin_layout'
    end

    # Update customizations
    app.post '/admin/customize' do
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
    app.post '/admin/customize/reset' do
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
    app.get '/admin/customize/export' do
      require_secure_admin_auth
      content_type 'application/x-yaml'
      attachment 'customizations.yml'
      TemplateCustomizer.export_customizations
    end

    # Import customizations
    app.post '/admin/customize/import' do
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
    app.get '/admin/customize/code-guide' do
      require_secure_admin_auth
      @page_title = 'Template Code Guide'
      erb :'admin/code_guide', layout: :'layouts/admin_layout'
    end

    # Live preview endpoint
    app.get '/admin/customize/preview' do
      require_secure_admin_auth
      @page_title = custom('branding.site_name', 'Source License')
      @products = Product.where(active: true).order(:name).limit(3)
      erb :index, layout: :'layouts/main_layout'
    end
  end

  # Generate licenses for completed order
  def self.generate_licenses_for_order(order)
    return unless order.completed?

    order.order_items.each do |item|
      item.quantity.times do
        license = LicenseGenerator.generate_for_product(item.product, order)
        order.add_license(license)
      end
    end
  end

  # Calculate revenue statistics for date range
  def self.calculate_revenue_stats(start_time, end_time)
    completed_orders = Order.where(status: 'completed', created_at: start_time..end_time)

    total_revenue = completed_orders.sum(:amount) || 0
    order_count = completed_orders.count
    avg_order_value = order_count.positive? ? total_revenue / order_count : 0

    # Previous period comparison
    period_length = end_time - start_time
    previous_start = start_time - period_length
    previous_end = start_time

    previous_revenue = Order.where(status: 'completed', created_at: previous_start..previous_end).sum(:amount) || 0
    revenue_growth = previous_revenue.positive? ? ((total_revenue - previous_revenue) / previous_revenue * 100) : 0

    {
      total_revenue: total_revenue,
      order_count: order_count,
      avg_order_value: avg_order_value,
      revenue_growth: revenue_growth,
      previous_revenue: previous_revenue,
    }
  end

  # Calculate license statistics for date range
  def self.calculate_license_stats(start_time, end_time)
    licenses_in_period = License.where(created_at: start_time..end_time)

    total_licenses = licenses_in_period.count
    active_licenses = licenses_in_period.where(status: 'active').count
    suspended_licenses = licenses_in_period.where(status: 'suspended').count
    revoked_licenses = licenses_in_period.where(status: 'revoked').count

    # Overall license health
    all_licenses = License.all
    overall_active = all_licenses.count(&:active?)
    overall_total = all_licenses.count

    activation_rate = total_licenses.positive? ? (active_licenses.to_f / total_licenses * 100) : 0

    {
      total_licenses: total_licenses,
      active_licenses: active_licenses,
      suspended_licenses: suspended_licenses,
      revoked_licenses: revoked_licenses,
      activation_rate: activation_rate,
      overall_active: overall_active,
      overall_total: overall_total,
    }
  end

  # Calculate order statistics for date range
  def self.calculate_order_stats(start_time, end_time)
    orders_in_period = Order.where(created_at: start_time..end_time)

    total_orders = orders_in_period.count
    completed_orders = orders_in_period.where(status: 'completed').count
    pending_orders = orders_in_period.where(status: 'pending').count
    failed_orders = orders_in_period.where(status: 'failed').count
    refunded_orders = orders_in_period.where(status: 'refunded').count

    completion_rate = total_orders.positive? ? (completed_orders.to_f / total_orders * 100) : 0
    failure_rate = total_orders.positive? ? (failed_orders.to_f / total_orders * 100) : 0

    # Payment method breakdown
    begin
      payment_methods = orders_in_period.group(:payment_method).count
      payment_methods = {} unless payment_methods.is_a?(Hash)
    rescue StandardError
      payment_methods = {}
    end

    {
      total_orders: total_orders,
      completed_orders: completed_orders,
      pending_orders: pending_orders,
      failed_orders: failed_orders,
      refunded_orders: refunded_orders,
      completion_rate: completion_rate,
      failure_rate: failure_rate,
      payment_methods: payment_methods,
    }
  end

  # Calculate customer statistics for date range
  def self.calculate_customer_stats(start_time, end_time)
    new_customers = User.where(created_at: start_time..end_time).count

    # Customer activity
    active_customers = User.where(last_login_at: start_time..end_time).count
    total_customers = User.count

    # Customer with orders in period
    customers_with_orders = DB[:orders]
      .where(created_at: start_time..end_time)
      .select(:email)
      .distinct
      .count

    # Repeat customers
    repeat_customers_data = DB[:orders]
      .where(created_at: start_time..end_time)
      .group(:email)
      .having { count.function.* > 1 }
      .select(:email)
      .all

    repeat_customers = repeat_customers_data.length
    repeat_rate = customers_with_orders.positive? ? (repeat_customers.to_f / customers_with_orders * 100) : 0

    {
      new_customers: new_customers,
      active_customers: active_customers,
      total_customers: total_customers,
      customers_with_orders: customers_with_orders,
      repeat_customers: repeat_customers,
      repeat_rate: repeat_rate,
    }
  end

  # Calculate product performance for date range
  def self.calculate_product_performance(start_time, end_time)
    # Get order items in the period with product info
    performance_data = DB[:order_items]
      .join(:orders, id: :order_id)
      .join(:products, id: Sequel[:order_items][:product_id])
      .where(Sequel[:orders][:created_at] => start_time..end_time)
      .where(Sequel[:orders][:status] => 'completed')
      .group(Sequel[:products][:id], Sequel[:products][:name])
      .select(
        Sequel[:products][:id],
        Sequel[:products][:name],
        Sequel.function(:sum, Sequel[:order_items][:quantity]).as(:total_quantity),
        Sequel.function(:sum,
                        Sequel[:order_items][:price] * Sequel[:order_items][:quantity]).as(:total_revenue),
        Sequel.function(:count, Sequel[:orders][:id]).as(:order_count)
      )
      .order(Sequel.desc(:total_revenue))
      .limit(10)
      .all

    performance_data.map do |row|
      {
        product_id: row[:id],
        product_name: row[:name],
        units_sold: row[:total_quantity],
        revenue: row[:total_revenue],
        order_count: row[:order_count],
      }
    end
  end

  # Calculate revenue trend data for charts
  def self.calculate_revenue_trend(start_time, end_time)
    # Group by day for date ranges up to 90 days, otherwise by week
    period_length = (end_time - start_time) / (24 * 60 * 60)

    if period_length <= 90
      # Daily grouping
      date_func = Sequel.function(:date, :created_at)

      DB[:orders]
        .where(status: 'completed', created_at: start_time..end_time)
        .group(date_func)
        .select(
          date_func.as(:date),
          Sequel.function(:sum, :amount).as(:revenue),
          Sequel.function(:count, :id).as(:order_count)
        )
        .order(:date)
        .all
    else
      # Weekly grouping
      week_func = case DB.database_type
                  when :postgres
                    Sequel.function(:to_char, :created_at, 'YYYY-WW')
                  when :mysql
                    Sequel.function(:date_format, :created_at, '%Y-%u')
                  else # SQLite and others
                    Sequel.function(:strftime, '%Y-%W', :created_at)
                  end

      DB[:orders]
        .where(status: 'completed', created_at: start_time..end_time)
        .group(week_func)
        .select(
          week_func.as(:week),
          Sequel.function(:sum, :amount).as(:revenue),
          Sequel.function(:count, :id).as(:order_count)
        )
        .order(:week)
        .all
    end
  end

  # Calculate license distribution by status
  def self.calculate_license_distribution
    result = License.group(:status).count
    result.empty? ? { 'no_data' => 1 } : result
  end

  # Calculate order status distribution for date range
  def self.calculate_order_status_distribution(start_time, end_time)
    result = Order.where(created_at: start_time..end_time).group(:status).count
    result.empty? ? { 'no_data' => 1 } : result
  end

  # Calculate monthly growth data for the last 12 months
  def self.calculate_monthly_growth_data
    twelve_months_ago = Date.today - 365

    month_func = case DB.database_type
                 when :postgres
                   Sequel.function(:to_char, :created_at, 'YYYY-MM')
                 when :mysql
                   Sequel.function(:date_format, :created_at, '%Y-%m')
                 else # SQLite and others
                   Sequel.function(:strftime, '%Y-%m', :created_at)
                 end

    DB[:orders]
      .where(status: 'completed')
      .where(Sequel[:created_at] >= twelve_months_ago)
      .group(month_func)
      .select(
        month_func.as(:month),
        Sequel.function(:sum, :amount).as(:revenue),
        Sequel.function(:count, :id).as(:order_count)
      )
      .order(:month)
      .all
  end

  # Generate CSV reports
  def self.generate_summary_csv_report(start_time, end_time)
    revenue_stats = calculate_revenue_stats(start_time, end_time)
    license_stats = calculate_license_stats(start_time, end_time)
    order_stats = calculate_order_stats(start_time, end_time)
    customer_stats = calculate_customer_stats(start_time, end_time)

    csv_data = "Metric,Value\n"
    csv_data += "Period,#{start_time.strftime('%Y-%m-%d')} to #{end_time.strftime('%Y-%m-%d')}\n"
    csv_data += "Total Revenue,#{format_currency(revenue_stats[:total_revenue])}\n"
    csv_data += "Total Orders,#{order_stats[:total_orders]}\n"
    csv_data += "Completed Orders,#{order_stats[:completed_orders]}\n"
    csv_data += "Order Completion Rate,#{format('%.1f', order_stats[:completion_rate])}%\n"
    csv_data += "Average Order Value,#{format_currency(revenue_stats[:avg_order_value])}\n"
    csv_data += "Total Licenses Generated,#{license_stats[:total_licenses]}\n"
    csv_data += "Active Licenses,#{license_stats[:active_licenses]}\n"
    csv_data += "License Activation Rate,#{format('%.1f', license_stats[:activation_rate])}%\n"
    csv_data += "New Customers,#{customer_stats[:new_customers]}\n"
    csv_data += "Repeat Customer Rate,#{format('%.1f', customer_stats[:repeat_rate])}%\n"

    csv_data
  end

  def self.generate_revenue_csv_report(start_time, end_time)
    orders = Order.where(status: 'completed', created_at: start_time..end_time).order(:created_at)

    csv_data = "Date,Order ID,Customer Email,Amount,Payment Method,Products\n"
    orders.each do |order|
      products = order.order_items.map { |item| "#{item.product&.name} (#{item.quantity}x)" }.join('; ')
      csv_data += "#{order.created_at.strftime('%Y-%m-%d')},#{order.id},\"#{order.email}\",#{order.amount},#{order.payment_method},\"#{products}\"\n"
    end

    csv_data
  end

  def self.generate_licenses_csv_report(start_time, end_time)
    licenses = License.where(created_at: start_time..end_time).order(:created_at)

    csv_data = "Date,License Key,Customer Email,Product,Status,Max Activations,Used Activations\n"
    licenses.each do |license|
      csv_data += "#{license.created_at.strftime('%Y-%m-%d')},\"#{license.license_key}\",\"#{license.customer_email}\",\"#{license.product&.name || 'Unknown'}\",#{license.status},#{license.effective_max_activations},#{license.activation_count}\n"
    end

    csv_data
  end

  def self.generate_orders_csv_report(start_time, end_time)
    orders = Order.where(created_at: start_time..end_time).order(:created_at)

    csv_data = "Date,Order ID,Customer Email,Customer Name,Amount,Status,Payment Method,Items Count\n"
    orders.each do |order|
      items_count = order.order_items.count
      csv_data += "#{order.created_at.strftime('%Y-%m-%d')},#{order.id},\"#{order.email}\",\"#{order.customer_name || ''}\",#{order.amount},#{order.status},#{order.payment_method},#{items_count}\n"
    end

    csv_data
  end

  def self.generate_customers_csv_report(start_time, end_time)
    customers = User.where(created_at: start_time..end_time).order(:created_at)

    csv_data = "Registration Date,Name,Email,Status,License Count,Total Orders,Last Login\n"
    customers.each do |customer|
      order_count = Order.where(email: customer.email).count
      csv_data += "#{customer.created_at.strftime('%Y-%m-%d')},\"#{customer.name || ''}\",\"#{customer.email}\",#{customer.status},#{customer.license_count},#{order_count},#{customer.last_login_at&.strftime('%Y-%m-%d') || 'Never'}\n"
    end

    csv_data
  end

  def self.format_currency(amount, _currency = 'USD')
    "$#{format('%.2f', amount || 0)}"
  end
end

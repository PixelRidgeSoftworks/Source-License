# frozen_string_literal: true

# Admin Reports Controller
# Handles reports and analytics functionality

module AdminControllers::ReportsController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
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
      @revenue_stats = AdminControllers::ReportsController.calculate_revenue_stats(start_time, end_time)

      # License metrics
      @license_stats = AdminControllers::ReportsController.calculate_license_stats(start_time, end_time)

      # Order metrics
      @order_stats = AdminControllers::ReportsController.calculate_order_stats(start_time, end_time)

      # Customer metrics
      @customer_stats = AdminControllers::ReportsController.calculate_customer_stats(start_time, end_time)

      # Product performance
      @product_performance = AdminControllers::ReportsController.calculate_product_performance(start_time, end_time)

      # Chart data for frontend
      @chart_data = {
        revenue_trend: AdminControllers::ReportsController.calculate_revenue_trend(start_time, end_time),
        license_distribution: AdminControllers::ReportsController.calculate_license_distribution,
        order_status_distribution: AdminControllers::ReportsController.calculate_order_status_distribution(
          start_time, end_time
        ),
        monthly_growth: AdminControllers::ReportsController.calculate_monthly_growth_data,
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
          AdminControllers::ReportsController.generate_revenue_csv_report(start_time, end_time)
        when 'licenses'
          AdminControllers::ReportsController.generate_licenses_csv_report(start_time, end_time)
        when 'orders'
          AdminControllers::ReportsController.generate_orders_csv_report(start_time, end_time)
        when 'customers'
          AdminControllers::ReportsController.generate_customers_csv_report(start_time, end_time)
        else
          AdminControllers::ReportsController.generate_summary_csv_report(start_time, end_time)
        end
      when 'json'
        content_type :json
        attachment "#{report_type}_report_#{start_date}_to_#{end_date}.json"

        {
          report_type: report_type,
          date_range: { start: start_date, end: end_date },
          revenue_stats: AdminControllers::ReportsController.calculate_revenue_stats(start_time, end_time),
          license_stats: AdminControllers::ReportsController.calculate_license_stats(start_time, end_time),
          order_stats: AdminControllers::ReportsController.calculate_order_stats(start_time, end_time),
          customer_stats: AdminControllers::ReportsController.calculate_customer_stats(start_time, end_time),
          product_performance: AdminControllers::ReportsController.calculate_product_performance(start_time,
                                                                                                 end_time),
        }.to_json
      else
        halt 400, 'Invalid format'
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
    result.is_a?(Hash) && result.any? ? result : { 'no_data' => 1 }
  end

  # Calculate order status distribution for date range
  def self.calculate_order_status_distribution(start_time, end_time)
    result = Order.where(created_at: start_time..end_time).group(:status).count
    result.is_a?(Hash) && result.any? ? result : { 'no_data' => 1 }
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

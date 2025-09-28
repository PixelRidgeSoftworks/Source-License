# frozen_string_literal: true

# Admin Orders Controller
# Handles order management, including refunds and bulk operations

require_relative '../../payment_processor'
require_relative '../../logging/payment_logger'

module Admin::OrdersController
  def self.setup_routes(app)
    # Orders listing page
    app.get '/admin/orders' do
      require_secure_admin_auth
      @page_title = 'Order Management'

      # Pagination
      @per_page = (params[:per_page] || 50).to_i
      @per_page = 50 if @per_page < 1 || @per_page > 100
      @current_page = (params[:page] || 1).to_i
      @current_page = 1 if @current_page < 1

      # Build base query
      query = Order.dataset

      # Apply filters
      if params[:search] && !params[:search].empty?
        search_term = "%#{params[:search].downcase}%"
        query = query.where(
          Sequel.ilike(:email, search_term) |
          Sequel.ilike(:customer_name, search_term) |
          Sequel.cast(:id, String).ilike(search_term) |
          Sequel.ilike(:payment_intent_id, search_term) |
          Sequel.ilike(:transaction_id, search_term)
        )
      end

      query = query.where(status: params[:status]) if params[:status] && !params[:status].empty?

      if params[:payment_method] && !params[:payment_method].empty?
        query = query.where(payment_method: params[:payment_method])
      end

      if params[:date_filter] && !params[:date_filter].empty?
        case params[:date_filter]
        when 'today'
          query = query.where(created_at: Date.today..(Date.today + 1))
        when 'week'
          start_of_week = Date.today - Date.today.wday
          query = query.where(created_at: start_of_week..(start_of_week + 7))
        when 'month'
          start_of_month = Date.new(Date.today.year, Date.today.month, 1)
          query = query.where(created_at: start_of_month..start_of_month.next_month)
        when 'year'
          start_of_year = Date.new(Date.today.year, 1, 1)
          query = query.where(created_at: start_of_year..start_of_year.next_year)
        end
      end

      # Get total count for pagination
      @total_orders = query.count
      @total_pages = (@total_orders / @per_page.to_f).ceil

      # Apply pagination and ordering
      offset = (@current_page - 1) * @per_page
      @orders = query.order(Sequel.desc(:created_at))
        .limit(@per_page)
        .offset(offset)
        .all

      erb :'admin/orders', layout: :'layouts/admin_layout'
    end

    # Order details page
    app.get '/admin/orders/:id' do
      require_secure_admin_auth
      @order = Order[params[:id]]
      halt 404, 'Order not found' unless @order

      @page_title = "Order ##{@order.id}"
      erb :'admin/orders_show', layout: :'layouts/admin_layout'
    end

    # Update order status
    app.post '/admin/orders/:id/update-status' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'
      content_type :json

      order = Order[params[:id]]
      halt 404, 'Order not found' unless order

      new_status = params[:status]
      unless %w[pending completed failed refunded].include?(new_status)
        return { success: false, error: 'Invalid status' }.to_json
      end

      begin
        DB.transaction do
          case new_status
          when 'completed'
            # Complete the order and generate licenses if needed
            Admin::OrdersController.complete_order(order)
          when 'refunded'
            # Process refund through payment system
            refund_result = Admin::OrdersController.process_order_refund(order, 'Admin refund')
            return { success: false, error: refund_result[:error] }.to_json unless refund_result[:success]
          else
            # Simple status update
            order.update(status: new_status, updated_at: Time.now)
          end

          PaymentLogger.log_payment_event('order_status_updated', {
            order_id: order.id,
            old_status: order.status,
            new_status: new_status,
            updated_by: current_secure_admin.email,
          })
        end

        { success: true, message: "Order status updated to #{new_status}" }.to_json
      rescue StandardError => e
        PaymentLogger.log_security_event('order_status_update_failed', {
          order_id: order.id,
          error: e.message,
          admin_id: current_secure_admin.id,
        })

        { success: false, error: e.message }.to_json
      end
    end

    # Refund order endpoint
    app.post '/admin/orders/:id/refund' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'
      content_type :json

      order = Order[params[:id]]
      halt 404, 'Order not found' unless order

      # Validate refund request
      return { success: false, error: 'Only completed orders can be refunded' }.to_json unless order.completed?

      return { success: false, error: 'Order is already refunded' }.to_json if order.refunded?

      refund_amount = params[:amount]&.to_f || order.amount
      refund_reason = params[:reason] || 'Admin initiated refund'

      # Validate refund amount
      if refund_amount <= 0 || refund_amount > order.amount
        return { success: false, error: 'Invalid refund amount' }.to_json
      end

      begin
        result = Admin::OrdersController.process_order_refund(order, refund_reason, refund_amount)
        result.to_json
      rescue StandardError => e
        PaymentLogger.log_security_event('refund_processing_failed', {
          order_id: order.id,
          error: e.message,
          admin_id: current_secure_admin.id,
        })

        { success: false, error: "Refund failed: #{e.message}" }.to_json
      end
    end

    # Bulk actions endpoint
    app.post '/admin/orders/bulk-action' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'
      content_type :json

      action = params[:action]
      order_ids = params[:order_ids] || []

      return { success: false, error: 'Invalid action' }.to_json unless %w[complete refund delete].include?(action)

      return { success: false, error: 'No orders selected' }.to_json if order_ids.empty?

      results = { success: 0, failed: 0, errors: [] }

      order_ids.each do |order_id|
        order = Order[order_id]
        next unless order

        case action
        when 'complete'
          Admin::OrdersController.complete_order(order) unless order.completed?
          results[:success] += 1
        when 'refund'
          if order.completed? && !order.refunded?
            refund_result = Admin::OrdersController.process_order_refund(order, 'Bulk admin refund')
            if refund_result[:success]
              results[:success] += 1
            else
              results[:failed] += 1
              results[:errors] << "Order ##{order.id}: #{refund_result[:error]}"
            end
          else
            results[:failed] += 1
            results[:errors] << "Order ##{order.id}: Cannot refund (not completed or already refunded)"
          end
        when 'delete'
          if order.pending? || order.failed?
            order.delete
            results[:success] += 1
          else
            results[:failed] += 1
            results[:errors] << "Order ##{order.id}: Cannot delete completed orders"
          end
        end
      rescue StandardError => e
        results[:failed] += 1
        results[:errors] << "Order ##{order_id}: #{e.message}"
      end

      PaymentLogger.log_payment_event('bulk_order_action', {
        action: action,
        total_orders: order_ids.length,
        successful: results[:success],
        failed: results[:failed],
        admin_id: current_secure_admin.id,
      })

      { success: true, results: results }.to_json
    end

    # Export orders
    app.get '/admin/orders/export' do
      require_secure_admin_auth

      # Build query with same filters as listing page
      query = Order.dataset

      if params[:order_ids] && !params[:order_ids].empty?
        # Export specific orders
        order_ids = params[:order_ids].split(',').map(&:to_i)
        query = query.where(id: order_ids)
      else
        # Export with current filters
        if params[:search] && !params[:search].empty?
          search_term = "%#{params[:search].downcase}%"
          query = query.where(
            Sequel.ilike(:email, search_term) |
            Sequel.ilike(:customer_name, search_term) |
            Sequel.cast(:id, String).ilike(search_term)
          )
        end

        query = query.where(status: params[:status]) if params[:status] && !params[:status].empty?

        if params[:payment_method] && !params[:payment_method].empty?
          query = query.where(payment_method: params[:payment_method])
        end
      end

      orders = query.order(Sequel.desc(:created_at)).all

      # Generate CSV
      require 'csv'
      csv_content = CSV.generate do |csv|
        # Headers
        csv << [
          'Order ID', 'Customer Email', 'Customer Name', 'Amount', 'Currency',
          'Status', 'Payment Method', 'Payment Intent ID', 'Transaction ID',
          'Created At', 'Completed At', 'Refunded At', 'Items',
        ]

        # Data rows
        orders.each do |order|
          items = order.order_items.map do |item|
            "#{item.product&.name || 'Unknown'} (×#{item.quantity})"
          end.join('; ')

          csv << [
            order.id,
            order.email,
            order.customer_name,
            order.amount,
            order.currency,
            order.status,
            order.payment_method,
            order.payment_intent_id,
            order.transaction_id,
            order.created_at&.strftime('%Y-%m-%d %H:%M:%S'),
            order.completed_at&.strftime('%Y-%m-%d %H:%M:%S'),
            order.refunded_at&.strftime('%Y-%m-%d %H:%M:%S'),
            items,
          ]
        end
      end

      filename = "orders_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"

      content_type 'text/csv'
      attachment filename
      csv_content
    end
  end

  # Process refund through payment system
  def self.process_order_refund(order, reason, amount = nil)
    amount ||= order.amount

    # Process refund through payment processor
    refund_result = PaymentProcessor.process_refund(order, amount, reason)

    if refund_result[:success]
      DB.transaction do
        # Update order status
        order.update(
          status: 'refunded',
          refunded_at: Time.now,
          updated_at: Time.now
        )

        # Revoke associated licenses
        order.licenses.each do |license|
          license.revoke!
          PaymentLogger.log_license_event(license, 'revoked_admin_refund', {
            order_id: order.id,
            refund_amount: amount,
            admin_id: current_secure_admin.id,
          })

          # Cancel subscriptions if any
          license.subscription&.cancel!
        end
      end

      PaymentLogger.log_payment_event('refund_successful', {
        order_id: order.id,
        refund_amount: amount,
        reason: reason,
        admin_id: current_secure_admin.id,
        transaction_id: refund_result[:refund_id],
      })

      {
        success: true,
        message: 'Refund processed successfully',
        refund_id: refund_result[:refund_id],
        amount: amount,
      }
    else
      PaymentLogger.log_security_event('refund_failed', {
        order_id: order.id,
        error: refund_result[:error],
        admin_id: current_secure_admin.id,
      })

      {
        success: false,
        error: refund_result[:error],
      }
    end
  end

  # Complete an order and generate licenses
  def self.complete_order(order)
    return if order.completed?

    DB.transaction do
      order.update(
        status: 'completed',
        completed_at: Time.now,
        updated_at: Time.now
      )

      # Generate licenses for order items
      order.order_items.each do |item|
        (1..item.quantity).each do
          license = License.create(
            product_id: item.product_id,
            customer_email: order.email,
            customer_name: order.customer_name,
            order_id: order.id,
            license_key: LicenseGenerator.generate_key,
            status: 'active',
            issued_at: Time.now,
            expires_at: Admin::OrdersController.calculate_expiration_date(item.product)
          )

          PaymentLogger.log_license_event(license, 'issued_admin_completion', {
            order_id: order.id,
            admin_id: current_secure_admin.id,
          })
        end
      end
    end
  end

  # Calculate license expiration date
  def self.calculate_expiration_date(product)
    return nil unless product&.license_duration_days

    return unless product.license_duration_days.positive?

    Time.now + (product.license_duration_days * 24 * 60 * 60)
  end
end

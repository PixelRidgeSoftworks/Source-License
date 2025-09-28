# frozen_string_literal: true

# Admin Order Service
# Handles business logic for order operations to avoid duplication between controllers

class Admin::OrderService
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

  # Complete an order and generate licenses (shared logic)
  def self.complete_order(order)
    return if order.completed?

    DB.transaction do
      order.update(
        status: 'completed',
        completed_at: Time.now,
        updated_at: Time.now
      )

      # Generate licenses for order items if using the features controller approach
      # Check if the order already has licenses to avoid duplication
      generate_licenses_for_order(order) if order.licenses.empty?
    end
  end

  # Process bulk order actions with consistent logic
  def self.process_bulk_action(action, order_ids)
    return { success: false, error: 'Invalid action' } unless %w[complete refund delete].include?(action)
    return { success: false, error: 'No orders selected' } if order_ids.nil? || order_ids.empty?

    # Find orders
    orders = Order.where(id: order_ids)
    return { success: false, error: 'Some orders not found' } if orders.count != order_ids.length

    results = { success: 0, failed: 0, errors: [] }

    DB.transaction do
      orders.each do |order|
        case action
        when 'complete'
          if order.pending?
            complete_order(order)
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

    { success: true, results: results }
  end

  # Update order status with validation
  def self.update_order_status(order, new_status)
    return { success: false, error: 'Invalid status' } unless %w[pending completed failed
                                                                 refunded].include?(new_status)

    case new_status
    when 'completed'
      complete_order(order)
      generate_licenses_for_order(order) if order.licenses.empty?
    when 'refunded'
      order.update(status: 'refunded', refunded_at: Time.now)
      # Revoke associated licenses
      order.licenses.each(&:revoke!)
    else
      order.update(status: new_status)
    end

    { success: true, status: order.status }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # Generate order export CSV with consistent formatting
  def self.generate_orders_csv(orders)
    csv_data = "Order ID,Customer Email,Customer Name,Amount,Currency,Status,Payment Method,Created At,Completed At,Items\n"
    orders.each do |order|
      items = order.order_items.map { |item| "#{item.product&.name} (#{item.quantity}x)" }.join('; ')
      csv_data += "#{order.id},\"#{order.email}\",\"#{order.customer_name || ''}\",#{order.amount},#{order.currency},#{order.status},#{order.payment_method},#{order.created_at},#{order.completed_at || ''},\"#{items}\"\n"
    end
    csv_data
  end

  # Apply standard filters to order query
  def self.apply_order_filters(query, params)
    # Status filter
    query = query.where(status: params[:status]) if params[:status] && !params[:status].empty?

    # Payment method filter
    if params[:payment_method] && !params[:payment_method].empty?
      query = query.where(payment_method: params[:payment_method])
    end

    # Search filter
    if params[:search] && !params[:search].empty?
      search_term = "%#{params[:search]}%"
      query = query.where(
        Sequel.|(
          Sequel.ilike(:email, search_term),
          Sequel.ilike(:customer_name, search_term),
          Sequel.like(:id, search_term)
        )
      )
    end

    # Date filter
    if params[:date_filter] && !params[:date_filter].empty?
      case params[:date_filter]
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

    query
  end
end

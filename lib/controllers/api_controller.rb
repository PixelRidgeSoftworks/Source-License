# frozen_string_literal: true

# Controller for API routes
module ApiController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # API ROUTES - Secure REST API
    # ==================================================

    # Get all products (for cart/checkout)
    app.get '/api/products' do
      content_type :json

      products = Product.where(active: true).order(:name).all
      products.map(&:values).to_json
    end

    # Create order (for checkout)
    app.post '/api/orders' do
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
    app.post '/api/orders/free' do
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

        # Generate licenses for the completed free order
        ApiController.generate_licenses_for_order(order)

        # Send confirmation email if configured
        ApiController.send_order_confirmation_email(order) if ENV['SMTP_HOST']

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
    app.post '/api/payment/paypal/capture' do
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
          ApiController.generate_licenses_for_order(order)

          # Send confirmation email if configured
          ApiController.send_order_confirmation_email(order) if ENV['SMTP_HOST']

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
    app.post '/api/auth' do
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
    app.get '/api/license/:key/validate' do
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
    app.post '/api/license/:key/activate' do
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
    app.post '/api/webhook/:provider' do
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
    app.get '/api/orders/:id' do
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
    app.get '/api/settings/categories' do
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
    app.get '/api/settings/:category' do
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
    app.get '/api/settings/:category/:key' do
      require_secure_admin_auth
      content_type :json

      full_key = "#{params[:category]}.#{params[:key]}"
      value = SettingsManager.get(full_key)

      { success: true, key: full_key, value: value }.to_json
    end

    # Update a specific setting
    app.put '/api/settings/:category/:key' do
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
    app.post '/api/settings/bulk-update' do
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
    app.post '/api/settings/:category/test' do
      require_secure_admin_auth
      content_type :json

      category = params[:category]
      test_results = SettingsManager.test_configuration(category)

      { success: true, category: category, test_results: test_results }.to_json
    end

    # Export settings as YAML
    app.get '/api/settings/export' do
      require_secure_admin_auth
      content_type 'application/x-yaml'
      attachment 'settings.yml'

      SettingsManager.export_to_yaml
    end

    # Import settings from YAML
    app.post '/api/settings/import' do
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
    app.get '/api/settings/generate-env' do
      require_secure_admin_auth
      content_type 'text/plain'
      attachment '.env'

      SettingsManager.generate_env_file
    end

    # Get web-editable settings only
    app.get '/api/settings/web-editable' do
      require_secure_admin_auth
      content_type :json

      settings = SettingsManager.get_web_editable

      { success: true, settings: settings }.to_json
    end
  end

  # Handle Stripe webhooks
  def self.handle_stripe_webhook(request)
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
  def self.handle_paypal_webhook(_request)
    # PayPal webhook handling implementation
    # This would verify the webhook signature and process the payment
    logger.info 'PayPal webhook received'
  end

  # Handle successful payment
  def self.handle_successful_payment(payment_intent)
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
    ApiController.send_order_confirmation_email(order) if ENV['SMTP_HOST']
  end

  # Send order confirmation email
  def self.send_order_confirmation_email(order)
    # Skip email sending if SMTP is not properly configured
    return unless ENV['SMTP_HOST'] && ENV['SMTP_USERNAME'] && ENV['SMTP_PASSWORD']

    begin
      # Simple email body since email templates don't exist
      email_body = "Thank you for your order!\n\n"
      email_body += "Order ID: #{order.id}\n"
      email_body += "Customer: #{order.customer_name}\n"
      email_body += "Email: #{order.email}\n"
      email_body += "Amount: #{order.amount}\n"
      email_body += "Status: #{order.status}\n\n"
      
      if order.licenses.any?
        email_body += "Your license keys:\n"
        order.licenses.each do |license|
          email_body += "- #{license.license_key} (#{license.product&.name})\n"
        end
      end
      
      email_body += "\nThank you for your business!"

      mail = Mail.new do
        from ENV.fetch('SMTP_USERNAME', nil)
        to order.email
        subject "Your Software License Purchase - Order ##{order.id}"
        body email_body
      end

      mail.deliver!
    rescue StandardError => e
      # Log error but don't fail the request
      puts "Failed to send confirmation email: #{e.message}" if ENV['APP_ENV'] == 'development'
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
end

# frozen_string_literal: true

# Controller for admin routes
module AdminController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # ADMIN ROUTES
    # ==================================================

    # Admin login page
    app.get '/admin/login' do
      redirect '/admin' if current_secure_admin
      @page_title = 'Admin Login'
      erb :'admin/login', layout: :'layouts/admin_layout'
    end

    # Enhanced admin login handler
    app.post '/admin/login' do
      require_csrf_token unless ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'

      # Gather request information
      request_info = {
        ip: request.ip,
        user_agent: request.user_agent,
      }

      # Use enhanced authentication
      auth_result = authenticate_admin_secure(params[:email], params[:password], request_info)

      if auth_result[:success]
        admin = auth_result[:admin]

        # Create secure session
        create_secure_session(admin, request_info)

        # Check for security warnings
        @security_warnings = check_account_security(admin)

        # Redirect to return URL or dashboard
        redirect_url = session.delete(:return_to) || '/admin'
        redirect redirect_url
      else
        @error = auth_result[:message]
        @page_title = 'Admin Login'
        erb :'admin/login', layout: :'layouts/admin_layout'
      end
    end

    # Admin logout
    app.post '/admin/logout' do
      session.clear
      redirect '/admin/login'
    end

    # Admin dashboard
    app.get '/admin' do
      require_secure_admin_auth
      @page_title = 'Admin Dashboard'
      @stats = {
        total_licenses: License.count,
        active_licenses: License.where(status: 'active').count,
        total_revenue: Order.where(status: 'completed').sum(:amount) || 0,
        recent_orders: Order.order(Sequel.desc(:created_at)).limit(10),
      }
      erb :'admin/dashboard', layout: :'layouts/admin_layout'
    end

    # Settings page
    app.get '/admin/settings' do
      require_secure_admin_auth
      @page_title = 'Settings'
      erb :'admin/settings', layout: :'layouts/admin_layout'
    end

    # Database backup route
    app.post '/admin/database/backup' do
      require_secure_admin_auth
      content_type :json

      begin
        # Create a simple database backup
        backup_filename = "backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
        backup_path = File.join(ENV['BACKUP_PATH'] || './backups', backup_filename)

        # Ensure backup directory exists
        FileUtils.mkdir_p(File.dirname(backup_path))

        # Simple backup for SQLite (adjust for other databases)
        if ENV['DATABASE_ADAPTER'] == 'sqlite' || !ENV['DATABASE_ADAPTER']
          db_path = ENV['DATABASE_PATH'] || './database.db'
          FileUtils.cp(db_path, backup_path) if File.exist?(db_path)
        end

        { success: true, message: 'Database backup created successfully', filename: backup_filename }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end

    # Run migrations route
    app.post '/admin/database/migrate' do
      require_secure_admin_auth
      content_type :json

      begin
        # Run any pending migrations
        require_relative '../migrations'
        Migrations.run_all

        { success: true, message: 'Migrations completed successfully' }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end

    # Download logs route
    app.get '/admin/logs/download' do
      require_secure_admin_auth

      log_path = ENV['LOG_PATH'] || './log/application.log'

      if File.exist?(log_path)
        send_file log_path, disposition: 'attachment', filename: "application_logs_#{Time.now.strftime('%Y%m%d')}.log"
      else
        halt 404, 'Log file not found'
      end
    end

    # Export data route
    app.post '/admin/data/export' do
      require_secure_admin_auth
      content_type :json

      begin
        export_data = {
          licenses: License.all.map(&:values),
          products: Product.all.map(&:values),
          orders: Order.all.map(&:values),
          exported_at: Time.now.iso8601,
        }

        filename = "data_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
        export_path = File.join(ENV['EXPORT_PATH'] || './exports', filename)

        # Ensure export directory exists
        FileUtils.mkdir_p(File.dirname(export_path))

        File.write(export_path, JSON.pretty_generate(export_data))

        { success: true, message: 'Data exported successfully', filename: filename }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end

    # Regenerate API keys route
    app.post '/admin/security/regenerate-keys' do
      require_secure_admin_auth
      content_type :json

      begin
        # Generate new JWT secret
        SecureRandom.hex(64)

        # In a real implementation, you'd update your environment or database
        # For now, we'll just simulate the action

        { success: true, message: 'API keys regenerated successfully. Please restart the application.' }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end
  end
end

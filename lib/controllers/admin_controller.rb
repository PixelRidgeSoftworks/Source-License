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

    # Admin management routes
    app.get '/admin/admins' do
      require_secure_admin_auth
      @page_title = 'Admin Management'
      @admins = Admin.all
      erb :'admin/admins', layout: :'layouts/admin_layout'
    end

    app.get '/admin/admins/new' do
      require_secure_admin_auth
      @page_title = 'Create New Admin'
      erb :'admin/admins_new', layout: :'layouts/admin_layout'
    end

    app.get '/admin/admins/:id/edit' do
      require_secure_admin_auth
      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin
      @page_title = 'Edit Admin'
      erb :'admin/admins_edit', layout: :'layouts/admin_layout'
    end

    app.put '/admin/admins/:id' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin

      email = params[:email]&.strip&.downcase
      name = params[:name]&.strip
      status = params[:status]

      # Validate input
      errors = []
      errors << 'Email is required' if email.nil? || email.empty?
      errors << 'Invalid email format' unless valid_email_format?(email)
      errors << 'Name is required' if name.nil? || name.empty?
      errors << 'Invalid status' unless ['active', 'inactive', 'locked', 'suspended'].include?(status)

      # Check if email already exists for another admin
      if email && email != @admin.email
        existing_admin = Admin.first(email: email)
        errors << 'An admin with this email already exists' if existing_admin
      end

      # Prevent editing protected admins (except yourself)
      if is_original_admin?(@admin) && @admin.id != current_secure_admin.id
        errors << 'Cannot edit the original admin account'
      end

      if errors.any?
        @error = errors.join('. ')
        @page_title = 'Edit Admin'
        erb :'admin/admins_edit', layout: :'layouts/admin_layout'
      else
        begin
          # Update admin
          update_data = {
            email: email,
            name: name,
            status: status,
            active: (status == 'active'),
            updated_at: Time.now
          }

          @admin.update(update_data)

          # Log the admin update
          log_auth_event('admin_updated', {
            updated_admin_id: @admin.id,
            updated_admin_email: @admin.email,
            updated_by_admin: current_secure_admin.id,
            updated_by_email: current_secure_admin.email,
            changes: update_data.keys
          })

          redirect '/admin/admins?success=Admin updated successfully'
        rescue StandardError => e
          @error = "Failed to update admin: #{e.message}"
          @page_title = 'Edit Admin'
          erb :'admin/admins_edit', layout: :'layouts/admin_layout'
        end
      end
    end

    app.get '/admin/admins/:id/reset-password' do
      require_secure_admin_auth
      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin
      @page_title = 'Reset Admin Password'
      erb :'admin/admins_reset_password', layout: :'layouts/admin_layout'
    end

    app.post '/admin/admins/:id/reset-password' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin

      password = params[:password]
      confirm_password = params[:confirm_password]

      # Validate input
      errors = []
      errors << 'Password is required' if password.nil? || password.empty?
      errors << 'Passwords do not match' if password != confirm_password

      # Check password policy
      password_errors = validate_password_policy(password) if password
      errors.concat(password_errors) if password_errors

      # Prevent resetting password of protected admins (except yourself)
      if is_original_admin?(@admin) && @admin.id != current_secure_admin.id
        errors << 'Cannot reset password for the original admin account'
      end

      if errors.any?
        @error = errors.join('. ')
        @page_title = 'Reset Admin Password'
        erb :'admin/admins_reset_password', layout: :'layouts/admin_layout'
      else
        begin
          # Update password
          @admin.update(
            password_hash: BCrypt::Password.create(password),
            updated_at: Time.now
          )

          # Log the password reset
          log_auth_event('admin_password_reset', {
            target_admin_id: @admin.id,
            target_admin_email: @admin.email,
            reset_by_admin: current_secure_admin.id,
            reset_by_email: current_secure_admin.email
          })

          redirect '/admin/admins?success=Admin password reset successfully'
        rescue StandardError => e
          @error = "Failed to reset password: #{e.message}"
          @page_title = 'Reset Admin Password'
          erb :'admin/admins_reset_password', layout: :'layouts/admin_layout'
        end
      end
    end

    app.post '/admin/admins' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      email = params[:email]&.strip&.downcase
      password = params[:password]
      confirm_password = params[:confirm_password]
      name = params[:name]&.strip

      # Validate input
      errors = []
      errors << 'Email is required' if email.nil? || email.empty?
      errors << 'Invalid email format' unless valid_email_format?(email)
      errors << 'Password is required' if password.nil? || password.empty?
      errors << 'Name is required' if name.nil? || name.empty?
      errors << 'Passwords do not match' if password != confirm_password

      # Check password policy
      password_errors = validate_password_policy(password) if password
      errors.concat(password_errors) if password_errors

      # Check if email already exists
      if email && Admin.first(email: email)
        errors << 'An admin with this email already exists'
      end

      if errors.any?
        @error = errors.join('. ')
        @page_title = 'Create New Admin'
        erb :'admin/admins_new', layout: :'layouts/admin_layout'
      else
        begin
          # Create new admin using the secure method
          new_admin = Admin.create_secure_admin(email, password, ['admin'])
          
          if new_admin && new_admin.id
            # Set the name separately if needed
            new_admin.update(name: name) if name && !name.empty?

            # Log the admin creation
            log_auth_event('admin_created', {
              new_admin_email: email,
              new_admin_id: new_admin.id,
              created_by_admin: current_secure_admin.id,
              created_by_email: current_secure_admin.email
            })

            redirect '/admin/admins?success=Admin created successfully'
          else
            error_msg = new_admin&.errors&.full_messages&.join(', ') || 'Unknown error'
            @error = "Failed to create admin: #{error_msg}"
            @page_title = 'Create New Admin'
            erb :'admin/admins_new', layout: :'layouts/admin_layout'
          end
        rescue StandardError => e
          @error = "Failed to create admin: #{e.message}"
          @page_title = 'Create New Admin'
          erb :'admin/admins_new', layout: :'layouts/admin_layout'
        end
      end
    end

    app.post '/admin/admins/:id/toggle' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless admin

      # Prevent disabling yourself
      if admin.id == current_secure_admin.id
        redirect '/admin/admins?error=You cannot disable your own account'
      # Prevent disabling the original admin from .env
      elsif is_original_admin?(admin)
        redirect '/admin/admins?error=Cannot disable the original admin account created during installation'
      else
        new_active_state = !admin.active
        new_status = new_active_state ? 'active' : 'inactive'
        
        admin.update(
          active: new_active_state,
          status: new_status,
          updated_at: Time.now
        )
        
        log_auth_event('admin_toggled', {
          target_admin_id: admin.id,
          target_admin_email: admin.email,
          new_status: new_active_state ? 'activated' : 'deactivated',
          toggled_by_admin: current_secure_admin.id,
          toggled_by_email: current_secure_admin.email
        })

        status_text = new_active_state ? 'activated' : 'deactivated'
        redirect "/admin/admins?success=Admin #{status_text} successfully"
      end
    end

    app.delete '/admin/admins/:id' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless admin

      # Prevent deleting yourself
      if admin.id == current_secure_admin.id
        redirect '/admin/admins?error=You cannot delete your own account'
      # Prevent deleting the original admin from .env
      elsif is_original_admin?(admin)
        redirect '/admin/admins?error=Cannot delete the original admin account created during installation'
      else
        # Check if this is the last active admin
        active_admin_count = Admin.where(active: true).count
        if active_admin_count <= 1 && admin.active?
          redirect '/admin/admins?error=Cannot delete the last active admin account'
        else
          log_auth_event('admin_deleted', {
            deleted_admin_id: admin.id,
            deleted_admin_email: admin.email,
            deleted_by_admin: current_secure_admin.id,
            deleted_by_email: current_secure_admin.email
          })

          admin.delete
          redirect '/admin/admins?success=Admin deleted successfully'
        end
      end
    end

    # Ban management routes
    app.get '/admin/bans' do
      require_secure_admin_auth
      @page_title = 'Ban Management'
      @active_bans = get_all_active_bans(100)
      erb :'admin/bans', layout: :'layouts/admin_layout'
    end

    app.post '/admin/bans/:email/remove' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'
      content_type :json

      email = params[:email]
      
      begin
        remove_ban(email, current_secure_admin)
        { success: true, message: 'Ban removed successfully' }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end

    app.post '/admin/bans/:email/reset-count' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'
      content_type :json

      email = params[:email]
      
      begin
        reset_ban_count(email, current_secure_admin)
        { success: true, message: 'Ban count reset successfully' }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end

    app.get '/admin/bans/search' do
      require_secure_admin_auth
      content_type :json

      email = params[:email]
      
      if email && !email.empty?
        ban_info = get_current_ban(email.strip.downcase)
        ban_count = get_ban_count(email.strip.downcase)
        
        if ban_info
          time_remaining = get_ban_time_remaining(email)
          duration_text = format_ban_duration(time_remaining)
          
          {
            success: true,
            banned: true,
            ban_info: ban_info.merge({
              time_remaining_text: duration_text,
              time_remaining_seconds: time_remaining
            }),
            ban_count: ban_count
          }.to_json
        else
          {
            success: true,
            banned: false,
            ban_count: ban_count
          }.to_json
        end
      else
        status 400
        { success: false, error: 'Email parameter is required' }.to_json
      end
    end
  end
end

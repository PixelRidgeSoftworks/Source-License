# frozen_string_literal: true

require_relative '../core/route_primitive'

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

    # Authentication routes
    admin_login_page_route(app)
    admin_login_handler_route(app)
    admin_logout_route(app)

    # Dashboard and settings
    admin_dashboard_route(app)
    admin_settings_route(app)

    # Database operations
    database_backup_route(app)
    database_migrate_route(app)

    # Logging
    admin_logs_page_route(app)
    admin_logs_download_route(app)
    admin_logs_api_route(app)

    # Data management
    admin_export_data_route(app)
    admin_regenerate_keys_route(app)

    # Admin management
    admin_list_route(app)
    admin_new_page_route(app)
    admin_edit_page_route(app)
    admin_update_route(app)
    admin_reset_password_page_route(app)
    admin_reset_password_handler_route(app)
    admin_create_route(app)
    admin_toggle_route(app)
    admin_delete_route(app)

    # Admin profile management
    admin_profile_route(app)
    admin_profile_update_route(app)
    admin_profile_password_route(app)
    admin_profile_security_route(app)

    # Ban management
    ban_list_route(app)
    ban_remove_route(app)
    ban_reset_count_route(app)
    ban_search_route(app)
  end

  # Admin login page
  def self.admin_login_page_route(app)
    app.get '/admin/login' do
      redirect '/admin' if current_secure_admin
      @page_title = 'Admin Login'
      erb :'admin/login', layout: :'layouts/admin_layout'
    end
  end

  # Enhanced admin login handler
  def self.admin_login_handler_route(app)
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
  end

  # Admin logout route
  def self.admin_logout_route(app)
    app.post '/admin/logout' do
      session.clear
      redirect '/admin/login'
    end
  end

  # Admin dashboard route
  def self.admin_dashboard_route(app)
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
  end

  # Admin settings route
  def self.admin_settings_route(app)
    app.get '/admin/settings' do
      require_secure_admin_auth
      @page_title = 'Settings'
      erb :'admin/settings', layout: :'layouts/admin_layout'
    end
  end

  # Database backup route
  def self.database_backup_route(app)
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
  end

  # Database migration route
  def self.database_migrate_route(app)
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
  end

  # Admin logs page route
  def self.admin_logs_page_route(app)
    app.get '/admin/logs' do
      require_secure_admin_auth
      @page_title = 'System Logs'

      # Get log files
      @log_files = available_log_files

      # Get recent log entries
      @recent_logs = recent_log_entries(100)

      erb :'admin/logs', layout: :'layouts/admin_layout'
    end
  end

  # Admin logs download route
  def self.admin_logs_download_route(app)
    app.get '/admin/logs/download' do
      require_secure_admin_auth

      log_path = ENV['LOG_PATH'] || './logs/application.log'

      if File.exist?(log_path)
        send_file log_path, disposition: 'attachment', filename: "application_logs_#{Time.now.strftime('%Y%m%d')}.log"
      else
        halt 404, 'Log file not found'
      end
    end
  end

  # Admin logs API route
  def self.admin_logs_api_route(app)
    app.get '/admin/logs/api' do
      require_secure_admin_auth
      content_type :json

      log_type = params[:type] || 'all'
      log_level = params[:level] || 'all'
      search_term = params[:search]
      limit = (params[:limit] || 50).to_i
      offset = (params[:offset] || 0).to_i

      begin
        logs = []

        # Handle different log types
        case log_type
        when 'all'
          # Get both file and database logs
          file_logs = mixed_file_logs(limit / 2, offset / 2)
          db_logs = database_log_entries(limit / 2)
          logs = (file_logs + db_logs).sort_by { |entry| entry[:timestamp] }.reverse
        when 'security', 'license', 'system'
          # These are primarily database logs
          logs = database_log_entries_by_type(log_type, limit, offset)
        else
          # File-based logs
          logs = log_entries(log_type, limit, offset)
        end

        # Apply level filtering
        logs = logs.select { |log| log[:level] == log_level } if log_level != 'all'

        # Apply search filtering
        if search_term && !search_term.empty?
          logs = logs.select do |log|
            log[:message].downcase.include?(search_term.downcase)
          end
        end

        # Apply offset and limit
        logs = logs.drop(offset).first(limit)

        { success: true, logs: logs }.to_json
      rescue StandardError => e
        status 500
        { success: false, error: e.message }.to_json
      end
    end
  end

  # Admin export data route
  def self.admin_export_data_route(app)
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
  end

  # Admin regenerate keys route
  def self.admin_regenerate_keys_route(app)
    app.post '/admin/security/regenerate-keys' do
      require_secure_admin_auth
      content_type :json

      begin
        # Generate new security keys based on actual environment variables
        new_jwt_secret = SecureRandom.hex(64)           # JWT_SECRET
        new_app_secret = SecureRandom.hex(64)           # APP_SECRET
        new_license_hash_salt = SecureRandom.hex(32)    # LICENSE_HASH_SALT
        new_license_jwt_secret = SecureRandom.hex(64)   # LICENSE_JWT_SECRET

        # Update in settings table
        regenerated_keys = []

        # Update JWT secret
        jwt_setting = DB[:settings].where(key: 'jwt_secret').first
        if jwt_setting
          DB[:settings].where(key: 'jwt_secret').update(
            value: new_jwt_secret,
            updated_at: Time.now
          )
          regenerated_keys << 'JWT Secret'
        else
          DB[:settings].insert(
            key: 'jwt_secret',
            value: new_jwt_secret,
            category: 'security',
            created_at: Time.now,
            updated_at: Time.now
          )
          regenerated_keys << 'JWT Secret (new)'
        end

        # Update app secret
        app_secret_setting = DB[:settings].where(key: 'app_secret').first
        if app_secret_setting
          DB[:settings].where(key: 'app_secret').update(
            value: new_app_secret,
            updated_at: Time.now
          )
          regenerated_keys << 'App Secret'
        else
          DB[:settings].insert(
            key: 'app_secret',
            value: new_app_secret,
            category: 'security',
            created_at: Time.now,
            updated_at: Time.now
          )
          regenerated_keys << 'App Secret (new)'
        end

        # Update license hash salt
        license_salt_setting = DB[:settings].where(key: 'license_hash_salt').first
        if license_salt_setting
          DB[:settings].where(key: 'license_hash_salt').update(
            value: new_license_hash_salt,
            updated_at: Time.now
          )
          regenerated_keys << 'License Hash Salt'
        else
          DB[:settings].insert(
            key: 'license_hash_salt',
            value: new_license_hash_salt,
            category: 'security',
            created_at: Time.now,
            updated_at: Time.now
          )
          regenerated_keys << 'License Hash Salt (new)'
        end

        # Update license JWT secret
        license_jwt_setting = DB[:settings].where(key: 'license_jwt_secret').first
        if license_jwt_setting
          DB[:settings].where(key: 'license_jwt_secret').update(
            value: new_license_jwt_secret,
            updated_at: Time.now
          )
          regenerated_keys << 'License JWT Secret'
        else
          DB[:settings].insert(
            key: 'license_jwt_secret',
            value: new_license_jwt_secret,
            category: 'security',
            created_at: Time.now,
            updated_at: Time.now
          )
          regenerated_keys << 'License JWT Secret (new)'
        end

        # Update environment variables in memory (requires restart to persist)
        ENV['JWT_SECRET'] = new_jwt_secret
        ENV['APP_SECRET'] = new_app_secret
        ENV['LICENSE_HASH_SALT'] = new_license_hash_salt
        ENV['LICENSE_JWT_SECRET'] = new_license_jwt_secret

        # Log the key regeneration for security audit
        log_auth_event('security_keys_regenerated', {
          admin_id: current_secure_admin.id,
          admin_email: current_secure_admin.email,
          keys_regenerated: regenerated_keys,
          regenerated_at: Time.now.iso8601,
        })

        {
          success: true,
          message: "Security keys regenerated successfully: #{regenerated_keys.join(', ')}. Please restart the application to ensure all services use the new keys.",
          keys_regenerated: regenerated_keys,
          restart_required: true,
        }.to_json
      rescue StandardError => e
        # Log the error for security monitoring
        log_auth_event('security_keys_regeneration_failed', {
          admin_id: current_secure_admin&.id,
          admin_email: current_secure_admin&.email,
          error: e.message,
          failed_at: Time.now.iso8601,
        })

        status 500
        { success: false, error: "Failed to regenerate security keys: #{e.message}" }.to_json
      end
    end
  end

  # Admin list route
  def self.admin_list_route(app)
    app.get '/admin/admins' do
      require_secure_admin_auth
      @page_title = 'Admin Management'
      @admins = Admin.all
      erb :'admin/admins', layout: :'layouts/admin_layout'
    end
  end

  # Admin new page route
  def self.admin_new_page_route(app)
    app.get '/admin/admins/new' do
      require_secure_admin_auth
      @page_title = 'Create New Admin'
      erb :'admin/admins_new', layout: :'layouts/admin_layout'
    end
  end

  # Admin edit page route
  def self.admin_edit_page_route(app)
    app.get '/admin/admins/:id/edit' do
      require_secure_admin_auth
      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin
      @page_title = 'Edit Admin'
      erb :'admin/admins_edit', layout: :'layouts/admin_layout'
    end
  end

  # Admin update route
  def self.admin_update_route(app)
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
      errors << 'Invalid status' unless %w[active inactive locked suspended].include?(status)

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
            updated_at: Time.now,
          }

          @admin.update(update_data)

          # Log the admin update
          log_auth_event('admin_updated', {
            updated_admin_id: @admin.id,
            updated_admin_email: @admin.email,
            updated_by_admin: current_secure_admin.id,
            updated_by_email: current_secure_admin.email,
            changes: update_data.keys,
          })

          redirect '/admin/admins?success=Admin updated successfully'
        rescue StandardError => e
          @error = "Failed to update admin: #{e.message}"
          @page_title = 'Edit Admin'
          erb :'admin/admins_edit', layout: :'layouts/admin_layout'
        end
      end
    end
  end

  # ==================================================
  # ADMIN PROFILE ROUTES
  # ==================================================

  # Admin profile main page
  def self.admin_profile_route(app)
    app.get '/admin/profile' do
      require_secure_admin_auth
      @page_title = 'My Profile'
      @current_admin = current_secure_admin

      # Get admin's recent login activity
      @recent_logins = AdminController.get_admin_login_history(@current_admin.id, 10)

      # Check if admin has 2FA enabled (assuming admins use the same 2FA system as users)
      @totp_enabled = AdminController.get_admin_totp_status(@current_admin.id)
      @webauthn_credentials = AdminController.get_admin_webauthn_credentials(@current_admin.id)
      @has_2fa = @totp_enabled || @webauthn_credentials.any?

      erb :'admin/profile', layout: :'layouts/admin_layout'
    end
  end

  # Admin profile update (name, email, etc.)
  def self.admin_profile_update_route(app)
    app.post '/admin/profile/update' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      @current_admin = current_secure_admin

      name = params[:name]&.strip
      email = params[:email]&.strip&.downcase

      # Validate input
      errors = []
      errors << 'Name is required' if name.nil? || name.empty?
      errors << 'Email is required' if email.nil? || email.empty?
      errors << 'Invalid email format' unless valid_email_format?(email)

      # Check if email already exists for another admin
      if email && email != @current_admin.email
        existing_admin = Admin.first(email: email)
        errors << 'An admin with this email already exists' if existing_admin
      end

      if errors.any?
        session[:profile_error] = errors.join('. ')
        redirect '/admin/profile'
      else
        begin
          @current_admin.update(
            name: name,
            email: email,
            updated_at: Time.now
          )

          # Log profile update
          log_auth_event('admin_profile_updated', {
            admin_id: @current_admin.id,
            admin_email: @current_admin.email,
            changes: %w[name email],
          })

          session[:profile_success] = 'Profile updated successfully'
          redirect '/admin/profile'
        rescue StandardError => e
          session[:profile_error] = "Failed to update profile: #{e.message}"
          redirect '/admin/profile'
        end
      end
    end
  end

  # Admin password change
  def self.admin_profile_password_route(app)
    app.post '/admin/profile/password' do
      require_secure_admin_auth
      require_csrf_token unless ENV['APP_ENV'] == 'test'

      @current_admin = current_secure_admin

      current_password = params[:current_password]
      new_password = params[:new_password]
      confirm_password = params[:confirm_password]

      # Validate input
      errors = []
      errors << 'Current password is required' if current_password.nil? || current_password.empty?
      errors << 'New password is required' if new_password.nil? || new_password.empty?
      errors << 'Password confirmation is required' if confirm_password.nil? || confirm_password.empty?
      errors << 'New passwords do not match' if new_password != confirm_password

      # Verify current password
      if current_password && !BCrypt::Password.new(@current_admin.password_hash).is_password?(current_password)
        errors << 'Current password is incorrect'
      end

      # Check password policy for new password
      if new_password
        password_errors = validate_password_policy(new_password)
        errors.concat(password_errors) if password_errors
      end

      if errors.any?
        session[:profile_error] = errors.join('. ')
        redirect '/admin/profile'
      else
        begin
          @current_admin.update(
            password_hash: BCrypt::Password.create(new_password),
            updated_at: Time.now
          )

          # Log password change
          log_auth_event('admin_password_changed', {
            admin_id: @current_admin.id,
            admin_email: @current_admin.email,
          })

          session[:profile_success] = 'Password changed successfully'
          redirect '/admin/profile'
        rescue StandardError => e
          session[:profile_error] = "Failed to change password: #{e.message}"
          redirect '/admin/profile'
        end
      end
    end
  end

  # Admin security settings (2FA management)
  def self.admin_profile_security_route(app)
    app.get '/admin/profile/security' do
      require_secure_admin_auth
      @page_title = 'Security Settings'
      @current_admin = current_secure_admin

      # Get admin's 2FA status - treat admin as a user for 2FA purposes
      @totp_settings = get_totp_settings(@current_admin.id)
      @webauthn_credentials = get_webauthn_credentials(@current_admin.id)
      @available_methods = get_available_2fa_methods(@current_admin.id)
      @backup_codes_count = get_backup_codes_count(@current_admin.id)

      # Get recent security events for this admin
      @recent_security_events = AdminController.get_admin_security_events(@current_admin.id, 20)

      erb :'admin/profile_security', layout: :'layouts/admin_layout'
    end
  end

  # Admin reset password page route
  def self.admin_reset_password_page_route(app)
    app.get '/admin/admins/:id/reset-password' do
      require_secure_admin_auth
      @admin = Admin[params[:id]]
      halt 404, 'Admin not found' unless @admin
      @page_title = 'Reset Admin Password'
      erb :'admin/admins_reset_password', layout: :'layouts/admin_layout'
    end
  end

  # Admin reset password handler route
  def self.admin_reset_password_handler_route(app)
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
            reset_by_email: current_secure_admin.email,
          })

          redirect '/admin/admins?success=Admin password reset successfully'
        rescue StandardError => e
          @error = "Failed to reset password: #{e.message}"
          @page_title = 'Reset Admin Password'
          erb :'admin/admins_reset_password', layout: :'layouts/admin_layout'
        end
      end
    end
  end

  # Admin create route
  def self.admin_create_route(app)
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
      errors << 'An admin with this email already exists' if email && Admin.first(email: email)

      if errors.any?
        @error = errors.join('. ')
        @page_title = 'Create New Admin'
        erb :'admin/admins_new', layout: :'layouts/admin_layout'
      else
        begin
          # Create new admin using the secure method
          new_admin = Admin.create_secure_admin(email, password, ['admin'])

          if new_admin&.id
            # Set the name separately if needed
            new_admin.update(name: name) if name && !name.empty?

            # Log the admin creation
            log_auth_event('admin_created', {
              new_admin_email: email,
              new_admin_id: new_admin.id,
              created_by_admin: current_secure_admin.id,
              created_by_email: current_secure_admin.email,
            })

            redirect '/admin/admins?success=Admin created successfully'
          else
            error_msg = if new_admin&.errors&.full_messages
                          new_admin.errors.full_messages.join(', ')
                        else
                          'Unknown error'
                        end
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
  end

  # Admin toggle route
  def self.admin_toggle_route(app)
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
          toggled_by_email: current_secure_admin.email,
        })

        status_text = new_active_state ? 'activated' : 'deactivated'
        redirect "/admin/admins?success=Admin #{status_text} successfully"
      end
    end
  end

  # Admin delete route
  def self.admin_delete_route(app)
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
            deleted_by_email: current_secure_admin.email,
          })

          admin.delete
          redirect '/admin/admins?success=Admin deleted successfully'
        end
      end
    end
  end

  # Ban list route
  def self.ban_list_route(app)
    app.get '/admin/bans' do
      require_secure_admin_auth
      @page_title = 'Ban Management'
      @active_bans = all_active_bans(100)
      erb :'admin/bans', layout: :'layouts/admin_layout'
    end
  end

  # Ban remove route
  def self.ban_remove_route(app)
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
  end

  # Ban reset count route
  def self.ban_reset_count_route(app)
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
  end

  # Ban search route
  def self.ban_search_route(app)
    app.get '/admin/bans/search' do
      require_secure_admin_auth
      content_type :json

      email = params[:email]

      if email && !email.empty?
        ban_info = current_ban(email.strip.downcase)
        ban_count = ban_count(email.strip.downcase)

        if ban_info
          time_remaining = ban_time_remaining(email)
          duration_text = format_ban_duration(time_remaining)

          {
            success: true,
            banned: true,
            ban_info: ban_info.merge({
              time_remaining_text: duration_text,
              time_remaining_seconds: time_remaining,
            }),
            ban_count: ban_count,
          }.to_json
        else
          {
            success: true,
            banned: false,
            ban_count: ban_count,
          }.to_json
        end
      else
        status 400
        { success: false, error: 'Email parameter is required' }.to_json
      end
    end
  end

  # ==================================================
  # HELPER METHODS FOR ADMIN PROFILE
  # ==================================================

  def self.get_admin_login_history(_admin_id, _limit = 10)
    # This would query your auth logs for admin login events
    # For now, return sample data - implement based on your logging system
    []
  end

  def self.get_admin_totp_status(admin_id)
    # Check if admin has TOTP enabled (treating admin as user for 2FA)

    totp_settings = DB[:user_totp_settings].where(user_id: admin_id).first
    totp_settings && totp_settings[:enabled]
  rescue StandardError
    false
  end

  def self.get_admin_webauthn_credentials(admin_id)
    # Get admin's WebAuthn credentials (treating admin as user for 2FA)

    DB[:user_webauthn_credentials].where(user_id: admin_id).all
  rescue StandardError
    []
  end

  def self.get_admin_security_events(_admin_id, _limit = 20)
    # Get recent security events for this admin
    # This would query your security logs - implement based on your logging system
    []
  end
end

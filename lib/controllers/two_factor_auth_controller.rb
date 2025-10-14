# frozen_string_literal: true

require_relative 'route_primitive'

# Controller for two-factor authentication management
module TwoFactorAuthController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  # Simple Admin struct for template compatibility
  Admin = Struct.new(:id, :email, :username, :name, :created_at, :last_login_at, keyword_init: true)

  def self.setup_routes(app)
    # ==================================================
    # TWO-FACTOR AUTHENTICATION ROUTES
    # ==================================================

    # Set up authentication filter first
    setup_authentication_filter(app)

    # User 2FA routes
    user_2fa_index_route(app)
    user_2fa_totp_setup_route(app)
    user_2fa_totp_enable_route(app)
    user_2fa_totp_disable_route(app)
    user_2fa_webauthn_register_route(app)
    user_2fa_webauthn_begin_route(app)
    user_2fa_webauthn_complete_route(app)
    user_2fa_webauthn_delete_route(app)
    user_2fa_backup_codes_route(app)
    user_2fa_backup_codes_regenerate_route(app)

    # 2FA verification routes (for login flow)
    user_2fa_verify_route(app)
    user_2fa_verify_totp_route(app)
    user_2fa_verify_backup_route(app)
    user_2fa_verify_webauthn_route(app)

    # Admin 2FA management routes
    admin_2fa_settings_route(app)
    admin_2fa_personal_route(app)
    admin_2fa_totp_setup_route(app)
    admin_2fa_totp_enable_route(app)
    admin_2fa_totp_disable_route(app)
    admin_2fa_webauthn_register_route(app)
    admin_2fa_webauthn_begin_route(app)
    admin_2fa_webauthn_complete_route(app)
    admin_2fa_webauthn_delete_route(app)
    admin_2fa_backup_codes_route(app)
    admin_2fa_backup_codes_regenerate_route(app)
    admin_2fa_stats_route(app)
    admin_2fa_settings_get_route(app)
    admin_2fa_settings_save_route(app)
    admin_2fa_webauthn_settings_route(app)
    admin_2fa_users_route(app)
    admin_2fa_events_route(app)
    admin_2fa_user_require_route(app)
    admin_2fa_user_remove_requirement_route(app)
    admin_2fa_user_reset_route(app)
  end

  # Authentication filter - will be implemented as before filter in main app
  def self.setup_authentication_filter(app)
    app.before '/2fa' do
      next if request.path_info.start_with?('/2fa/verify')
      next if request.path_info.start_with?('/admin/2fa') # Skip for admin routes

      # Check for either user or admin authentication
      if user_logged_in?
        # Regular user authentication - current_user helper will be available from BaseController
        # No need to set @current_user, the helper method will provide the User object
      elsif session[:admin_session].is_a?(Hash) && session[:admin_session][:admin_id]
        # Admin is trying to access user 2FA routes - redirect to admin routes
        admin_path = request.path_info.gsub('/2fa', '/admin/2fa')

        # Handle special cases for admin routing
        case request.path_info
        when '/2fa'
          redirect '/admin/2fa/personal'
        when '/2fa/totp/setup'
          redirect '/admin/2fa/totp/setup'
        when '/2fa/webauthn/register'
          redirect '/admin/2fa/webauthn/register'
        when '/2fa/backup-codes'
          redirect '/admin/2fa/backup-codes'
        else
          redirect admin_path
        end
      else
        halt 401, 'Authentication required'
      end
    end
  end

  # User 2FA Routes
  def self.user_2fa_index_route(app)
    app.get '/2fa' do
      @totp_settings = get_totp_settings(current_user.id)
      @webauthn_credentials = get_webauthn_credentials(current_user.id)
      @available_methods = get_available_2fa_methods(current_user.id)
      @backup_codes_count = get_backup_codes_count(current_user.id)

      erb :'users/2fa/index', layout: :'layouts/main_layout'
    end
  end

  def self.user_2fa_totp_setup_route(app)
    app.get '/2fa/totp/setup' do
      user_id = current_user.id
      user_email = current_user.email

      halt 400, 'Invalid user session' unless user_id && user_email

      # Check if TOTP is already enabled
      totp_settings = get_totp_settings(user_id)
      halt 400, 'TOTP already enabled' if totp_settings && totp_settings[:enabled]

      @secret = generate_totp_secret(user_id)
      @qr_code = generate_totp_qr_code(user_email, @secret)

      erb :'users/2fa/totp_setup', layout: :'layouts/main_layout'
    end
  end

  def self.user_2fa_totp_enable_route(app)
    app.post '/2fa/totp/enable' do
      token = params[:token]&.strip&.gsub(/\s/, '')

      halt 400, 'Invalid token format' unless token&.match?(/^\d{6}$/)

      backup_codes = enable_totp(current_user.id, token)

      if backup_codes
        session[:backup_codes] = backup_codes # Show once, then clear
        redirect '/2fa/backup-codes'
      else
        @error = 'Invalid verification code. Please try again.'
        @secret = get_totp_settings(current_user.id)[:secret]
        @qr_code = generate_totp_qr_code(current_user.email, @secret)
        erb :'users/2fa/totp_setup', layout: :'layouts/main_layout'
      end
    end
  end

  def self.user_2fa_totp_disable_route(app)
    app.post '/2fa/totp/disable' do
      # Require current password for security
      current_password = params[:current_password]
      halt 400, 'Current password required' unless current_password

      unless current_user.password_matches?(current_password)
        @error = 'Invalid password'
        redirect '/2fa'
      end

      disable_totp(current_user.id)
      redirect '/2fa?message=TOTP disabled successfully'
    end
  end

  def self.user_2fa_webauthn_register_route(app)
    app.get '/2fa/webauthn/register' do
      @credentials = get_webauthn_credentials(current_user.id)
      erb :'users/2fa/webauthn_register', layout: :'layouts/main_layout'
    end
  end

  def self.user_2fa_webauthn_begin_route(app)
    app.post '/2fa/webauthn/register/begin' do
      content_type :json

      options = begin_webauthn_registration(current_user.id, current_user.email)

      if options
        options.to_json
      else
        status 400
        { error: 'Failed to initiate registration' }.to_json
      end
    end
  end

  def self.user_2fa_webauthn_complete_route(app)
    app.post '/2fa/webauthn/register/complete' do
      content_type :json

      credential_params = JSON.parse(request.body.read)
      nickname = params[:nickname] || 'Security Key'

      result = complete_webauthn_registration(credential_params, nickname)

      status 400 unless result[:success]
      result.to_json
    end
  end

  def self.user_2fa_webauthn_delete_route(app)
    app.delete '/2fa/webauthn/credentials/:id' do
      credential_id = params[:id].to_i

      if delete_webauthn_credential(current_user.id, credential_id)
        redirect '/2fa?message=Security key removed successfully'
      else
        redirect '/2fa?error=Failed to remove security key'
      end
    end
  end

  def self.user_2fa_backup_codes_route(app)
    app.get '/2fa/backup-codes' do
      @backup_codes = session[:backup_codes]
      session.delete(:backup_codes) # Show only once

      halt 404, 'No backup codes to display' unless @backup_codes

      erb :'users/2fa/backup_codes', layout: :'layouts/main_layout'
    end
  end

  def self.user_2fa_backup_codes_regenerate_route(app)
    app.post '/2fa/backup-codes/regenerate' do
      # Require current password for security
      current_password = params[:current_password]
      halt 400, 'Current password required' unless current_password

      unless current_user.password_matches?(current_password)
        @error = 'Invalid password'
        redirect '/2fa'
      end

      new_codes = regenerate_backup_codes(current_user.id)
      session[:backup_codes] = new_codes
      redirect '/2fa/backup-codes'
    end
  end

  # 2FA Verification Routes (for login flow)
  def self.user_2fa_verify_route(app)
    app.get '/2fa/verify' do
      # Check if user is in 2FA verification state
      halt 400, 'Invalid 2FA session' unless session[:pending_2fa_user_id]

      @user_id = session[:pending_2fa_user_id]
      @available_methods = get_available_2fa_methods(@user_id)
      @preferred_method = get_preferred_2fa_method(@user_id)
      @backup_codes_count = get_backup_codes_count(@user_id)

      # If user has WebAuthn, prepare authentication options
      @webauthn_options = begin_webauthn_authentication(@user_id) if @available_methods.include?('webauthn')

      erb :'users/2fa/verify'
    end
  end

  def self.user_2fa_verify_totp_route(app)
    app.post '/2fa/verify/totp' do
      content_type :json

      user_id = session[:pending_2fa_user_id]
      halt 400, { error: 'Invalid session' }.to_json unless user_id

      token = params[:token]&.strip&.gsub(/\s/, '')
      halt 400, { error: 'Invalid token format' }.to_json unless token&.match?(/^\d{6}$/)

      if verify_totp_token(user_id, token)
        # Complete login
        complete_2fa_login(user_id, session)

        { success: true, redirect: '/dashboard' }.to_json
      else
        { error: 'Invalid verification code' }.to_json
      end
    end
  end

  def self.user_2fa_verify_backup_route(app)
    app.post '/2fa/verify/backup' do
      content_type :json

      user_id = session[:pending_2fa_user_id]
      halt 400, { error: 'Invalid session' }.to_json unless user_id

      code = params[:code]&.strip&.downcase
      halt 400, { error: 'Invalid code format' }.to_json unless code&.match?(/^[a-z0-9]{8}$/)

      if verify_backup_code(user_id, code)
        # Complete login
        complete_2fa_login(user_id, session)

        remaining_codes = get_backup_codes_count(user_id)
        warning = if remaining_codes <= 2
                    'Warning: You have few backup codes remaining. ' \
                      'Consider generating new ones.'
                  end

        { success: true, redirect: '/dashboard', warning: warning }.to_json
      else
        { error: 'Invalid backup code' }.to_json
      end
    end
  end

  def self.user_2fa_verify_webauthn_route(app)
    app.post '/2fa/verify/webauthn' do
      content_type :json

      user_id = session[:pending_2fa_user_id]
      halt 400, { error: 'Invalid session' }.to_json unless user_id

      credential_params = JSON.parse(request.body.read)

      if complete_webauthn_authentication(credential_params)
        # Complete login
        complete_2fa_login(user_id, session)

        { success: true, redirect: '/dashboard' }.to_json
      else
        { error: 'Authentication failed' }.to_json
      end
    end
  end

  # Admin Routes for 2FA Management
  def self.admin_2fa_settings_route(app)
    app.get '/admin/2fa' do
      unless session[:admin_session]
        session[:return_to] = request.fullpath
        redirect '/admin/login'
      end
      erb :'admin/2fa_settings', layout: :'layouts/admin_layout'
    end
  end

  def self.admin_2fa_personal_route(app)
    app.get '/admin/2fa/personal' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      @current_admin = admin
      @totp_settings = get_totp_settings(admin_id)
      @webauthn_credentials = get_webauthn_credentials(admin_id)
      @available_methods = get_available_2fa_methods(admin_id)
      @backup_codes_count = get_backup_codes_count(admin_id)

      erb :'admin/2fa/index', layout: :'layouts/admin_layout'
    end
  end

  def self.admin_2fa_totp_setup_route(app)
    app.get '/admin/2fa/totp/setup' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      # Check if TOTP is already enabled
      totp_settings = get_totp_settings(admin_id)
      halt 400, 'TOTP already enabled' if totp_settings && totp_settings[:enabled]

      @current_admin = admin
      @secret = generate_totp_secret(admin_id)
      @qr_code = generate_totp_qr_code(admin[:email], @secret)

      erb :'admin/2fa/totp_setup', layout: :'layouts/admin_layout'
    end
  end

  def self.admin_2fa_totp_enable_route(app)
    app.post '/admin/2fa/totp/enable' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      token = params[:token]&.strip&.gsub(/\s/, '')
      halt 400, 'Invalid token format' unless token&.match?(/^\d{6}$/)

      backup_codes = enable_totp(admin_id, token)

      if backup_codes
        session[:backup_codes] = backup_codes # Show once, then clear
        redirect '/admin/2fa/backup-codes'
      else
        @error = 'Invalid verification code. Please try again.'
        @secret = get_totp_settings(admin_id)[:secret]
        @qr_code = generate_totp_qr_code(admin[:email], @secret)
        erb :'admin/2fa/totp_setup', layout: :'layouts/admin_layout'
      end
    end
  end

  def self.admin_2fa_totp_disable_route(app)
    app.post '/admin/2fa/totp/disable' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      # Require current password for security
      current_password = params[:current_password]
      halt 400, 'Current password required' unless current_password

      unless BCrypt::Password.new(admin[:password_hash]) == current_password
        @error = 'Invalid password'
        redirect '/admin/2fa/personal'
      end

      disable_totp(admin_id)
      redirect '/admin/2fa/personal?message=TOTP disabled successfully'
    end
  end

  def self.admin_2fa_webauthn_register_route(app)
    app.get '/admin/2fa/webauthn/register' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]

      @credentials = get_webauthn_credentials(admin_id)
      erb :'admin/2fa/webauthn_register', layout: :'layouts/admin_layout'
    end
  end

  def self.admin_2fa_webauthn_begin_route(app)
    app.post '/admin/2fa/webauthn/register/begin' do
      halt 401, 'Admin authentication required' unless session[:admin_session]
      content_type :json

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      options = begin_webauthn_registration(admin_id, admin[:email])

      if options
        options.to_json
      else
        status 400
        { error: 'Failed to initiate registration' }.to_json
      end
    end
  end

  def self.admin_2fa_webauthn_complete_route(app)
    app.post '/admin/2fa/webauthn/register/complete' do
      halt 401, 'Admin authentication required' unless session[:admin_session]
      content_type :json

      credential_params = JSON.parse(request.body.read)
      nickname = params[:nickname] || 'Security Key'

      result = complete_webauthn_registration(credential_params, nickname)

      status 400 unless result[:success]
      result.to_json
    end
  end

  def self.admin_2fa_webauthn_delete_route(app)
    app.delete '/admin/2fa/webauthn/credentials/:id' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      credential_id = params[:id].to_i

      if delete_webauthn_credential(admin_id, credential_id)
        redirect '/admin/2fa/personal?message=Security key removed successfully'
      else
        redirect '/admin/2fa/personal?error=Failed to remove security key'
      end
    end
  end

  def self.admin_2fa_backup_codes_route(app)
    app.get '/admin/2fa/backup-codes' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      @backup_codes = session[:backup_codes]
      session.delete(:backup_codes) # Show only once

      halt 404, 'No backup codes to display' unless @backup_codes

      erb :'admin/2fa/backup_codes', layout: :'layouts/admin_layout'
    end
  end

  def self.admin_2fa_backup_codes_regenerate_route(app)
    app.post '/admin/2fa/backup-codes/regenerate' do
      halt 401, 'Admin authentication required' unless session[:admin_session]

      admin_session = session[:admin_session]
      admin_id = admin_session[:admin_id]
      admin = DB[:admins].where(id: admin_id).first
      halt 404, 'Admin not found' unless admin

      # Require current password for security
      current_password = params[:current_password]
      halt 400, 'Current password required' unless current_password

      unless BCrypt::Password.new(admin[:password_hash]) == current_password
        @error = 'Invalid password'
        redirect '/admin/2fa/personal'
      end

      new_codes = regenerate_backup_codes(admin_id)
      session[:backup_codes] = new_codes
      redirect '/admin/2fa/backup-codes'
    end
  end

  # Admin API Routes
  def self.admin_2fa_stats_route(app)
    app.get '/admin/2fa/stats' do
      unless session[:admin_session]
        status 403
        return { error: 'Admin access required' }.to_json
      end
      content_type :json

      stats = {
        total_users: DB[:users].count,
        users_2fa_enabled: DB[:users].where(two_factor_enabled: true).count,
        totp_users: DB[:user_totp_settings].where(enabled: true).count,
        webauthn_users: DB[:user_webauthn_credentials].select(:user_id).distinct.count,
      }

      { success: true, stats: stats }.to_json
    end
  end

  def self.admin_2fa_settings_get_route(app)
    app.get '/admin/2fa/settings' do
      halt 403, 'Admin access required' unless session[:admin_session]
      content_type :json

      settings = {
        enforce_all_users: SettingsManager.get('security.2fa.enforce_all_users', false),
        enforce_new_users: SettingsManager.get('security.2fa.enforce_new_users', false),
        enforce_admins: SettingsManager.get('security.2fa.enforce_admins', false),
        grace_period_days: SettingsManager.get('security.2fa.grace_period_days', 7),
        allow_totp: SettingsManager.get('security.2fa.allow_totp', true),
        allow_webauthn: SettingsManager.get('security.2fa.allow_webauthn', true),
        allow_backup_codes: SettingsManager.get('security.2fa.allow_backup_codes', true),
        backup_code_count: SettingsManager.get('security.2fa.backup_code_count', 10),
        totp_issuer: SettingsManager.get('security.2fa.totp_issuer', 'Source-License'),
        webauthn_rp_name: SettingsManager.get('security.webauthn.rp_name', 'Source-License'),
        webauthn_timeout: SettingsManager.get('security.webauthn.timeout', 60),
        webauthn_user_verification: SettingsManager.get('security.webauthn.user_verification', 'preferred'),
        webauthn_attestation: SettingsManager.get('security.webauthn.attestation', 'none'),
      }

      { success: true, settings: settings }.to_json
    end
  end

  def self.admin_2fa_settings_save_route(app)
    app.post '/admin/2fa/settings' do
      halt 403, 'Admin access required' unless session[:admin_session]
      content_type :json

      begin
        request_data = JSON.parse(request.body.read)

        # Save each setting using the SettingsManager
        settings_to_save = {
          'security.2fa.enforce_all_users' => request_data['enforce_all_users'],
          'security.2fa.enforce_new_users' => request_data['enforce_new_users'],
          'security.2fa.enforce_admins' => request_data['enforce_admins'],
          'security.2fa.grace_period_days' => request_data['grace_period_days'],
          'security.2fa.allow_totp' => request_data['allow_totp'],
          'security.2fa.allow_webauthn' => request_data['allow_webauthn'],
          'security.2fa.allow_backup_codes' => request_data['allow_backup_codes'],
          'security.2fa.backup_code_count' => request_data['backup_code_count'],
          'security.2fa.totp_issuer' => request_data['totp_issuer'],
        }

        settings_to_save.each do |key, value|
          SettingsManager.set(key, value) unless value.nil?
        end

        admin_session = session[:admin_session]
        log_auth_event('admin_update_2fa_settings', {
          admin_id: admin_session ? admin_session[:admin_id] : nil,
          settings: request_data,
        })

        { success: true, message: '2FA settings saved successfully' }.to_json
      rescue JSON::ParserError
        status 400
        { success: false, error: 'Invalid JSON data' }.to_json
      rescue StandardError
        status 500
        { success: false, error: 'Failed to save settings' }.to_json
      end
    end
  end

  def self.admin_2fa_webauthn_settings_route(app)
    app.post '/admin/2fa/webauthn-settings' do
      halt 403, 'Admin access required' unless session[:admin_session]
      content_type :json

      begin
        request_data = JSON.parse(request.body.read)

        # Save WebAuthn settings using the SettingsManager
        settings_to_save = {
          'security.webauthn.rp_name' => request_data['webauthn_rp_name'],
          'security.webauthn.timeout' => request_data['webauthn_timeout'],
          'security.webauthn.user_verification' => request_data['webauthn_user_verification'],
          'security.webauthn.attestation' => request_data['webauthn_attestation'],
        }

        settings_to_save.each do |key, value|
          SettingsManager.set(key, value) unless value.nil?
        end

        admin_session = session[:admin_session]
        log_auth_event('admin_update_webauthn_settings', {
          admin_id: admin_session ? admin_session[:admin_id] : nil,
          settings: request_data,
        })

        { success: true, message: 'WebAuthn settings saved successfully' }.to_json
      rescue JSON::ParserError
        status 400
        { success: false, error: 'Invalid JSON data' }.to_json
      rescue StandardError
        status 500
        { success: false, error: 'Failed to save WebAuthn settings' }.to_json
      end
    end
  end

  def self.admin_2fa_users_route(app)
    app.get '/admin/2fa/users' do
      halt 403, 'Admin access required' unless session[:admin_session]
      content_type :json

      page = (params[:page] || 1).to_i
      per_page = [(params[:per_page] || 10).to_i, 50].min
      search = params[:search]

      query = DB[:users].select(
        :id, :email, :name, :require_2fa, :two_factor_enabled,
        :preferred_2fa_method, :last_login_at, :created_at
      )

      if search && !search.empty?
        query = query.where(Sequel.ilike(:email, "%#{search}%") | Sequel.ilike(:name, "%#{search}%"))
      end

      total = query.count
      users = query.limit(per_page).offset((page - 1) * per_page).all

      # Add 2FA method info
      users.each do |user|
        totp = DB[:user_totp_settings].where(user_id: user[:id]).first
        user[:totp_enabled] = totp&.[](:enabled) || false

        user[:webauthn_count] = DB[:user_webauthn_credentials].where(user_id: user[:id]).count
        user[:backup_codes_count] = get_backup_codes_count(user[:id])
      end

      pagination = {
        page: page,
        per_page: per_page,
        total: total,
        pages: (total.to_f / per_page).ceil,
      }

      { success: true, users: users, pagination: pagination }.to_json
    end
  end

  def self.admin_2fa_events_route(app)
    app.get '/admin/2fa/events' do
      halt 403, 'Admin access required' unless session[:admin_session]
      content_type :json

      [(params[:limit] || 10).to_i, 100].min

      # This would come from a security events table in a real implementation
      events = []

      { success: true, events: events }.to_json
    end
  end

  def self.admin_2fa_user_require_route(app)
    app.post '/admin/users/:id/require-2fa' do
      halt 403, 'Admin access required' unless session[:admin_session]

      user_id = params[:id].to_i
      DB[:users].where(id: user_id).update(require_2fa: true)

      admin_session = session[:admin_session]
      log_auth_event('admin_force_2fa_requirement', {
        admin_id: admin_session ? admin_session[:admin_id] : nil,
        target_user_id: user_id,
      })

      redirect "/admin/users/#{user_id}?message=2FA requirement enabled"
    end
  end

  def self.admin_2fa_user_remove_requirement_route(app)
    app.post '/admin/users/:id/remove-2fa-requirement' do
      halt 403, 'Admin access required' unless session[:admin_session]

      user_id = params[:id].to_i
      DB[:users].where(id: user_id).update(require_2fa: false)

      admin_session = session[:admin_session]
      log_auth_event('admin_remove_2fa_requirement', {
        admin_id: admin_session ? admin_session[:admin_id] : nil,
        target_user_id: user_id,
      })

      redirect "/admin/users/#{user_id}?message=2FA requirement removed"
    end
  end

  def self.admin_2fa_user_reset_route(app)
    app.post '/admin/users/:id/reset-2fa' do
      halt 403, 'Admin access required' unless session[:admin_session]

      user_id = params[:id].to_i

      DB.transaction do
        # Disable TOTP
        DB[:user_totp_settings].where(user_id: user_id).update(enabled: false)

        # Remove all WebAuthn credentials
        DB[:user_webauthn_credentials].where(user_id: user_id).delete

        # Update user 2FA status
        DB[:users].where(id: user_id).update(
          two_factor_enabled: false,
          preferred_2fa_method: nil
        )
      end

      admin_session = session[:admin_session]
      log_auth_event('admin_reset_user_2fa', {
        admin_id: admin_session ? admin_session[:admin_id] : nil,
        target_user_id: user_id,
      })

      redirect "/admin/users/#{user_id}?message=User 2FA reset successfully"
    end
  end

  # Helper Methods
  def self.complete_2fa_login(user_id, session_obj)
    # Complete the login process after successful 2FA
    user = DB[:users].where(id: user_id).first

    # Create user session (from user auth controller)
    session_obj[:user_id] = user_id
    session_obj[:user_email] = user[:email]
    session_obj[:logged_in_at] = Time.now

    # Handle license transfer if pending
    if session_obj[:pending_licenses_transfer]
      session_obj.delete(:pending_licenses_transfer)
      # This would call transfer_licenses_to_user method - simplified for now
      # transferred_count = transfer_licenses_to_user(user, email)
    end

    # Clear 2FA session data
    session_obj.delete(:pending_2fa_user_id)

    # Store return URL if it exists
    session_obj.delete(:return_to)
  end

  # Helper method to provide access to current admin for admin layout template
  def self.current_admin_helper(admin_hash)
    return nil unless admin_hash

    Admin.new(admin_hash)
  end
end

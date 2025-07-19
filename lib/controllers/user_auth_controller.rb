# frozen_string_literal: true

# Controller for user authentication and user area routes
module UserAuthController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # ==================================================
    # USER AUTHENTICATION ROUTES
    # ==================================================

    # User login page
    app.get '/login' do
      redirect '/dashboard' if user_logged_in?
      @page_title = 'Login'
      erb :'users/login', layout: :'layouts/main_layout'
    end

    # User login handler
    app.post '/login' do
      result = authenticate_user(params[:email], params[:password])

      if result[:success]
        user = result[:user]
        create_user_session(user)

        # Transfer any licenses from email to user account
        transferred_count = transfer_licenses_to_user(user, params[:email])

        if transferred_count.positive?
          flash :info, "#{transferred_count} existing license(s) have been transferred to your account."
        end

        # Redirect to dashboard or return URL
        redirect_url = session.delete(:return_to) || '/dashboard'
        redirect redirect_url
      else
        @error = result[:error]
        @page_title = 'Login'
        erb :'users/login', layout: :'layouts/main_layout'
      end
    end

    # User registration page
    app.get '/register' do
      redirect '/dashboard' if user_logged_in?
      @page_title = 'Create Account'
      erb :'users/register', layout: :'layouts/main_layout'
    end

    # User registration handler
    app.post '/register' do
      result = register_user(params[:email], params[:password], params[:name])

      if result[:success]
        user = result[:user]

        # Transfer any existing licenses to the new account
        transferred_count = transfer_licenses_to_user(user, params[:email])

        # Create user session
        create_user_session(user)

        success_message = 'Account created successfully!'
        if transferred_count.positive?
          success_message += " #{transferred_count} existing license(s) have been transferred to your account."
        end

        flash :success, success_message
        redirect '/dashboard'
      else
        @error = result[:error]
        @page_title = 'Create Account'
        erb :'users/register', layout: :'layouts/main_layout'
      end
    end

    # User logout
    app.post '/logout' do
      clear_user_session
      flash :success, 'You have been logged out successfully.'
      redirect '/'
    end

    # User dashboard (secure)
    app.get '/dashboard' do
      require_user_auth
      @user = current_user
      @licenses = get_user_licenses(@user)
      @page_title = 'My Dashboard'
      erb :'users/dashboard', layout: :'layouts/main_layout'
    end

    # Secure license management (replaces the old insecure lookup)
    app.get '/licenses' do
      require_user_auth
      @user = current_user
      @licenses = get_user_licenses(@user)
      @page_title = 'My Licenses'
      erb :'users/licenses', layout: :'layouts/main_layout'
    end

    # Secure license details
    app.get '/licenses/:id' do
      require_user_auth
      license = License[params[:id]]
      halt 404 unless license
      halt 403 unless user_owns_license?(current_user, license)

      @license = license
      @page_title = "License: #{@license.product.name}"
      erb :'users/license_details', layout: :'layouts/main_layout'
    end

    # Secure download (requires authentication)
    app.get '/secure-download/:license_id/:file' do
      require_user_auth
      license = License[params[:license_id]]
      halt 404 unless license
      halt 403 unless user_owns_license?(current_user, license)
      halt 404 unless license.valid?

      file_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads',
                            license.product.download_file)
      halt 404 unless File.exist?(file_path)

      # Log the download
      license.update(download_count: license.download_count + 1,
                     last_downloaded_at: Time.now)

      send_file file_path, disposition: 'attachment'
    end

    # User profile page
    app.get '/profile' do
      require_user_auth
      @user = current_user
      @page_title = 'My Profile'
      erb :'users/profile', layout: :'layouts/main_layout'
    end

    # Update user profile
    app.post '/profile' do
      require_user_auth
      user = current_user

      # Update basic info
      user.name = params[:name]&.strip if params[:name]

      # Handle password change if provided
      if params[:current_password] && params[:new_password]
        if user.password_matches?(params[:current_password])
          if params[:new_password].length >= 8
            user.password = params[:new_password]
            flash :success, 'Profile and password updated successfully!'
          else
            flash :error, 'New password must be at least 8 characters long.'
            @user = user
            return erb :'users/profile', layout: :'layouts/main_layout'
          end
        else
          flash :error, 'Current password is incorrect.'
          @user = user
          return erb :'users/profile', layout: :'layouts/main_layout'
        end
      else
        flash :success, 'Profile updated successfully!'
      end

      user.save_changes
      redirect '/profile'
    end

    # Password reset request page
    app.get '/forgot-password' do
      redirect '/dashboard' if user_logged_in?
      @page_title = 'Forgot Password'
      erb :'users/forgot_password', layout: :'layouts/main_layout'
    end

    # Password reset request handler
    app.post '/forgot-password' do
      result = generate_password_reset_token(params[:email])

      if result
        # Send reset email (if SMTP is configured)
        if ENV['SMTP_HOST']
          send_password_reset_email(result[:user], result[:token])
          flash :success, 'Password reset instructions have been sent to your email.'
        else
          flash :info, "Reset token: #{result[:token]} (SMTP not configured - this would be emailed)"
        end
      else
        flash :success, 'If an account with that email exists, password reset instructions have been sent.'
      end

      redirect '/login'
    end

    # Password reset form
    app.get '/reset-password/:token' do
      @user = verify_password_reset_token(params[:token])
      halt 404 unless @user

      @token = params[:token]
      @page_title = 'Reset Password'
      erb :'users/reset_password', layout: :'layouts/main_layout'
    end

    # Password reset handler
    app.post '/reset-password/:token' do
      result = reset_password_with_token(params[:token], params[:password])

      if result[:success]
        flash :success, 'Your password has been reset successfully. Please log in.'
        redirect '/login'
      else
        @error = result[:error]
        @user = verify_password_reset_token(params[:token])
        halt 404 unless @user
        @token = params[:token]
        @page_title = 'Reset Password'
        erb :'users/reset_password', layout: :'layouts/main_layout'
      end
    end
  end

  private

  # Send password reset email
  def send_password_reset_email(user, token)
    reset_url = "#{request.scheme}://#{request.host_with_port}/reset-password/#{token}"

    mail = Mail.new do
      from ENV.fetch('SMTP_USERNAME', nil)
      to user.email
      subject 'Password Reset Instructions'
      body "Click here to reset your password: #{reset_url}\n\nThis link will expire in 1 hour."

      mail.deliver!
    end
  rescue StandardError => e
    logger.error "Failed to send password reset email: #{e.message}"
  end
end

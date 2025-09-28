# frozen_string_literal: true

# Source-License: Legacy Authentication Module
# Maintains backward compatibility with existing authentication methods

module Auth::LegacyAuth
  include BaseAuth

  #
  # BASIC AUTHENTICATION METHODS (Legacy compatibility)
  #

  # Check if admin is logged in via session
  def admin_logged_in?
    session[:admin_logged_in] == true
  end

  # Get current admin email from session
  def current_admin_email
    session[:admin_email]
  end

  # Get current admin object (legacy method)
  def current_admin
    return nil unless admin_logged_in?

    @current_admin ||= Admin.first(email: current_admin_email)
  end

  # Require admin authentication for protected routes (basic version)
  def require_admin_auth
    return if admin_logged_in?

    if request.xhr? || content_type == 'application/json'
      halt 401, { error: 'Authentication required' }.to_json
    else
      session[:return_to] = request.fullpath
      redirect '/admin/login'
    end
  end

  # Basic admin authentication (legacy method)
  def authenticate_admin(email, password)
    return false unless email && password

    admin = Admin.first(email: email.strip.downcase)
    return false unless admin&.active
    return false unless admin.password_matches?(password)

    # Update last login timestamp
    admin.update_last_login!

    true
  end
end

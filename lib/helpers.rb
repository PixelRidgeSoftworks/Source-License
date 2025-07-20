# frozen_string_literal: true

# Source-License: Helper Functions
# Provides template helpers for the Sinatra application

require 'uri'
require 'cgi'
require 'json'
require 'securerandom'

# Template helper functions
module TemplateHelpers
  # HTML escape text
  def h(text)
    CGI.escapeHTML(text.to_s)
  end

  # URL encode text
  def u(text)
    URI.encode_www_form_component(text.to_s)
  end

  # Truncate text with ellipsis
  def truncate(text, length = 100, suffix = '...')
    return text if text.length <= length

    text[0..(length - 1)] + suffix
  end

  # Time ago in words
  def time_ago(time)
    return 'Unknown' unless time

    diff = Time.now - time

    case diff
    when 0..59
      'Just now'
    when 60..3599
      "#{(diff / 60).to_i} minutes ago"
    when 3600..86_399
      "#{(diff / 3600).to_i} hours ago"
    when 86_400..2_591_999
      "#{(diff / 86_400).to_i} days ago"
    else
      time.strftime('%B %d, %Y')
    end
  end

  # Format currency
  def format_currency(amount, currency = 'USD')
    return '$0.00' unless amount

    formatted = format('%.2f', amount.to_f)

    case currency.upcase
    when 'USD'
      "$#{formatted}"
    when 'EUR'
      "€#{formatted}"
    when 'GBP'
      "£#{formatted}"
    else
      "#{currency.upcase} #{formatted}"
    end
  end

  # Format date
  def format_date(date, format = :short)
    return 'Unknown' unless date

    case format
    when :short
      date.strftime('%m/%d/%Y')
    when :long
      date.strftime('%B %d, %Y')
    when :datetime
      date.strftime('%m/%d/%Y %I:%M %p')
    else
      date.strftime(format.to_s)
    end
  end

  # Generate navigation link with active state
  def nav_link(text, path, options = {})
    css_class = options[:class] || 'nav-link'
    target = options[:target] ? " target=\"#{options[:target]}\"" : ''

    # Check if current path matches
    current_path = request.path
    is_active = (current_path == path) ||
                (path != '/' && current_path.start_with?(path))

    css_class += ' active' if is_active

    "<a href=\"#{path}\" class=\"#{css_class}\"#{target}>#{text}</a>"
  end

  # Generate status badge
  def status_badge(status)
    case status.to_s.downcase
    when 'active', 'completed', 'valid'
      "<span class=\"badge bg-success\">#{status.capitalize}</span>"
    when 'pending', 'processing'
      "<span class=\"badge bg-warning\">#{status.capitalize}</span>"
    when 'inactive', 'cancelled', 'invalid', 'expired'
      "<span class=\"badge bg-danger\">#{status.capitalize}</span>"
    when 'suspended', 'paused'
      "<span class=\"badge bg-secondary\">#{status.capitalize}</span>"
    else
      "<span class=\"badge bg-light text-dark\">#{status.capitalize}</span>"
    end
  end

  # Generate button with custom styling
  def button(text, options = {})
    css_class = options[:class] || 'btn btn-primary'
    type = options[:type] || 'button'
    onclick = options[:onclick] ? " onclick=\"#{options[:onclick]}\"" : ''
    disabled = options[:disabled] ? ' disabled' : ''

    "<button type=\"#{type}\" class=\"#{css_class}\"#{onclick}#{disabled}>#{text}</button>"
  end

  # Generate card component
  def card(title = nil, options = {})
    css_class = "card #{options[:class] || ''}"

    html = "<div class=\"#{css_class}\">"

    html += "<div class=\"card-header\">#{title}</div>" if title

    html += '<div class="card-body">'
    html += yield if block_given?
    html += '</div></div>'

    html
  end

  # Render partial template
  def partial(template_name, locals = {})
    template_path = template_name.start_with?('_') ? template_name : "_#{template_name}"
    erb :"partials/#{template_path}", locals: locals, layout: false
  end

  # Flash messages
  def flash_messages
    return '' unless session[:flash]

    html = ''
    session[:flash].each do |type, message|
      alert_class = case type.to_s
                    when 'success' then 'alert-success'
                    when 'error', 'danger' then 'alert-danger'
                    when 'warning' then 'alert-warning'
                    else 'alert-info'
                    end

      html += "<div class=\"alert #{alert_class} flash-message alert-dismissible fade show\" role=\"alert\">"
      html += h(message).to_s
      html += '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>'
      html += '</div>'
    end

    session.delete(:flash)
    html
  end

  # Set flash message
  def flash(type, message)
    session[:flash] ||= {}
    session[:flash][type.to_sym] = message
  end

  # Check if development environment
  def development?
    ENV['APP_ENV'] == 'development' || ENV['RACK_ENV'] == 'development'
  end

  # Check if production environment
  def production?
    ENV['APP_ENV'] == 'production' || ENV['RACK_ENV'] == 'production'
  end

  # Check if Stripe is enabled
  def stripe_enabled?
    !!(ENV.fetch('STRIPE_SECRET_KEY', nil) && ENV.fetch('STRIPE_PUBLISHABLE_KEY', nil))
  end

  # Check if PayPal is enabled
  def paypal_enabled?
    !!(ENV.fetch('PAYPAL_CLIENT_ID', nil) && ENV.fetch('PAYPAL_CLIENT_SECRET', nil))
  end

  # Convert Ruby object to JSON for JavaScript
  def json_for_js(obj)
    JSON.generate(obj).gsub('</', '<\/')
  end

  # Generate CSRF token
  def csrf_token
    session[:csrf_token] ||= SecureRandom.hex(32)
  end

  # Time ago helper for admin views
  def time_ago_in_words(time)
    return 'never' unless time
    
    seconds_ago = Time.now - time
    
    case seconds_ago
    when 0..59
      'less than a minute'
    when 60..3599
      minutes = (seconds_ago / 60).round
      "#{minutes} minute#{'s' if minutes != 1}"
    when 3600..86399
      hours = (seconds_ago / 3600).round
      "#{hours} hour#{'s' if hours != 1}"
    when 86400..2591999
      days = (seconds_ago / 86400).round
      "#{days} day#{'s' if days != 1}"
    when 2592000..31535999
      months = (seconds_ago / 2592000).round
      "#{months} month#{'s' if months != 1}"
    else
      years = (seconds_ago / 31536000).round
      "#{years} year#{'s' if years != 1}"
    end
  end

  # Generate CSRF input field
  def csrf_input
    "<input type=\"hidden\" name=\"csrf_token\" value=\"#{csrf_token}\">"
  end

  # Verify CSRF token
  def verify_csrf_token
    return true if request.get? || request.head? || request.options?

    # Skip CSRF in development or test environments
    if ENV['APP_ENV'] == 'development' || ENV['RACK_ENV'] == 'development' ||
       ENV['APP_ENV'] == 'test' || ENV['RACK_ENV'] == 'test' ||
       development?
      return true
    end

    submitted_token = params[:csrf_token] || request.env['HTTP_X_CSRF_TOKEN']
    return false unless submitted_token

    # Use secure comparison to prevent timing attacks
    submitted_token == csrf_token
  end

  # Require CSRF token
  def require_csrf_token
    return if verify_csrf_token

    if request.xhr? || content_type == 'application/json'
      halt 403, { error: 'CSRF token verification failed' }.to_json
    else
      halt 403, 'CSRF token verification failed'
    end
  end

  # Current page title
  def page_title
    @page_title || 'Source License'
  end

  # Set page title
  def title(text)
    @page_title = text
  end

  # Meta description
  def meta_description(text = nil)
    if text
      @meta_description = text
    else
      @meta_description || 'Professional software licensing management system'
    end
  end

  # Check if current page matches path
  def current_page?(path)
    request.path == path
  end

  # Generate pagination links
  def paginate(collection, page, per_page)
    total_pages = (collection.count.to_f / per_page).ceil
    current_page = page.to_i

    return '' if total_pages <= 1

    html = '<nav><ul class="pagination justify-content-center">'

    # Previous button
    html += if current_page > 1
              "<li class=\"page-item\"><a class=\"page-link\" href=\"?page=#{current_page - 1}\">Previous</a></li>"
            else
              '<li class="page-item disabled"><span class="page-link">Previous</span></li>'
            end

    # Page numbers
    (1..total_pages).each do |p|
      html += if p == current_page
                "<li class=\"page-item active\"><span class=\"page-link\">#{p}</span></li>"
              else
                "<li class=\"page-item\"><a class=\"page-link\" href=\"?page=#{p}\">#{p}</a></li>"
              end
    end

    # Next button
    html += if current_page < total_pages
              "<li class=\"page-item\"><a class=\"page-link\" href=\"?page=#{current_page + 1}\">Next</a></li>"
            else
              '<li class="page-item disabled"><span class="page-link">Next</span></li>'
            end

    html += '</ul></nav>'
    html
  end

  # Generate breadcrumbs
  def breadcrumbs(*links)
    return '' if links.empty?

    html = '<nav aria-label="breadcrumb"><ol class="breadcrumb">'

    links[0..-2].each do |link|
      name, path = link
      html += "<li class=\"breadcrumb-item\"><a href=\"#{path}\">#{h(name)}</a></li>"
    end

    # Last item (current page)
    html += "<li class=\"breadcrumb-item active\" aria-current=\"page\">#{h(links.last.first)}</li>"
    html += '</ol></nav>'

    html
  end

  # Generate alert component
  def alert(message, type = 'info', dismissible = true)
    alert_class = "alert alert-#{type}"
    alert_class += ' alert-dismissible fade show' if dismissible

    html = "<div class=\"#{alert_class}\" role=\"alert\">"
    html += h(message)

    html += '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>' if dismissible

    html += '</div>'
    html
  end

  # File size formatting
  def format_file_size(size_in_bytes)
    return '0 B' unless size_in_bytes&.positive?

    units = %w[B KB MB GB TB]
    size = size_in_bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{format('%.1f', size)} #{units[unit_index]}"
  end

  # Environment-specific asset URL
  def asset_url(path)
    return path if development?

    # In production, you might want to use a CDN
    cdn_host = ENV.fetch('CDN_HOST', nil)
    cdn_host ? "#{cdn_host}#{path}" : path
  end

  # Generate tooltip
  def tooltip(text, content)
    "<span data-bs-toggle=\"tooltip\" data-bs-placement=\"top\" title=\"#{h(content)}\">#{h(text)}</span>"
  end

  # Number formatting
  def format_number(number, decimals = 0)
    return '0' unless number

    if decimals.positive?
      format("%.#{decimals}f", number.to_f).reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    else
      number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end

  # Percentage formatting
  def format_percentage(value, total, decimals = 1)
    return '0%' unless value && total&.positive?

    percentage = (value.to_f / total) * 100
    "#{format("%.#{decimals}f", percentage)}%"
  end

  # Simple humanize method for strings
  def humanize(text)
    return '' unless text

    text.to_s.gsub('_', ' ').split.map(&:capitalize).join(' ')
  end
end

# License-specific helper functions
module LicenseHelpers
  # Check if license key format is valid
  def valid_license_format?(key)
    key.to_s.match?(/\A[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
  end

  # Format license key for display
  def format_license_key(key)
    return 'Invalid' unless valid_license_format?(key)

    key.upcase
  end

  # Generate license status icon
  def license_status_icon(status)
    case status.to_s.downcase
    when 'active'
      '<i class="fas fa-check-circle text-success"></i>'
    when 'suspended'
      '<i class="fas fa-pause-circle text-warning"></i>'
    when 'expired'
      '<i class="fas fa-clock text-danger"></i>'
    when 'revoked'
      '<i class="fas fa-times-circle text-danger"></i>'
    else
      '<i class="fas fa-question-circle text-muted"></i>'
    end
  end

  # Calculate license expiration
  def license_expires_in(expires_at)
    return 'Never' unless expires_at
    return 'Expired' if expires_at < Time.now

    diff = expires_at - Time.now
    days = (diff / 86_400).to_i

    if days > 365
      "#{(days / 365).to_i} year(s)"
    elsif days > 30
      "#{(days / 30).to_i} month(s)"
    elsif days.positive?
      "#{days} day(s)"
    else
      hours = (diff / 3600).to_i
      "#{hours} hour(s)"
    end
  end

  # Generate activation progress bar
  def activation_progress(used, total)
    return '' unless used && total

    percentage = [(used.to_f / total * 100).to_i, 100].min
    color_class = case percentage
                  when 0..50 then 'bg-success'
                  when 51..80 then 'bg-warning'
                  else 'bg-danger'
                  end

    "<div class=\"progress\" style=\"height: 8px;\">
      <div class=\"progress-bar #{color_class}\" style=\"width: #{percentage}%\">
      </div>
    </div>
    <small class=\"text-muted\">#{used}/#{total} activations used</small>"
  end
end

# Order-specific helper functions
module OrderHelpers
  # Helper method for order status icons
  def order_status_icon(status)
    case status.to_s.downcase
    when 'completed'
      '<i class="fas fa-check-circle text-success"></i>'
    when 'pending'
      '<i class="fas fa-clock text-warning"></i>'
    when 'failed'
      '<i class="fas fa-times-circle text-danger"></i>'
    when 'refunded'
      '<i class="fas fa-undo text-warning"></i>'
    else
      '<i class="fas fa-question-circle text-muted"></i>'
    end
  end

  # Helper method for payment method icons
  def payment_method_icon(method)
    case method.to_s.downcase
    when 'stripe'
      '<i class="fab fa-stripe text-info"></i>'
    when 'paypal'
      '<i class="fab fa-paypal text-primary"></i>'
    when 'free'
      '<i class="fas fa-gift text-success"></i>'
    when 'manual'
      '<i class="fas fa-user-cog text-secondary"></i>'
    else
      '<i class="fas fa-credit-card text-muted"></i>'
    end
  end

  # Helper method for order status alert classes
  def order_status_class(status)
    case status.to_s.downcase
    when 'completed'
      'success'
    when 'pending'
      'warning'
    when 'failed'
      'danger'
    when 'refunded'
      'info'
    else
      'secondary'
    end
  end
end

# Customer-specific helper functions
module CustomerHelpers
  # Helper method for customer status icons
  def customer_status_icon(status)
    case status.to_s.downcase
    when 'active'
      '<i class="fas fa-check-circle text-success"></i>'
    when 'inactive'
      '<i class="fas fa-pause-circle text-secondary"></i>'
    when 'suspended'
      '<i class="fas fa-ban text-danger"></i>'
    else
      '<i class="fas fa-question-circle text-muted"></i>'
    end
  end

  # Helper method for email verification status
  def email_verification_icon(verified)
    if verified
      '<i class="fas fa-shield-check text-success" title="Email Verified"></i>'
    else
      '<i class="fas fa-shield-exclamation text-warning" title="Email Not Verified"></i>'
    end
  end

  # Helper method for customer activity status
  def customer_activity_status(customer)
    if customer.last_login_at
      thirty_days_ago = Time.now - (30 * 24 * 60 * 60)
      ninety_days_ago = Time.now - (90 * 24 * 60 * 60)

      if customer.last_login_at > thirty_days_ago
        '<span class="badge bg-success">Active</span>'
      elsif customer.last_login_at > ninety_days_ago
        '<span class="badge bg-warning">Recent</span>'
      else
        '<span class="badge bg-secondary">Inactive</span>'
      end
    else
      '<span class="badge bg-light text-dark">Never Logged In</span>'
    end
  end

  # Helper method for customer registration source
  def registration_source_icon(customer)
    # This could be expanded to track registration sources
    thirty_days_ago = Time.now - (30 * 24 * 60 * 60)
    if customer.created_at > thirty_days_ago
      '<i class="fas fa-user-plus text-info" title="New Customer"></i>'
    else
      '<i class="fas fa-user text-muted" title="Existing Customer"></i>'
    end
  end

  # Helper method for customer value calculation
  def customer_lifetime_value(customer)
    total_spent = Order.where(email: customer.email, status: 'completed').sum(:amount) || 0
    format_currency(total_spent)
  end

  # Helper method for customer order count
  def customer_order_count(customer)
    Order.where(email: customer.email).count
  end

  # Helper method for customer license count display
  def customer_license_summary(customer)
    total = customer.license_count
    active = customer.active_licenses.count

    if total.zero?
      '<span class="text-muted">No licenses</span>'
    elsif active == total
      "<span class=\"text-success\">#{active} license#{'s' unless active == 1}</span>"
    else
      "<span class=\"text-warning\">#{active}/#{total} active</span>"
    end
  end

  # Helper method for account age
  def account_age_text(customer)
    return 'Unknown' unless customer.created_at

    days = ((Time.now - customer.created_at) / (24 * 60 * 60)).ceil

    if days < 30
      "#{days} day#{'s' unless days == 1}"
    elsif days < 365
      months = (days / 30).ceil
      "#{months} month#{'s' unless months == 1}"
    else
      years = (days / 365).ceil
      "#{years} year#{'s' unless years == 1}"
    end
  end

  # Helper method for customer risk level
  def customer_risk_level(customer)
    # Simple risk assessment based on activity
    risk_factors = 0

    # No email verification
    risk_factors += 1 unless customer.email_verified?

    # No recent login
    ninety_days_ago = Time.now - (90 * 24 * 60 * 60)
    risk_factors += 1 if customer.last_login_at.nil? || customer.last_login_at < ninety_days_ago

    # Suspended account
    risk_factors += 2 if customer.status == 'suspended'

    # Multiple failed orders
    failed_orders = Order.where(email: customer.email, status: 'failed').count
    risk_factors += 1 if failed_orders > 2

    case risk_factors
    when 0..1
      '<span class="badge bg-success text-dark">Low</span>'
    when 2..3
      '<span class="badge bg-warning text-dark">Medium</span>'
    else
      '<span class="badge bg-danger text-dark">High</span>'
    end
  end
end

# Reports-specific helper functions
module ReportsHelpers
  # Format data for Chart.js with proper escaping
  def chart_data_for_js(data)
    JSON.generate(data).gsub('</script>', '<\/script>')
  end

  # Calculate percentage change between two values
  def percentage_change(current, previous)
    return 0 if previous.nil? || previous.zero?

    ((current.to_f - previous.to_f) / previous.to_f) * 100
  end

  # Format large numbers with abbreviations
  def format_large_number(number)
    return '0' unless number&.positive?

    case number
    when 0..999
      number.to_s
    when 1000..999_999
      "#{(number / 1000.0).round(1)}K"
    when 1_000_000..999_999_999
      "#{(number / 1_000_000.0).round(1)}M"
    else
      "#{(number / 1_000_000_000.0).round(1)}B"
    end
  end

  # Generate trend arrow based on percentage change
  def trend_arrow(percentage)
    if percentage.positive?
      '<i class="fas fa-arrow-up text-success"></i>'
    elsif percentage.negative?
      '<i class="fas fa-arrow-down text-danger"></i>'
    else
      '<i class="fas fa-minus text-muted"></i>'
    end
  end
end

# Admin-specific helper functions
module AdminHelpers
  # Check if admin is the original admin created from .env
  def is_original_admin?(admin)
    return false unless admin

    # Check if this admin's email matches the initial admin email from .env
    initial_admin_email = ENV['INITIAL_ADMIN_EMAIL']
    return false unless initial_admin_email

    admin.email&.downcase == initial_admin_email.downcase
  end

  # Check if admin is protected (original or system admin)
  def is_protected_admin?(admin)
    return false unless admin

    # Protect the original admin from .env
    return true if is_original_admin?(admin)

    # Protect the first admin in the system (fallback)
    first_admin = Admin.order(:id).first
    return true if first_admin && admin.id == first_admin.id

    # Additional protection logic could be added here
    false
  end

  # Get admin protection reason
  def admin_protection_reason(admin)
    return nil unless is_protected_admin?(admin)

    if is_original_admin?(admin)
      'Original admin account created during installation'
    elsif Admin.order(:id).first&.id == admin.id
      'First administrator account in the system'
    else
      'Protected system account'
    end
  end

  # Check if admin can be modified by current user
  def can_modify_admin?(target_admin, current_admin)
    return false unless target_admin && current_admin

    # Can't modify yourself for certain operations
    return false if target_admin.id == current_admin.id

    # Can't modify protected admins
    return false if is_protected_admin?(target_admin)

    true
  end

  # Get admin display name
  def admin_display_name(admin)
    return 'Unknown Admin' unless admin

    if admin.name && !admin.name.empty?
      admin.name
    else
      admin.email&.split('@')&.first || 'Admin'
    end
  end

  # Check if admin is system critical
  def is_system_critical_admin?(admin)
    return false unless admin

    # Check if this is the last active admin
    active_admin_count = Admin.where(active: true).count
    return true if active_admin_count <= 1 && admin.active?

    # Check if this is a protected admin
    is_protected_admin?(admin)
  end

  # Get admin status with protection info
  def admin_status_with_protection(admin)
    status = admin.active? ? 'Active' : 'Inactive'
    
    if is_protected_admin?(admin)
      protection_reason = admin_protection_reason(admin)
      "#{status} (Protected: #{protection_reason})"
    else
      status
    end
  end

  # Admin security level indicator
  def admin_security_level(admin)
    return 'Unknown' unless admin

    level = 0
    
    # Recent login
    level += 1 if admin.last_login_at && admin.last_login_at > (Time.now - 30 * 24 * 60 * 60)
    
    # Has name set
    level += 1 if admin.name && !admin.name.empty?
    
    # Email verified (if field exists)
    level += 1 if admin.respond_to?(:email_verified) && admin.email_verified
    
    # Two-factor enabled (if field exists)
    level += 1 if admin.respond_to?(:two_factor_enabled) && admin.two_factor_enabled
    
    # Recent password change (if field exists)
    if admin.respond_to?(:password_changed_at) && admin.password_changed_at
      level += 1 if admin.password_changed_at > (Time.now - 90 * 24 * 60 * 60)
    end

    case level
    when 0..1
      '<span class="badge bg-danger">Low</span>'
    when 2..3
      '<span class="badge bg-warning">Medium</span>'
    else
      '<span class="badge bg-success">High</span>'
    end
  end
end

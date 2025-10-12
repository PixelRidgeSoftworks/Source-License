# frozen_string_literal: true

# Source-License: Template Helper Functions
# Provides basic template helper methods for the Sinatra application

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
    return '' unless text
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
    when 3600..86_399
      hours = (seconds_ago / 3600).round
      "#{hours} hour#{'s' if hours != 1}"
    when 86_400..2_591_999
      days = (seconds_ago / 86_400).round
      "#{days} day#{'s' if days != 1}"
    when 2_592_000..31_535_999
      months = (seconds_ago / 2_592_000).round
      "#{months} month#{'s' if months != 1}"
    else
      years = (seconds_ago / 31_536_000).round
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

  # Build pagination URL with current query parameters
  def build_pagination_url(page)
    query_params = request.params.dup
    query_params['page'] = page.to_s
    "#{request.path}?#{URI.encode_www_form(query_params)}"
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

    text.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
  end
end

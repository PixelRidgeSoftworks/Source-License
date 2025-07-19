# frozen_string_literal: true

require_relative 'test_helper'

class HelpersTest < Minitest::Test
  include TemplateHelpers
  include LicenseHelpers
  include CustomizationHelpers

  def setup
    super
    # Mock request object for helpers that need it
    @request = Struct.new(:path).new('/test')
  end

  attr_reader :request

  def test_html_escape
    assert_equal '&lt;script&gt;', h('<script>')
    assert_equal '&quot;quoted&quot;', h('"quoted"')
    assert_equal 'safe text', h('safe text')
  end

  def test_url_encode
    assert_equal 'hello%20world', u('hello world')
    assert_equal 'test%40example.com', u('test@example.com')
  end

  def test_truncate
    long_text = 'This is a very long text that should be truncated'

    assert_equal 'This is a very long text that should be truncated', truncate(long_text, 100)
    assert_equal 'This is a very...', truncate(long_text, 16)
    assert_equal 'Short', truncate('Short', 100)
  end

  def test_time_ago
    assert_equal 'Just now', time_ago(Time.now)
    assert_equal '5 minutes ago', time_ago(5.minutes.ago)
    assert_equal '2 hours ago', time_ago(2.hours.ago)
    assert_equal '3 days ago', time_ago(3.days.ago)

    old_time = 2.years.ago

    assert_includes time_ago(old_time), old_time.year.to_s
  end

  def test_format_currency
    assert_equal '$0.00', format_currency(nil)
    assert_equal '$99.99', format_currency(99.99)
    assert_equal '$1,234.56', format_currency(1234.56)
    assert_equal '€50.00', format_currency(50, 'EUR')
    assert_equal '£25.99', format_currency(25.99, 'GBP')
  end

  def test_format_date
    date = Date.new(2025, 1, 15)
    time = Time.new(2025, 1, 15, 14, 30, 0)

    assert_equal '01/15/2025', format_date(date, :short)
    assert_equal 'January 15, 2025', format_date(date, :long)
    assert_equal '01/15/2025 02:30 PM', format_date(time, :datetime)
  end

  def test_nav_link
    @request.path = '/admin'

    # Active link
    result = nav_link('Dashboard', '/admin')

    assert_includes result, 'active'
    assert_includes result, 'Dashboard'

    # Inactive link
    @request.path = '/admin'
    result = nav_link('Products', '/admin/products')

    refute_includes result, 'active'
  end

  def test_status_badge
    assert_includes status_badge('active'), 'bg-success'
    assert_includes status_badge('pending'), 'bg-warning'
    assert_includes status_badge('expired'), 'bg-danger'
    assert_includes status_badge('suspended'), 'bg-secondary'
    assert_includes status_badge('unknown'), 'bg-light'
  end

  def test_button_helper
    result = button('Click Me')

    assert_includes result, 'Click Me'
    assert_includes result, 'btn btn-primary'

    result = button('Custom', class: 'btn btn-danger', onclick: 'alert("test")')

    assert_includes result, 'btn btn-danger'
    assert_includes result, 'alert("test")'
  end

  def test_card_helper
    result = card('Test Card') { 'Content here' }

    assert_includes result, 'Test Card'
    assert_includes result, 'Content here'
    assert_includes result, 'card'
    assert_includes result, 'card-header'
    assert_includes result, 'card-body'
  end

  def test_format_file_size
    assert_equal '0 B', format_file_size(nil)
    assert_equal '0 B', format_file_size(0)
    assert_equal '512 B', format_file_size(512)
    assert_equal '1.0 KB', format_file_size(1024)
    assert_equal '1.5 MB', format_file_size(1024 * 1024 * 1.5)
    assert_equal '2.0 GB', format_file_size(1024 * 1024 * 1024 * 2)
  end

  def test_format_number
    assert_equal '0', format_number(nil)
    assert_equal '1,234', format_number(1234)
    assert_equal '1,234,567', format_number(1_234_567)
    assert_equal '1,234.57', format_number(1234.567, 2)
  end

  def test_format_percentage
    assert_equal '0%', format_percentage(nil, 100)
    assert_equal '0%', format_percentage(0, 0)
    assert_equal '50.0%', format_percentage(50, 100)
    assert_equal '33.3%', format_percentage(1, 3)
    assert_equal '150.0%', format_percentage(150, 100)
  end

  def test_valid_license_format
    assert valid_license_format?('ABCD-1234-EFGH-5678')
    assert valid_license_format?('1111-2222-3333-4444')
    refute valid_license_format?('invalid-format')
    refute valid_license_format?('ABCD-1234-EFGH')
    refute valid_license_format?('abcd-1234-efgh-5678')
  end

  def test_format_license_key
    assert_equal 'ABCD-1234-EFGH-5678', format_license_key('abcd-1234-efgh-5678')
    assert_equal 'Invalid', format_license_key('invalid')
  end

  def test_license_status_icon
    assert_includes license_status_icon('active'), 'fa-check-circle'
    assert_includes license_status_icon('suspended'), 'fa-pause-circle'
    assert_includes license_status_icon('expired'), 'fa-clock'
    assert_includes license_status_icon('revoked'), 'fa-times-circle'
  end

  def test_license_expires_in
    assert_equal 'Never', license_expires_in(nil)
    assert_equal 'Expired', license_expires_in(1.day.ago)

    future_date = 30.days.from_now
    result = license_expires_in(future_date)

    assert_includes result, 'day'

    far_future = 2.years.from_now
    result = license_expires_in(far_future)

    assert_includes result, 'year'
  end

  def test_activation_progress
    result = activation_progress(2, 5)

    assert_includes result, 'progress'
    assert_includes result, '2/5'
    assert_includes result, '40%'

    # Test color classes
    assert_includes activation_progress(1, 5), 'bg-success'  # 20%
    assert_includes activation_progress(3, 5), 'bg-warning'  # 60%
    assert_includes activation_progress(5, 5), 'bg-danger'   # 100%
  end

  def test_json_for_js
    data = { key: 'value', script: '<script>' }
    result = json_for_js(data)

    assert_includes result, '"key":"value"'
    assert_includes result, '<\\/' # Escaped for JS
    refute_includes result, '</' # Should not contain unescaped
  end

  def test_breadcrumbs
    result = breadcrumbs(['Home', '/'], ['Admin', '/admin'], ['Dashboard', '/admin/dashboard'])

    assert_includes result, 'breadcrumb'
    assert_includes result, 'Home'
    assert_includes result, 'Admin'
    assert_includes result, 'Dashboard'
    assert_includes result, 'active'
  end

  def test_alert_helper
    result = alert('Test message', 'success')

    assert_includes result, 'alert-success'
    assert_includes result, 'Test message'

    result = alert('Error message', 'danger', false)

    assert_includes result, 'alert-danger'
    refute_includes result, 'dismissible'
  end

  def test_tooltip
    result = tooltip('Hover text', 'Tooltip content')

    assert_includes result, 'data-bs-toggle="tooltip"'
    assert_includes result, 'Hover text'
    assert_includes result, 'Tooltip content'
  end

  def test_environment_helpers
    ENV['APP_ENV'] = 'test'

    refute_predicate self, :production?

    ENV['APP_ENV'] = 'production'

    assert_predicate self, :production?
    refute_predicate self, :development?

    ENV['APP_ENV'] = 'development'

    assert_predicate self, :development?
    refute_predicate self, :production?
  ensure
    ENV['APP_ENV'] = 'test'
  end

  def test_payment_gateway_helpers
    ENV['STRIPE_SECRET_KEY'] = 'sk_test_123'
    ENV['STRIPE_PUBLISHABLE_KEY'] = 'pk_test_123'

    assert_predicate self, :stripe_enabled?

    ENV.delete('STRIPE_SECRET_KEY')

    refute_predicate self, :stripe_enabled?

    ENV['PAYPAL_CLIENT_ID'] = 'test_client_id'
    ENV['PAYPAL_CLIENT_SECRET'] = 'test_secret'

    assert_predicate self, :paypal_enabled?

    ENV.delete('PAYPAL_CLIENT_ID')

    refute_predicate self, :paypal_enabled?
  ensure
    # Clean up
    ENV.delete('STRIPE_SECRET_KEY')
    ENV.delete('STRIPE_PUBLISHABLE_KEY')
    ENV.delete('PAYPAL_CLIENT_ID')
    ENV.delete('PAYPAL_CLIENT_SECRET')
  end

  def test_custom_value_helper
    with_customizations('branding' => { 'site_name' => 'Test Site' }) do
      assert_equal 'Test Site', custom('branding.site_name')
      assert_equal 'Default', custom('nonexistent.key', 'Default')
    end
  end

  def test_custom_css_variables
    with_customizations({
      'colors' => { 'primary' => '#ff0000', 'secondary' => '#00ff00' },
      'layout' => { 'hero_padding' => '5rem 0' },
    }) do
      result = custom_css_variables

      assert_includes result, '--custom-primary: #ff0000'
      assert_includes result, '--custom-secondary: #00ff00'
      assert_includes result, '--custom-hero-padding: 5rem 0'
    end
  end

  def test_feature_enabled
    with_customizations('features' => { 'show_help_widget' => true, 'dark_mode' => false }) do
      assert feature_enabled?('show_help_widget')
      refute feature_enabled?('dark_mode')
      refute feature_enabled?('nonexistent_feature')
    end
  end

  def test_custom_color
    with_customizations('colors' => { 'primary' => '#ff0000' }) do
      assert_equal '#ff0000', custom_color('primary')
      assert_equal '#default', custom_color('nonexistent', '#default')
    end
  end

  def test_custom_text
    with_customizations('text' => { 'hero_title' => 'Custom Title' }) do
      assert_equal 'Custom Title', custom_text('hero_title')
      assert_equal 'Default', custom_text('nonexistent', 'Default')
    end
  end

  def test_custom_style
    with_customizations({
      'colors' => { 'hero_gradient_start' => '#ff0000', 'hero_gradient_end' => '#00ff00' },
      'layout' => { 'hero_padding' => '5rem 0', 'card_border_radius' => '15px' },
    }) do
      hero_style = custom_style('hero')

      assert_includes hero_style, 'linear-gradient'
      assert_includes hero_style, '#ff0000'
      assert_includes hero_style, '5rem 0'

      card_style = custom_style('card')

      assert_includes card_style, '15px'
    end
  end

  def test_paginate
    # Create a mock collection
    collection = Struct.new(:total_count).new(50)

    result = paginate(collection, 2, 10)

    assert_includes result, 'pagination'
    assert_includes result, 'Previous'
    assert_includes result, 'Next'
    assert_includes result, 'page-item'
  end

  def test_csrf_token_generation
    first_token = csrf_token
    second_token = csrf_token

    # Should return same token within session
    assert_equal first_token, second_token
    assert_operator first_token.length, :>=, 32
  end

  def test_csrf_input
    result = csrf_input

    assert_includes result, 'authenticity_token'
    assert_includes result, 'hidden'
  end

  private

  # Mock session for testing
  def session
    @session ||= {}
  end
end

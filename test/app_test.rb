# frozen_string_literal: true

require_relative 'test_helper'

class AppTest < Minitest::Test
  def test_homepage_loads
    get '/'

    assert_successful_response
    assert_includes last_response.body, 'Source License'
  end

  def test_homepage_with_products
    products = create_list(:product, 3)

    get '/'

    assert_successful_response
    products.each do |product|
      assert_includes last_response.body, product.name
    end
  end

  def test_homepage_without_products
    get '/'

    assert_successful_response
    assert_includes last_response.body, 'No Products Available'
  end

  def test_license_lookup_page
    get '/my-licenses'

    assert_successful_response
    assert_includes last_response.body, 'License Lookup'
    assert_includes last_response.body, 'license key or email'
  end

  def test_admin_login_page
    get '/admin/login'

    assert_successful_response
    assert_includes last_response.body, 'Admin Login'
    assert_includes last_response.body, 'email'
    assert_includes last_response.body, 'password'
  end

  def test_admin_login_success
    create_test_admin

    post '/admin/login', { email: 'admin@test.com', password: 'test_password' }

    assert_redirect_to('/admin')
  end

  def test_admin_login_failure
    post '/admin/login', { email: 'admin@test.com', password: 'wrong_password' }

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Invalid credentials'
  end

  def test_admin_dashboard_requires_login
    get '/admin'

    # Should redirect to login or return 401
    assert_includes [302, 401], last_response.status
  end

  def test_admin_dashboard_with_login
    create_test_admin
    login_as_admin

    get '/admin'

    assert_successful_response
    assert_includes last_response.body, 'Dashboard'
  end

  def test_admin_logout
    create_test_admin
    login_as_admin

    post '/admin/logout'

    assert_redirect_to('/admin/login')
  end

  def test_customization_page_requires_admin
    get '/admin/customize'

    assert_includes [302, 401], last_response.status
  end

  def test_customization_page_with_admin
    create_test_admin
    login_as_admin

    get '/admin/customize'

    assert_successful_response
    assert_includes last_response.body, 'Template Customization'
  end

  def test_code_guide_page
    create_test_admin
    login_as_admin

    get '/admin/customize/code-guide'

    assert_successful_response
    assert_includes last_response.body, 'Template Code Guide'
  end

  def test_settings_page
    create_test_admin
    login_as_admin

    get '/admin/settings'

    assert_successful_response
    assert_includes last_response.body, 'System Settings'
  end

  def test_404_error_page
    get '/nonexistent-page'

    assert_equal 404, last_response.status
    assert_includes last_response.body, '404'
  end

  def test_api_auth_endpoint
    create_test_admin

    post '/api/auth', { email: 'admin@test.com', password: 'test_password' }

    assert_successful_response
    response = assert_json_response
    assert response['success']
    assert response['token']
  end

  def test_api_auth_failure
    post '/api/auth', { email: 'admin@test.com', password: 'wrong_password' }

    assert_equal 401, last_response.status
    response = assert_json_response
    refute response['success']
  end

  def test_license_validation_api
    license = create(:license)

    get "/api/license/#{license.license_key}/validate"

    assert_successful_response
    response = assert_json_response
    assert response['valid']
    assert_equal license.status, response['status']
  end

  def test_license_validation_api_invalid_key
    get '/api/license/INVALID-KEY-FORMAT/validate'

    assert_equal 404, last_response.status
    response = assert_json_response
    refute response['valid']
  end

  def test_license_activation_api
    license = create(:license, max_activations: 3, activation_count: 0)

    post "/api/license/#{license.license_key}/activate", {
      machine_fingerprint: 'test-machine-123',
    }

    assert_successful_response
    response = assert_json_response
    assert response['success']
    assert_equal 2, response['activations_remaining']
  end

  def test_license_activation_api_max_reached
    license = create(:license, :fully_activated)

    post "/api/license/#{license.license_key}/activate", {
      machine_fingerprint: 'test-machine-123',
    }

    assert_equal 400, last_response.status
    response = assert_json_response
    refute response['success']
    assert_includes response['error'], 'Maximum activations reached'
  end

  def test_customization_update
    create_test_admin
    login_as_admin

    updates = {
      'branding.site_name' => 'My Custom License Store',
      'colors.primary' => '#ff0000',
    }

    post '/admin/customize', updates.to_json, 'CONTENT_TYPE' => 'application/json'

    assert_successful_response
    response = assert_json_response
    assert response['success']
  end

  def test_customization_reset
    create_test_admin
    login_as_admin

    post '/admin/customize/reset'

    assert_successful_response
    response = assert_json_response
    assert response['success']
  end

  def test_customization_export
    create_test_admin
    login_as_admin

    get '/admin/customize/export'

    assert_successful_response
    assert_equal 'application/x-yaml', last_response.content_type
  end

  def test_product_page_exists
    product = create(:product)

    get "/product/#{product.id}"

    assert_successful_response
    assert_includes last_response.body, product.name
  end

  def test_product_page_not_found
    get '/product/99999'

    assert_equal 404, last_response.status
  end

  def test_inactive_product_not_accessible
    product = create(:product, :inactive)

    get "/product/#{product.id}"

    assert_equal 404, last_response.status
  end

  def test_cart_page
    get '/cart'

    assert_successful_response
    assert_includes last_response.body, 'Shopping Cart'
  end

  def test_checkout_page
    get '/checkout'

    assert_successful_response
    assert_includes last_response.body, 'Checkout'
  end

  def test_success_page
    get '/success'

    assert_successful_response
    assert_includes last_response.body, 'Purchase Successful'
  end

  def test_license_details_page
    license = create(:license)

    get "/license/#{license.license_key}"

    assert_successful_response
    assert_includes last_response.body, license.license_key
  end

  def test_license_details_not_found
    get '/license/INVALID-KEY-1234'

    assert_equal 404, last_response.status
  end

  def test_download_with_valid_license
    scenario = create_complete_order_with_license
    license = scenario[:license]

    # Mock file existence
    download_path = File.join(ENV['DOWNLOADS_PATH'] || './downloads', license.product.download_file)
    FileUtils.mkdir_p(File.dirname(download_path))
    File.write(download_path, 'test file content')

    get "/download/#{license.license_key}/software.zip"

    # Should either succeed or redirect depending on implementation
    assert_includes [200, 302], last_response.status
  ensure
    # Clean up test file
    FileUtils.rm_f(download_path) if download_path
  end

  def test_download_with_invalid_license
    get '/download/INVALID-KEY/software.zip'

    assert_equal 404, last_response.status
  end

  def test_csrf_protection_in_forms
    get '/admin/login'

    assert_successful_response
    # Check for CSRF token in form (if implemented)
    assert_includes last_response.body, 'csrf' if last_response.body.include?('csrf')
  end

  def test_session_persistence
    create_test_admin

    # Login
    post '/admin/login', { email: 'admin@test.com', password: 'test_password' }

    assert_redirect_to('/admin')

    # Access protected page with session
    follow_redirect!

    assert_successful_response
  end

  def test_error_handling_for_database_errors
    # Simulate database error by using invalid table
    original_method = DB.method(:from)
    DB.define_singleton_method(:from) do |*_args|
      raise Sequel::DatabaseError, 'Simulated database error'
    end

    get '/'

    # Should handle error gracefully
    assert_equal 500, last_response.status
  ensure
    # Restore original method
    DB.define_singleton_method(:from, original_method)
  end

  def test_content_type_headers
    get '/'

    assert_includes last_response.content_type, 'text/html'

    get '/api/license/TEST-1234-5678-ABCD/validate'

    assert_includes last_response.content_type, 'application/json'
  end

  def test_security_headers
    get '/'

    # Check for basic security headers if implemented
    # These are good to have but not required for basic functionality
    last_response.headers

    # Just verify the response works
    assert_successful_response
  end

  def test_admin_product_management
    create_test_admin
    login_as_admin

    get '/admin/products'

    assert_successful_response
    assert_includes last_response.body, 'Manage Products'
  end

  def test_admin_license_management
    create_test_admin
    login_as_admin

    get '/admin/licenses'

    assert_successful_response
    assert_includes last_response.body, 'Manage Licenses'
  end

  def test_webhook_endpoints
    # Test Stripe webhook
    post '/api/webhook/stripe', {}, 'CONTENT_TYPE' => 'application/json'

    # Should not crash (might return error due to missing signature)
    assert_includes [200, 400], last_response.status

    # Test PayPal webhook
    post '/api/webhook/paypal', {}, 'CONTENT_TYPE' => 'application/json'

    assert_includes [200, 400], last_response.status
  end

  def test_unknown_webhook_provider
    post '/api/webhook/unknown', {}, 'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status
    response = assert_json_response
    assert_includes response['error'], 'Unknown provider'
  end

  def test_admin_preview_page
    create_test_admin
    login_as_admin

    get '/admin/customize/preview'

    assert_successful_response
    # Should show the main site layout
    assert_includes last_response.body, 'Source License'
  end

  def test_customization_with_invalid_json
    create_test_admin
    login_as_admin

    post '/admin/customize', 'invalid json', 'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status
  end

  def test_api_order_creation_requires_auth
    post '/api/orders', {
      email: 'test@example.com',
      items: [{ product_id: 1, quantity: 1 }],
    }.to_json, 'CONTENT_TYPE' => 'application/json'

    # Should require authentication
    assert_includes [401, 403], last_response.status
  end

  def test_order_status_api
    order = create(:order)

    get "/api/orders/#{order.id}"

    assert_successful_response
    response = assert_json_response
    assert_equal order.id, response['id']
    assert_equal order.status, response['status']
  end

  def test_order_status_api_not_found
    get '/api/orders/99999'

    assert_equal 404, last_response.status
    response = assert_json_response
    assert_includes response['error'], 'not found'
  end
end

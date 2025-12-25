# frozen_string_literal: true

# Source-License: Template Customization System
# Allows admins to customize text, colors, and positioning through the admin interface

require 'json'
require 'yaml'

class TemplateCustomizer
  CUSTOMIZATIONS_FILE = 'config/customizations.yml'

  class << self
    # Get all customizations with defaults (deep-merge to preserve nested defaults)
    def all_customizations
      deep_merge(default_customizations, load_customizations)
    end

    # Get a specific customization value
    def get(key, default = nil)
      # Treat empty or dot-only keys as missing
      normalized = key.to_s
      return default if normalized.strip.delete('.').empty?

      customizations = all_customizations
      keys = key.to_s.split('.')

      value = keys.reduce(customizations) do |hash, k|
        hash.is_a?(Hash) ? hash[k.to_s] : nil
      end

      value || default
    end

    # Set a customization value
    def set(key, value)
      customizations = load_customizations
      keys = key.to_s.split('.')

      # Navigate to the nested hash
      current = customizations
      keys[0..-2].each do |k|
        current[k] ||= {}
        current = current[k]
      end

      # Set the value
      current[keys.last] = value

      save_customizations(customizations)
    end

    # Update multiple customizations at once
    def update_multiple(updates)
      updates.each { |key, value| set(key, value) }
    end

    # Reset to defaults
    def reset_to_defaults
      FileUtils.rm_f(CUSTOMIZATIONS_FILE)
    end

    # Export customizations
    def export_customizations
      all_customizations.to_yaml
    end

    # Import customizations
    def import_customizations(yaml_content)
      imported = YAML.safe_load(yaml_content)
      save_customizations(imported) if imported.is_a?(Hash)
      true
    rescue StandardError
      false
    end

    # Get all customizations (alias for all_customizations)
    def all_customizations_list
      all_customizations
    end

    # Backwards-compatible aliases expected by tests
    def get_all_customizations
      all_customizations
    end

    # Get categories (alias for categories)
    def categories_list
      categories
    end

    # Backwards-compatible alias expected by tests
    def get_categories
      categories
    end

    # Get customization categories for the admin interface
    def categories
      result = {
        'branding' => {
          'title' => 'Branding & Identity',
          'description' => 'Customize your brand identity and basic information',
          'icon' => 'fas fa-palette',
        },
        'colors' => {
          'title' => 'Colors & Theme',
          'description' => 'Customize colors, themes, and visual appearance',
          'icon' => 'fas fa-paint-brush',
        },
        'text' => {
          'title' => 'Text & Content',
          'description' => 'Customize textual content, headlines and messages',
          'icon' => 'fas fa-font',
        },
        'hero_section' => {
          'title' => 'Hero Section',
          'description' => 'Customize the main hero section content and appearance',
          'icon' => 'fas fa-rocket',
        },
        'features_section' => {
          'title' => 'Features Section',
          'description' => 'Customize the features showcase section',
          'icon' => 'fas fa-star',
        },
        'products_section' => {
          'title' => 'Products Section',
          'description' => 'Customize the products display section',
          'icon' => 'fas fa-box',
        },
        'products_page' => {
          'title' => 'Products Page',
          'description' => 'Customize the dedicated products page layout and content',
          'icon' => 'fas fa-store',
        },
        'how_it_works' => {
          'title' => 'How It Works Section',
          'description' => 'Customize the process explanation section',
          'icon' => 'fas fa-list-ol',
        },
        'support_section' => {
          'title' => 'Support Section',
          'description' => 'Customize the support and help section',
          'icon' => 'fas fa-life-ring',
        },
        'page_structure' => {
          'title' => 'Page Structure',
          'description' => 'Control which sections appear and their order',
          'icon' => 'fas fa-th-large',
        },
        'layout' => {
          'title' => 'Layout & Spacing',
          'description' => 'Customize positioning, spacing, and layout options',
          'icon' => 'fas fa-expand-arrows-alt',
        },
        'advanced' => {
          'title' => 'Advanced Features',
          'description' => 'Enable/disable features and advanced customizations',
          'icon' => 'fas fa-cogs',
        },
      }
      # Backwards-compatible alias expected by tests
      result['features'] = result['features_section']
      result
    end

    private

    # Default customization values
    def default_customizations
      {
        'branding' => {
          'site_name' => 'Source License',
          'site_tagline' => 'Professional Software Licensing Made Simple',
          'company_name' => 'Your Company',
          'support_email' => ENV['ADMIN_EMAIL'] || 'support@example.com',
          'logo_text' => 'Source License',
          'footer_text' => 'Professional software licensing management system.',
        },
        'colors' => {
          'primary' => '#2c3e50',
          'secondary' => '#3498db',
          'success' => '#27ae60',
          'warning' => '#f39c12',
          'danger' => '#e74c3c',
          'light' => '#ecf0f1',
          'dark' => '#34495e',
          'background' => '#f8f9fa',
          'navbar_bg' => '#ffffff',
          'footer_bg' => '#2c3e50',
          'hero_gradient_start' => '#2c3e50',
          'hero_gradient_end' => '#3498db',
          'hero_text_color' => '#ffffff',
          'section_bg_color' => '#ffffff',
          'card_bg_color' => '#ffffff',
          'feature_icon_bg' => '#f8f9fa',
        },
        'hero_section' => {
          'enabled' => true,
          'title' => 'Transform Your Business with Our Solutions',
          'subtitle' => 'Powerful, reliable, and easy-to-use solutions designed to help your business grow. ' \
                        'From startups to enterprises, we provide the tools you need to succeed.',
          'cta_primary_text' => 'Get Started',
          'cta_primary_link' => '/products',
          'cta_primary_icon' => 'fas fa-rocket',
          'cta_secondary_text' => 'Sign Up Free',
          'cta_secondary_link' => '/register',
          'cta_secondary_icon' => 'fas fa-user-plus',
          'cta_dashboard_text' => 'My Dashboard',
          'show_trust_indicators' => true,
          'trust_indicator_1_icon' => 'fas fa-shield-alt',
          'trust_indicator_1_text' => 'Secure',
          'trust_indicator_2_icon' => 'fas fa-clock',
          'trust_indicator_2_text' => 'Fast Setup',
          'trust_indicator_3_icon' => 'fas fa-users',
          'trust_indicator_3_text' => 'Expert Support',
          'show_background_elements' => true,
          # SVG Visual Element Options
          'svg_enabled' => true,
          'svg_document_color' => '#ffffff',
          'svg_border_color' => '#e1e8ed',
          'svg_shadow_color' => '#00000020',
          'svg_header_color' => '#f8fafc',
          'svg_text_color' => '#64748b',
          'svg_text_light_color' => '#94a3b8',
          'svg_accent_color' => '#3b82f6',
          'svg_secondary_color' => '#10b981',
          'svg_tertiary_color' => '#f59e0b',
          'svg_status_color' => '#10b981',
          'svg_icon_color' => '#ffffff',
          'svg_show_floating_elements' => true,
          'svg_enable_animations' => true,
          'svg_title' => 'Business Dashboard',
          'svg_metric_1_value' => '98.5%',
          'svg_metric_1_label' => 'SUCCESS',
          'svg_metric_1_sublabel' => 'RATE',
          'svg_metric_2_value' => '24/7',
          'svg_metric_2_label' => 'UPTIME',
          'svg_metric_2_sublabel' => 'SUPPORT',
          'svg_metric_3_value' => '10K+',
          'svg_metric_3_label' => 'HAPPY',
          'svg_metric_3_sublabel' => 'CUSTOMERS',
          'svg_chart_title' => 'Performance Overview',
          'svg_progress_1_label' => 'Growth',
          'svg_progress_2_label' => 'Efficiency',
          'svg_status_text' => 'All systems operational',
          'svg_timestamp' => 'Live data',
          # Dashboard alternative to SVG
          'dashboard_title' => 'Business Dashboard',
          'stat_1_value' => '98%',
          'stat_1_label' => 'Success Rate',
          'stat_2_value' => '24/7',
          'stat_2_label' => 'Support',
          'stat_3_value' => '10k+',
          'stat_3_label' => 'Customers',
          'progress_1_label' => 'Performance',
          'progress_1_value' => '92%',
          'progress_2_label' => 'Growth',
          'progress_2_value' => '87%',
          'status_text' => 'All Systems Operational',
        },
        'features_section' => {
          'enabled' => true,
          'title' => 'Why Choose Us?',
          'subtitle' => 'We provide cutting-edge solutions with exceptional service to help your ' \
                        'business thrive in today\'s competitive market.',
          'feature_1_enabled' => true,
          'feature_1_icon' => 'fas fa-rocket',
          'feature_1_title' => 'Fast & Reliable',
          'feature_1_description' => 'Lightning-fast performance with 99.9% uptime guarantee. ' \
                                     'Built on modern infrastructure to ensure your business never slows down.',
          'feature_1_color_start' => '#007bff',
          'feature_1_color_end' => '#0056b3',
          'feature_2_enabled' => true,
          'feature_2_icon' => 'fas fa-shield-alt',
          'feature_2_title' => 'Secure & Compliant',
          'feature_2_description' => 'Enterprise-grade security with industry-standard compliance. ' \
                                     'Your data is protected with military-grade encryption.',
          'feature_2_color_start' => '#28a745',
          'feature_2_color_end' => '#1e7e34',
          'feature_3_enabled' => true,
          'feature_3_icon' => 'fas fa-cogs',
          'feature_3_title' => 'Easy Integration',
          'feature_3_description' => 'Seamless integration with your existing tools and workflows. ' \
                                     'Get up and running in minutes, not hours.',
          'feature_3_color_start' => '#ffc107',
          'feature_3_color_end' => '#e0a800',
          'feature_4_enabled' => true,
          'feature_4_icon' => 'fas fa-users',
          'feature_4_title' => 'Expert Support',
          'feature_4_description' => '24/7 dedicated support from our team of experts. ' \
                                     'Get help when you need it, however you need it.',
          'feature_4_color_start' => '#dc3545',
          'feature_4_color_end' => '#b02a37',
          'feature_5_enabled' => true,
          'feature_5_icon' => 'fas fa-chart-line',
          'feature_5_title' => 'Analytics & Insights',
          'feature_5_description' => 'Comprehensive analytics and reporting to help you make data-driven ' \
                                     'decisions and optimize your operations.',
          'feature_5_color_start' => '#17a2b8',
          'feature_5_color_end' => '#117a8b',
          'feature_6_enabled' => true,
          'feature_6_icon' => 'fas fa-mobile-alt',
          'feature_6_title' => 'Mobile Ready',
          'feature_6_description' => 'Fully responsive design that works perfectly on all devices. ' \
                                     'Manage your business from anywhere, anytime.',
          'feature_6_color_start' => '#6f42c1',
          'feature_6_color_end' => '#5a32a3',
        },
        'products_section' => {
          'enabled' => true,
          'title' => 'Available Software Products',
          'subtitle' => 'Choose from our selection of professional software solutions. All products include ' \
                        'secure licensing and instant delivery.',
          'show_when_no_products' => true,
          'no_products_title' => 'No Products Available',
          'no_products_message' => 'Products are currently being configured. Please check back soon or contact ' \
                                   'support.',
          'columns_per_row' => 3,
        },
        'products_page' => {
          'enabled' => true,
          'title' => 'Our Software Products',
          'subtitle' => 'Choose from our selection of professional software solutions. All products include ' \
                        'secure licensing and instant delivery.',
          'show_category_filters' => true,
          'show_search' => true,
          'show_category_descriptions' => true,
          'show_product_counts' => true,
          'no_products_title' => 'No Products Available',
          'no_products_message' => 'Products are currently being configured. ' \
                                   'Please check back soon or contact support.',
          'no_results_title' => 'No products found',
          'no_results_message' => 'Try adjusting your search or category filter.',
          'category_filters_title' => 'Browse by Category:',
          'all_products_text' => 'All Products',
          'search_placeholder' => 'Search products...',
          'products_per_row' => 3,
        },
        'how_it_works' => {
          'enabled' => true,
          'title' => 'How It Works',
          'subtitle' => 'Get started in three simple steps and see results immediately.',
          'step_1_enabled' => true,
          'step_1_icon' => 'fas fa-user-plus',
          'step_1_title' => 'Sign Up',
          'step_1_description' => 'Create your account in seconds with our streamlined registration process. ' \
                                  'No credit card required to get started.',
          'step_2_enabled' => true,
          'step_2_icon' => 'fas fa-cogs',
          'step_2_title' => 'Setup & Configure',
          'step_2_description' => 'Customize your setup with our intuitive configuration wizard. ' \
                                  'Everything is designed to be simple and straightforward.',
          'step_3_enabled' => true,
          'step_3_icon' => 'fas fa-rocket',
          'step_3_title' => 'Launch & Grow',
          'step_3_description' => 'Go live instantly and watch your business grow. ' \
                                  'Our platform scales with you as your needs evolve.',
          'cta_link' => '/register',
          'cta_text' => 'Start Your Journey',
        },
        'support_section' => {
          'enabled' => true,
          'title' => 'Need Help?',
          'subtitle' => 'We\'re here to support you every step of the way. Get help when you need it, ' \
                        'however you need it.',
          'card_1_enabled' => true,
          'card_1_icon' => 'fas fa-tachometer-alt',
          'card_1_title' => 'Account Management',
          'card_1_description' => 'Access your account, manage your settings, or view your ' \
                                  'activity through our user-friendly dashboard.',
          'card_1_button_1_text' => 'Create Account',
          'card_1_button_1_link' => '/register',
          'card_1_button_2_text' => 'Sign In',
          'card_1_button_2_link' => '/login',
          'card_2_enabled' => true,
          'card_2_icon' => 'fas fa-life-ring',
          'card_2_title' => 'Contact Support',
          'card_2_description' => 'Get help from our support team for technical issues, ' \
                                  'questions, or general assistance.',
          'card_2_button_text' => 'Email Support',
          'card_2_button_link' => 'mailto:support@example.com',
        },
        'page_structure' => {
          'section_order' => %w[hero features products how_it_works support],
          'hero_enabled' => true,
          'features_enabled' => true,
          'products_enabled' => true,
          'how_it_works_enabled' => true,
          'support_enabled' => true,
        },
        'text' => {
          'hero_title' => 'Professional Software Licensing Made Simple',
          'hero_subtitle' => 'Secure, reliable, and easy-to-manage software licenses for developers and ' \
                             'businesses. Support for both one-time purchases and subscriptions with ' \
                             'integrated payment processing.',
          'features_title' => 'Why Choose Source License?',
          'features_subtitle' => 'Built with modern technology and security best practices to ensure your ' \
                                 'software licensing is handled professionally.',
          'products_title' => 'Available Software Products',
          'products_subtitle' => 'Choose from our selection of professional software solutions. All products ' \
                                 'include secure licensing and instant delivery.',
          'how_it_works_title' => 'How It Works',
          'how_it_works_subtitle' => 'Get your software license in three simple steps.',
          'support_title' => 'Need Help?',
          'support_subtitle' => 'We\'re here to help you with any questions about your licenses or our products.',
          # Cart page text
          'cart_title' => 'Shopping Cart',
          'cart_clear_button' => 'Clear Cart',
          'cart_empty_title' => 'Your Cart is Empty',
          'cart_empty_message' => 'Browse our products and add items to your cart to get started.',
          'cart_browse_products' => 'Browse Products',
          'cart_order_summary' => 'Order Summary',
          'cart_proceed_checkout' => 'Proceed to Checkout',
          'cart_security_ssl' => 'SSL Secured',
          'cart_security_pci' => 'PCI Compliant',
          'cart_security_trusted' => 'Trusted',
          # Checkout page text
          'checkout_title' => 'Checkout',
          'checkout_step_information' => 'Information',
          'checkout_step_payment' => 'Payment',
          'checkout_step_complete' => 'Complete',
          'checkout_customer_info' => 'Customer Information',
          'checkout_full_name' => 'Full Name',
          'checkout_email' => 'Email Address',
          'checkout_company' => 'Company Name',
          'checkout_phone' => 'Phone Number',
          'checkout_newsletter' => 'Subscribe to newsletter for product updates',
          'checkout_continue_payment' => 'Continue to Payment',
          'checkout_payment_method' => 'Payment Method',
          'checkout_credit_card' => 'Credit/Debit Card',
          'checkout_credit_card_desc' => 'Visa, Mastercard, American Express',
          'checkout_paypal_desc' => 'Pay with your PayPal account',
          'checkout_card_info' => 'Card Information',
          'checkout_back' => 'Back',
          'checkout_complete_payment' => 'Complete Payment',
          'checkout_secure_title' => 'Secure Checkout',
          'checkout_ssl_encrypted' => 'SSL encrypted payment',
          'checkout_pci_compliant' => 'PCI DSS compliant',
          'checkout_instant_delivery' => 'Instant license delivery',
          # License validation page text
          'validate_title' => 'Validate License',
          'validate_description' => 'Enter your license key below to verify its status and validity. ' \
                                    'This tool only shows basic license information and does not provide ' \
                                    'access to downloads or sensitive data.',
          'validate_license_key' => 'License Key',
          'validate_placeholder' => 'Enter your license key...',
          'validate_help_text' => 'Your license key is typically provided in your purchase confirmation email.',
          'validate_button' => 'Validate License',
          'validate_valid_title' => 'Valid License',
          'validate_invalid_title' => 'Invalid License',
          'validate_valid_message' => 'This license is valid and active.',
          'validate_invalid_message' => 'License could not be validated.',
          'validate_search_again' => 'Validate Another License',
          'validate_need_account_title' => 'Need Full Access?',
          'validate_need_account_desc' => 'Create an account to manage all your licenses, download software, ' \
                                          'and access support.',
          'validate_create_account' => 'Create Account',
          'validate_have_account_title' => 'Already Have Account?',
          'validate_have_account_desc' => 'Log in to access your complete license dashboard with ' \
                                          'downloads and support.',
          'validate_sign_in' => 'Sign In',
          'validate_footer_text' => 'This validation tool only shows basic license information. For ' \
                                    'downloads and full license management, please sign in or create an account.',
          # User dashboard text
          'dashboard_welcome' => 'Welcome back',
          'dashboard_subtitle' => 'Manage your licenses and account settings',
          'dashboard_total_licenses' => 'Total Licenses',
          'dashboard_active_licenses' => 'Active Licenses',
          'dashboard_downloads' => 'Downloads',
          'dashboard_quick_actions' => 'Quick Actions',
          'dashboard_view_licenses' => 'View All Licenses',
          'dashboard_validate_license' => 'Validate License',
          'dashboard_edit_profile' => 'Edit Profile',
          'dashboard_your_licenses' => 'Your Licenses',
          'dashboard_no_licenses_title' => 'No Licenses Found',
          'dashboard_no_licenses_message' => 'You don\'t have any licenses yet. When you purchase software, ' \
                                             'your licenses will appear here.',
          'dashboard_browse_products' => 'Browse Products',
          'dashboard_view_all_licenses' => 'View All Licenses',
          # User login page text
          'login_title' => 'Sign In',
          'login_email' => 'Email Address',
          'login_password' => 'Password',
          'login_button' => 'Sign In',
          'login_create_account' => 'Create Account',
          'login_forgot_password' => 'Forgot Password',
          'login_transfer_note' => 'Don\'t have an account? Existing licenses will be automatically ' \
                                   'transferred when you create an account with the same email address.',
          'login_validate_link' => 'Just need to validate a license?',
        },
        'layout' => {
          'hero_padding' => '4rem 0',
          'section_padding' => '5rem 0',
          'container_max_width' => '1200px',
          'card_border_radius' => '10px',
          'button_border_radius' => '25px',
          'navbar_height' => 'auto',
          'footer_padding' => '2rem 0',
        },
        'features' => {
          'show_hero_animation' => true,
          'show_trust_indicators' => true,
          'show_help_widget' => true,
          'enable_auto_refresh' => true,
          'show_version_info' => false,
          'enable_dark_mode' => false,
        },
      }
    end

    # Load customizations from file
    def load_customizations
      return {} unless File.exist?(CUSTOMIZATIONS_FILE)

      begin
        YAML.safe_load_file(CUSTOMIZATIONS_FILE) || {}
      rescue StandardError => e
        puts "Error loading customizations: #{e.message}"
        {}
      end
    end

    # Deep merge two hashes, preferring values from hash_b when conflicts occur
    def deep_merge(hash_a, hash_b)
      return hash_a unless hash_b.is_a?(Hash)

      hash_a.merge(hash_b) do |_key, oldval, newval|
        if oldval.is_a?(Hash) && newval.is_a?(Hash)
          deep_merge(oldval, newval)
        else
          newval
        end
      end
    end

    # Save customizations to file
    def save_customizations(customizations)
      FileUtils.mkdir_p(File.dirname(CUSTOMIZATIONS_FILE))
      File.write(CUSTOMIZATIONS_FILE, customizations.to_yaml)
    end
  end
end

# Helper methods for templates
module CustomizationHelpers
  # Get a customization value in templates
  def custom(key, default = nil)
    TemplateCustomizer.get(key, default)
  end

  # Generate CSS custom properties from color customizations
  def custom_css_variables
    colors = TemplateCustomizer.get('colors', {})
    variables = colors.map { |key, value| "--custom-#{key.tr('_', '-')}: #{value};" }.join("\n    ")

    layout = TemplateCustomizer.get('layout', {})
    layout_vars = layout.map { |key, value| "--custom-#{key.tr('_', '-')}: #{value};" }.join("\n    ")

    ":root {\n    #{variables}\n    #{layout_vars}\n  }"
  end

  # Check if a feature is enabled
  def feature_enabled?(feature)
    TemplateCustomizer.get("features.#{feature}", false)
  end

  # Get custom color with fallback
  def custom_color(color_name, fallback = nil)
    TemplateCustomizer.get("colors.#{color_name}", fallback)
  end

  # Get custom text with fallback
  def custom_text(text_name, fallback = nil)
    TemplateCustomizer.get("text.#{text_name}", fallback)
  end

  # Apply custom styles to an element
  def custom_style(element_type)
    case element_type
    when 'hero'
      gradient_start = custom_color('hero_gradient_start', '#2c3e50')
      gradient_end = custom_color('hero_gradient_end', '#3498db')
      padding = TemplateCustomizer.get('layout.hero_padding', '4rem 0')
      "background: linear-gradient(135deg, #{gradient_start}, #{gradient_end}); padding: #{padding};"
    when 'section'
      "padding: #{TemplateCustomizer.get('layout.section_padding', '5rem 0')};"
    when 'card'
      "border-radius: #{TemplateCustomizer.get('layout.card_border_radius', '10px')};"
    when 'button'
      "border-radius: #{TemplateCustomizer.get('layout.button_border_radius', '25px')};"
    else
      ''
    end
  end
end

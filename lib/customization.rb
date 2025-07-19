# frozen_string_literal: true

# Source-License: Template Customization System
# Allows admins to customize text, colors, and positioning through the admin interface

require 'json'
require 'yaml'

class TemplateCustomizer
  CUSTOMIZATIONS_FILE = 'config/customizations.yml'

  class << self
    # Get all customizations with defaults
    def all_customizations
      default_customizations.merge(load_customizations)
    end

    # Get a specific customization value
    def get(key, default = nil)
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
    def get_all_customizations
      all_customizations
    end

    # Get categories (alias for categories)
    def get_categories
      categories
    end

    # Get customization categories for the admin interface
    def categories
      {
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
          'description' => 'Customize text content throughout the application',
          'icon' => 'fas fa-font',
        },
        'layout' => {
          'title' => 'Layout & Positioning',
          'description' => 'Customize positioning, spacing, and layout options',
          'icon' => 'fas fa-th-large',
        },
        'features' => {
          'title' => 'Features & Functionality',
          'description' => 'Enable/disable features and customize functionality',
          'icon' => 'fas fa-cogs',
        },
      }
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
        },
        'text' => {
          'hero_title' => 'Professional Software Licensing Made Simple',
          'hero_subtitle' => 'Secure, reliable, and easy-to-manage software licenses for developers and businesses. ' \
                             'Support for both one-time purchases and subscriptions with integrated payment ' \
                             'processing.',
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
          'validate_description' => 'Enter your license key below to verify its status and validity. This tool only shows basic license information and does not provide access to downloads or sensitive data.',
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
          'validate_need_account_desc' => 'Create an account to manage all your licenses, download software, and access support.',
          'validate_create_account' => 'Create Account',
          'validate_have_account_title' => 'Already Have Account?',
          'validate_have_account_desc' => 'Log in to access your complete license dashboard with downloads and support.',
          'validate_sign_in' => 'Sign In',
          'validate_footer_text' => 'This validation tool only shows basic license information. For downloads and full license management, please sign in or create an account.',
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
          'dashboard_no_licenses_message' => 'You don\'t have any licenses yet. When you purchase software, your licenses will appear here.',
          'dashboard_browse_products' => 'Browse Products',
          'dashboard_view_all_licenses' => 'View All Licenses',
          # User login page text
          'login_title' => 'Sign In',
          'login_email' => 'Email Address',
          'login_password' => 'Password',
          'login_button' => 'Sign In',
          'login_create_account' => 'Create Account',
          'login_forgot_password' => 'Forgot Password',
          'login_transfer_note' => 'Don\'t have an account? Existing licenses will be automatically transferred when you create an account with the same email address.',
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

# frozen_string_literal: true

# Source-License: Customer Helper Functions
# Provides customer-specific helper methods for templates and controllers

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

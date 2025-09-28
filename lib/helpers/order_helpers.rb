# frozen_string_literal: true

# Source-License: Order Helper Functions
# Provides order-specific helper methods for templates and controllers

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

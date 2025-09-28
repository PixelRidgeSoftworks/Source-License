# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'
require 'json'

# Customer orders
class Order < Sequel::Model
  include BaseModelMethods

  set_dataset :orders
  one_to_many :order_items
  one_to_many :licenses
  one_to_many :order_taxes

  # Parse payment details from JSON
  def payment_details_hash
    return {} unless payment_details

    JSON.parse(payment_details)
  rescue JSON::ParserError
    {}
  end

  # Set payment details as JSON
  def payment_details_hash=(hash)
    self.payment_details = hash.to_json
  end

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Get formatted subtotal (before taxes)
  def formatted_subtotal
    "$#{format('%.2f', subtotal || 0)}"
  end

  # Get formatted tax total
  def formatted_tax_total
    "$#{format('%.2f', tax_total || 0)}"
  end

  # Check order status
  def pending?
    status == 'pending'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def refunded?
    status == 'refunded'
  end

  # Mark order as completed
  def complete!
    update(status: 'completed', completed_at: Time.now)
  end

  # Mark order as refunded
  def refund!
    update(status: 'refunded', refunded_at: Time.now)
  end

  # Calculate subtotal from order items (before taxes)
  def calculate_subtotal
    order_items.sum { |item| item.price * item.quantity }
  end

  # Calculate tax total from order taxes
  def calculate_tax_total
    order_taxes.sum(&:amount)
  end

  # Calculate total (subtotal + taxes)
  def calculate_total
    calculate_subtotal + calculate_tax_total
  end

  # Apply taxes to order
  def apply_taxes!
    # Check if taxes are enabled globally
    return 0.0 unless SettingsManager.get('tax.enable_taxes')

    # Clear existing taxes
    order_taxes_dataset.delete

    subtotal_amount = calculate_subtotal
    return 0.0 if subtotal_amount <= 0

    total_tax = 0.0

    # Only apply taxes if auto-apply is enabled
    if SettingsManager.get('tax.auto_apply_taxes')
      # Apply all active taxes
      Tax.active.each do |tax|
        tax_amount = tax.calculate_amount(subtotal_amount)
        next if tax_amount <= 0

        # Round tax amount if setting is enabled
        tax_amount = tax_amount.round(2) if SettingsManager.get('tax.round_tax_amounts')

        add_order_tax(
          tax_id: tax.id,
          tax_name: tax.name,
          rate: tax.rate,
          amount: tax_amount
        )

        total_tax += tax_amount
      end
    end

    # Update order totals
    update(
      subtotal: subtotal_amount,
      tax_total: total_tax,
      amount: subtotal_amount + total_tax,
      tax_applied: true
    )

    total_tax
  end

  # Apply specific taxes to order (for manual tax application)
  def apply_specific_taxes!(tax_ids)
    # Check if taxes are enabled globally
    return 0.0 unless SettingsManager.get('tax.enable_taxes')

    # Clear existing taxes
    order_taxes_dataset.delete

    subtotal_amount = calculate_subtotal
    return 0.0 if subtotal_amount <= 0

    total_tax = 0.0

    # Apply only specified taxes
    Tax.where(id: tax_ids, status: 'active').each do |tax|
      tax_amount = tax.calculate_amount(subtotal_amount)
      next if tax_amount <= 0

      # Round tax amount if setting is enabled
      tax_amount = tax_amount.round(2) if SettingsManager.get('tax.round_tax_amounts')

      add_order_tax(
        tax_id: tax.id,
        tax_name: tax.name,
        rate: tax.rate,
        amount: tax_amount
      )

      total_tax += tax_amount
    end

    # Update order totals
    update(
      subtotal: subtotal_amount,
      tax_total: total_tax,
      amount: subtotal_amount + total_tax,
      tax_applied: true
    )

    total_tax
  end

  # Check if taxes are enabled and should be displayed
  def should_display_taxes?
    SettingsManager.get('tax.enable_taxes') && SettingsManager.get('tax.display_tax_breakdown')
  end

  # Check if prices include tax
  def tax_inclusive_pricing?
    SettingsManager.get('tax.include_tax_in_price')
  end

  # Get payment URL (would be set during payment processing)
  def payment_url
    case payment_method
    when 'stripe'
      # This would be set by Stripe payment intent
      payment_details_hash['payment_intent_url'] || payment_details_hash['payment_url']
    when 'paypal'
      # This would be set by PayPal order
      payment_details_hash['approval_url'] || payment_details_hash['payment_url']
    end
  end

  # Add order item to this order
  def add_order_item(product:, quantity:, price:)
    OrderItem.create(
      order_id: id,
      product_id: product.id,
      quantity: quantity,
      price: price
    )
  end

  # Get tax breakdown as hash
  def tax_breakdown
    order_taxes.map do |order_tax|
      {
        name: order_tax.tax_name,
        rate: order_tax.rate,
        amount: order_tax.amount,
        formatted_amount: order_tax.formatted_amount,
      }
    end
  end

  # Validation
  def validate
    super
    errors.add(:email, 'cannot be empty') if !email || email.strip.empty?
    unless /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i.match?(email)
      errors.add(:email,
                 'must be valid email format')
    end
    errors.add(:amount, 'must be greater than or equal to 0') if !amount || amount.negative?
    errors.add(:status, 'invalid status') unless %w[pending completed failed refunded].include?(status)
    errors.add(:payment_method, 'invalid payment method') unless %w[stripe paypal free manual].include?(payment_method)
  end
end

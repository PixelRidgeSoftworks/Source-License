# frozen_string_literal: true

require 'sequel'
require_relative 'base_model_methods'

class Product < Sequel::Model
  extend BaseModelMethods

  # Associations
  one_to_many :order_items
  one_to_many :orders, through: :order_items
  one_to_many :licenses
  many_to_one :product_category, key: :category_id
  many_to_one :billing_cycle_object, class: :BillingCycle, key: :billing_cycle, primary_key: :name

  # Validations
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:price, 'cannot be empty') if price.nil?
    errors.add(:category_id, 'must be selected') if !category_id || category_id.to_s.strip.empty?

    unless price.nil?
      begin
        price_float = Float(price)
        errors.add(:price, 'must be non-negative') if price_float.negative?
      rescue ArgumentError, TypeError
        errors.add(:price, 'must be a number')
      end
    end

    # Check name uniqueness
    if name && !name.strip.empty?
      existing = Product.where(name: name.strip).exclude(id: id)
      errors.add(:name, 'is already taken') if existing.any?
    end

    # Validate that category exists if provided
    return unless category_id && !category_id.to_s.strip.empty?

    errors.add(:category_id, 'does not exist') unless ProductCategory[category_id]
  end

  def before_create
    self.created_at ||= Time.now
    self.updated_at ||= Time.now
    super
  end

  def before_update
    self.updated_at = Time.now
    super
  end

  # Instance methods
  def formatted_price
    format('%.2f', price.to_f)
  end

  def active_licenses_count
    licenses_dataset.where(status: 'active').count
  end

  def total_licenses_count
    licenses.count
  end

  def total_revenue
    orders_dataset.where(status: 'completed').sum(:total) || 0
  end

  def category
    product_category
  end

  # Subscription-related methods
  def subscription?
    # Check if this product has subscription fields or is a subscription type
    respond_to?(:billing_cycle) && !billing_cycle.nil? && !billing_cycle.empty?
  end

  def billing_frequency_text
    return 'N/A' unless subscription?

    case billing_cycle&.downcase
    when 'monthly'
      'monthly billing'
    when 'yearly', 'annual'
      'annual billing'
    when 'weekly'
      'weekly billing'
    when 'daily'
      'daily billing'
    else
      "#{billing_cycle} billing"
    end
  end

  def trial?
    respond_to?(:trial_period_days) && trial_period_days&.positive?
  end

  def trial_period_text
    return 'No trial' unless trial?

    days = trial_period_days
    case days
    when 1
      '1 day'
    when 7
      '1 week'
    when 30
      '1 month'
    when (8..29)
      "#{days / 7} weeks"
    else
      "#{days} days"
    end
  end

  def formatted_setup_fee
    return '$0.00' unless respond_to?(:setup_fee) && setup_fee

    format('$%.2f', setup_fee.to_f)
  end
end

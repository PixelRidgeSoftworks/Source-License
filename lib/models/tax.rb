# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Tax configurations for orders
class Tax < Sequel::Model
  include BaseModelMethods

  set_dataset :taxes
  one_to_many :order_taxes

  # Check if tax is active
  def active?
    status == 'active'
  end

  # Get formatted rate as percentage
  def formatted_rate
    "#{format('%.2f', rate)}%"
  end

  # Calculate tax amount for a given subtotal
  def calculate_amount(subtotal)
    return 0.0 unless active? && rate.positive?

    (subtotal * rate / 100.0).round(2)
  end

  # Activate tax
  def activate!
    update(status: 'active')
  end

  # Deactivate tax
  def deactivate!
    update(status: 'inactive')
  end

  # Get all active taxes
  def self.active
    where(status: 'active').order(:name)
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:rate, 'must be greater than or equal to 0') if !rate || rate.negative?
    errors.add(:rate, 'must be less than 100') if rate && rate >= 100
    errors.add(:status, 'invalid status') unless %w[active inactive].include?(status)
  end

  # Before save hooks
  def before_save
    super
    self.name = name.strip if name
    self.status ||= 'active'
    self.created_at ||= Time.now
  end
end

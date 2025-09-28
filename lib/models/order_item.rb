# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Individual items within an order
class OrderItem < Sequel::Model
  include BaseModelMethods

  set_dataset :order_items
  many_to_one :order
  many_to_one :product

  # Calculate line total
  def total
    price * quantity
  end

  # Get formatted price
  def formatted_price
    "$#{format('%.2f', price)}"
  end

  # Get formatted total
  def formatted_total
    "$#{format('%.2f', total)}"
  end

  # Validation
  def validate
    super
    errors.add(:quantity, 'must be greater than 0') if !quantity || quantity <= 0
    errors.add(:price, 'must be greater than or equal to 0') if !price || price.negative?
  end
end

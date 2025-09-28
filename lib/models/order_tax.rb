# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Order tax tracking
class OrderTax < Sequel::Model
  include BaseModelMethods

  set_dataset :order_taxes
  many_to_one :order
  many_to_one :tax

  # Get formatted amount
  def formatted_amount
    "$#{format('%.2f', amount)}"
  end

  # Validation
  def validate
    super
    errors.add(:amount, 'must be greater than or equal to 0') if !amount || amount.negative?
    errors.add(:rate, 'must be greater than or equal to 0') if !rate || rate.negative?
  end
end

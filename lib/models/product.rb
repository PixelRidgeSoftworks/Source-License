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

  # Validations
  def validate
    super
    validates_presence %i[name price]
    validates_numeric :price, message: 'Price must be a number'
    validates_operator(:>=, 0, :price, message: 'Price must be non-negative')
    validates_unique :name
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
end

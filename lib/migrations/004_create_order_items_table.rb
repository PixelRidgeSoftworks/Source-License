# frozen_string_literal: true

# Source-License: Migration 4 - Create Order Items Table
# Creates the order_items table for managing order line items

class Migrations::CreateOrderItemsTable < BaseMigration
  VERSION = 4

  def up
    DB.create_table :order_items do
      primary_key :id
      foreign_key :order_id, :orders, null: false, on_delete: :cascade
      foreign_key :product_id, :products, null: false
      Integer :quantity, null: false, default: 1
      Decimal :price, size: [10, 2], null: false # price at time of purchase
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :order_id
      index :product_id
    end
  end
end

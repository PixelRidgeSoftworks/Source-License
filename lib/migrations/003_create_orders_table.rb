# frozen_string_literal: true

# Source-License: Migration 3 - Create Orders Table
# Creates the orders table for managing customer orders

class Migrations::CreateOrdersTable < BaseMigration
  VERSION = 3

  def up
    DB.create_table :orders do
      primary_key :id
      String :email, null: false, size: 255
      String :customer_name, size: 255 # customer's full name
      Decimal :amount, size: [10, 2], null: false
      String :currency, default: 'USD', size: 3
      String :status, null: false, default: 'pending' # pending, completed, failed, refunded
      String :payment_method, size: 50 # stripe, paypal, free, manual
      String :payment_intent_id, size: 255 # external payment ID
      String :transaction_id, size: 255 # final transaction ID
      Text :payment_details # JSON field for additional payment info
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :completed_at

      index :email
      index :status
      index :payment_intent_id
    end
  end
end

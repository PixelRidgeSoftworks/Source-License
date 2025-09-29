# frozen_string_literal: true

# Source-License: Migration 18 - Create Order Taxes Table
# Creates the order_taxes table for tracking applied taxes

class Migrations::CreateOrderTaxesTable < Migrations::BaseMigration
  VERSION = 18

  def up
    puts 'Creating order_taxes table for tracking applied taxes...'

    DB.create_table :order_taxes do
      primary_key :id
      foreign_key :order_id, :orders, null: false, on_delete: :cascade
      foreign_key :tax_id, :taxes, null: true # null if tax was deleted
      String :tax_name, null: false, size: 255 # store name for historical purposes
      Decimal :rate, size: [8, 4], null: false # store rate at time of application
      Decimal :amount, size: [10, 2], null: false # calculated tax amount
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :order_id
      index :tax_id
    end

    puts '✓ Created order_taxes table'
  end
end

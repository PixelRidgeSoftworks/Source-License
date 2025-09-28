# frozen_string_literal: true

# Source-License: Migration 11 - Add Customer Name to Orders
# Adds customer_name field to orders table

class Migrations::AddCustomerNameToOrders < BaseMigration
  VERSION = 11

  def up
    puts 'Adding customer_name field to orders table...'

    # Add customer_name field if it doesn't exist
    add_column_if_not_exists(:orders, :customer_name, String, size: 255)

    puts '✓ Added customer_name field to orders table'
  end
end

# frozen_string_literal: true

# Source-License: Migration 19 - Add Tax Fields to Orders
# Adds tax-related fields to orders table

class Migrations::AddTaxFieldsToOrders < BaseMigration
  VERSION = 19

  def up
    puts 'Adding tax fields to orders table...'

    # Add tax-related fields to orders table
    add_column_if_not_exists(:orders, :subtotal, :decimal, size: [10, 2], default: 0.00)
    add_column_if_not_exists(:orders, :tax_total, :decimal, size: [10, 2], default: 0.00)
    add_column_if_not_exists(:orders, :tax_applied, :boolean, default: false)

    # Add indexes for the new fields
    add_index_if_not_exists(:orders, :subtotal)
    add_index_if_not_exists(:orders, :tax_total)
    add_index_if_not_exists(:orders, :tax_applied)

    puts '✓ Added tax fields to orders table'
  end
end

# frozen_string_literal: true

# Source-License: Migration 20 - Add Refunded At to Orders
# Adds refunded_at field to orders table

class Migrations::AddRefundedAtToOrders < Migrations::BaseMigration
  VERSION = 20

  def up
    puts 'Adding refunded_at field to orders table...'

    # Add refunded_at field if it doesn't exist
    add_column_if_not_exists(:orders, :refunded_at, DateTime)

    # Add index for the new field
    add_index_if_not_exists(:orders, :refunded_at)

    puts '✓ Added refunded_at field to orders table'
  end
end

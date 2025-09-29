# frozen_string_literal: true

# Source-License: Migration 21 - Add Customer Name to Licenses
# Adds customer_name field to licenses table

class Migrations::AddCustomerNameToLicenses < Migrations::BaseMigration
  VERSION = 21

  def up
    puts 'Adding customer_name field to licenses table...'

    # Add customer_name field if it doesn't exist
    add_column_if_not_exists(:licenses, :customer_name, String, size: 255)

    # Add index for the new field
    add_index_if_not_exists(:licenses, :customer_name)

    puts '✓ Added customer_name field to licenses table'
  end
end

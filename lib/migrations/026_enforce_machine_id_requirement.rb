# frozen_string_literal: true

require_relative 'base_migration'

# Migration to enforce machine ID requirement for all licenses
class Migrations::EnforceMachineIdRequirement < Migrations::BaseMigration
  VERSION = 26
  # This migration enforces that all new licenses require machine IDs
  # for activation, enhancing security by preventing license sharing.
  def up
    puts 'Adding machine ID requirement to products table...'

    # First, add the requires_machine_id column to products table if it doesn't exist
    unless DB.table_exists?(:products) && DB[:products].columns.include?(:requires_machine_id)
      DB.alter_table :products do
        add_column :requires_machine_id, TrueClass, default: false
      end
      puts 'Added requires_machine_id column to products table'
    end

    puts 'Setting all products to require machine ID...'

    # Set all existing products to require machine ID
    DB[:products].update(requires_machine_id: true)

    # Set all existing licenses to require machine ID
    DB[:licenses].update(requires_machine_id: true)

    puts 'Updated all existing products and licenses to require machine ID'
    puts 'All new licenses will now require machine ID by default'
  end

  def down
    puts 'Reverting machine ID requirement...'

    # This is intentionally limited - we don't want to accidentally
    # make licenses less secure in a rollback
    puts 'WARNING: This rollback only removes the default requirement.'
    puts 'Individual licenses that were already activated with machine IDs'
    puts 'will continue to require them for security reasons.'

    # Reset products to not require machine ID (but keep existing licenses secure)
    DB[:products].update(requires_machine_id: false)

    puts 'Reverted product machine ID requirements'
  end

  def description
    'Enforce machine ID requirement for all licenses (security hardening)'
  end
end

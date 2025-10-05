# frozen_string_literal: true

# Source-License: Migration 24 - Add Machine ID Support
# Adds machine ID requirement support to licenses and stores machine IDs in license activations

class Migrations::AddMachineIdSupport < Migrations::BaseMigration
  VERSION = 24

  def up
    # Add machine ID requirement field to licenses table
    DB.alter_table :licenses do
      add_column :requires_machine_id, TrueClass, default: false
    end

    # Add machine ID field to license activations table for storing the machine ID
    DB.alter_table :license_activations do
      add_column :machine_id, String, size: 255
    end

    # Add index for machine_id lookups
    DB.add_index :license_activations, :machine_id

    # Add compound index for license_id + machine_id for uniqueness checks
    DB.add_index :license_activations, %i[license_id machine_id], name: :license_activations_license_machine_idx
  end

  def down
    # Remove indexes
    DB.drop_index :license_activations, %i[license_id machine_id], name: :license_activations_license_machine_idx
    DB.drop_index :license_activations, :machine_id

    # Remove columns
    DB.alter_table :license_activations do
      drop_column :machine_id
    end

    DB.alter_table :licenses do
      drop_column :requires_machine_id
    end
  end
end

# frozen_string_literal: true

# Source-License: Migration 27 - Add activated_at column to license_activations
# Adds the activated_at column that the activation logic expects

class Migrations::AddActivatedAtToLicenseActivations < Migrations::BaseMigration
  VERSION = 27

  def up
    # Check if column already exists before adding it
    unless DB.schema(:license_activations).any? { |col| col[0] == :activated_at }
      DB.alter_table :license_activations do
        add_column :activated_at, DateTime
      end
    end
  end

  def down
    DB.alter_table :license_activations do
      drop_column :activated_at
    end
  end
end

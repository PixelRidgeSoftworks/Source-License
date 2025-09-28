# frozen_string_literal: true

# Source-License: Migration 10 - Add Missing Product Fields
# Adds missing fields to products table

class Migrations::AddMissingProductFields < BaseMigration
  VERSION = 10

  def up
    puts 'Adding missing product fields...'

    # Add missing fields to products table
    DB.alter_table :products do
      add_column :download_url, String, size: 500 # external download URL
      add_column :file_size, String, size: 50 # display file size
      add_column :featured, :boolean, default: false # featured product flag
    end

    puts '✓ Added missing product fields'
  end
end

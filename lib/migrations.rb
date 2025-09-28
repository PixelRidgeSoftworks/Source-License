# frozen_string_literal: true

# Source-License: Database Migrations
# This file now serves as a facade to the new modular migration system

# Load the new modular migration system
require_relative 'migrations/base_migration'
require_relative 'migrations/migrations_registry'
require_relative 'migrations/migration_manager'

# Backward compatibility - delegate to new system
class Migrations
  class << self
    # Run all migrations in order using the new modular system
    def run_all
      Migrations::MigrationManager.run_all
    end
  end
end

# Auto-load all migrations when this file is required
Migrations::MigrationsRegistry.load_all_migrations

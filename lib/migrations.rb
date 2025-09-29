# frozen_string_literal: true

# Source-License: Database Migrations
# This file now serves as a facade to the new modular migration system

# Define the Migrations module first
module Migrations
  # Load the new modular migration system
  autoload :BaseMigration, File.expand_path('migrations/base_migration', __dir__)
  autoload :MigrationsRegistry, File.expand_path('migrations/migrations_registry', __dir__)
  autoload :MigrationManager, File.expand_path('migrations/migration_manager', __dir__)

  class << self
    # Run all migrations in order using the new modular system
    def run_all
      MigrationManager.run_all
    end
  end
end

# Auto-load all migrations when this file is required
Migrations::MigrationsRegistry.load_all_migrations

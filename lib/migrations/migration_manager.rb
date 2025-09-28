# frozen_string_literal: true

# Source-License: Migration Manager
# Handles orchestration of database migrations

class Migrations::MigrationManager
  class << self
    # Run all migrations in order
    def run_all
      puts 'Running database migrations...'

      create_schema_info_table

      # Load all migration files
      MigrationsRegistry.load_all_migrations

      # Run migrations in order
      MigrationsRegistry.all_migration_classes.each do |migration_class|
        migration = migration_class.new
        run_migration(migration.version, migration)
      end

      puts '✓ All migrations completed successfully'
    end

    private

    # Create schema info table to track migration versions
    def create_schema_info_table
      return if DB.table_exists?(:schema_info)

      DB.create_table :schema_info do
        Integer :version, primary_key: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      end
      puts '✓ Created schema_info table'
    end

    # Run a specific migration if it hasn't been run yet
    def run_migration(version, migration_instance)
      return if migration_exists?(version)

      puts "Running migration #{version}: #{migration_instance.class.name}"
      migration_instance.up
      record_migration(version)
      puts "✓ Migration #{version} completed"
    end

    # Check if a migration has already been run
    def migration_exists?(version)
      DB[:schema_info].where(version: version).any?
    end

    # Record that a migration has been run
    def record_migration(version)
      DB[:schema_info].insert(version: version, created_at: Time.now)
    end
  end
end

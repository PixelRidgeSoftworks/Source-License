# frozen_string_literal: true

# Source-License: Migration Manager
# Manages the execution of migrations using the registry system

class Migrations::MigrationManager
  class << self
    # Run all migrations in order
    def run_all
      puts 'Running database migrations...'

      create_schema_info_table

      # Load all migration files
      Migrations::MigrationsRegistry.load_all_migrations

      # Run migrations in order
      Migrations::MigrationsRegistry.all_migration_classes.each do |migration_class|
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

      begin
        migration_instance.up
        record_migration(version)
        puts "✓ Migration #{version} completed"
      rescue StandardError => e
        puts "✗ Migration #{version} FAILED: #{e.message}"
        puts "Error details: #{e.class.name}"
        puts "Backtrace: #{e.backtrace.first(3).join("\n")}" if e.backtrace
        puts
        puts "Migration #{version} was NOT recorded as completed due to the error."
        puts 'Please fix the migration and run it again.'

        # Re-raise the error to stop the migration process
        raise e
      end
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

# frozen_string_literal: true

# Source-License: Database Configuration
# Handles database connection setup for both MySQL and PostgreSQL

require 'sequel'
require 'logger'

class Database
  class << self
    # Set up database connection based on environment configuration
    def setup
      # Skip setup if database is already configured (e.g., in tests)
      return if defined?(DB) && DB.is_a?(Sequel::Database)

      adapter = ENV['DATABASE_ADAPTER'] || 'mysql'

      case adapter.downcase
      when 'mysql'
        setup_mysql
      when 'postgresql', 'postgres'
        setup_postgresql
      when 'sqlite'
        setup_sqlite
      else
        raise "Unsupported database adapter: #{adapter}. Supported: mysql, postgresql, sqlite"
      end

      # Configure database logging
      configure_logging

      # Run migrations if needed
      run_migrations if should_run_migrations?

      # Create default admin user if none exists
      create_default_admin if should_create_admin?
    end

    private

    # Set up MySQL connection
    def setup_mysql
      connection_string = build_mysql_connection_string

      begin
        # Connect to MySQL server first to create database if it doesn't exist
        server_db = Sequel.connect(connection_string.gsub(/\/#{database_name}$/, ''))
        server_db.run("CREATE DATABASE IF NOT EXISTS `#{database_name}`")
        server_db.disconnect

        # Connect to the actual database
        Object.const_set(:DB, Sequel.connect(connection_string))

        puts "✓ Connected to MySQL database: #{database_name}"
      rescue StandardError => e
        puts "✗ Failed to connect to MySQL: #{e.message}"
        puts 'Please ensure MySQL is running and credentials are correct'
        exit 1
      end
    end

    # Set up PostgreSQL connection
    def setup_postgresql
      connection_string = build_postgresql_connection_string

      begin
        # Connect to PostgreSQL server first to create database if it doesn't exist
        server_db = Sequel.connect(connection_string.gsub(/\/#{database_name}$/, '/postgres'))
        begin
          server_db.run("CREATE DATABASE #{database_name}")
        rescue Sequel::DatabaseError => e
          # Database might already exist, that's ok
          raise e unless e.message.include?('already exists')
        end
        server_db.disconnect

        # Connect to the actual database
        Object.const_set(:DB, Sequel.connect(connection_string))

        puts "✓ Connected to PostgreSQL database: #{database_name}"
      rescue StandardError => e
        puts "✗ Failed to connect to PostgreSQL: #{e.message}"
        puts 'Please ensure PostgreSQL is running and credentials are correct'
        exit 1
      end
    end

    # Set up SQLite connection
    def setup_sqlite
      db_file = sqlite_database_path

      begin
        # Ensure the directory exists and is writable
        dir = File.dirname(db_file)

        # Create directory if it doesn't exist
        unless Dir.exist?(dir)
          begin
            Dir.mkdir(dir)
          rescue SystemCallError => e
            puts "✗ Failed to create database directory: #{dir}"
            puts "Error: #{e.message}"
            raise e
          end
        end

        # Test if directory is writable
        test_file = File.join(dir, '.write_test')
        begin
          File.write(test_file, 'test')
          File.delete(test_file)
        rescue StandardError => e
          puts "✗ Directory is not writable: #{dir}"
          puts "Error: #{e.message}"
          raise e
        end

        # Connect to SQLite database (creates file if it doesn't exist)
        Object.const_set(:DB, Sequel.connect("sqlite://#{db_file}"))

        puts "✓ Connected to SQLite database: #{db_file}"
      rescue StandardError => e
        puts "✗ Failed to connect to SQLite: #{e.message}"
        puts "Database file path: #{db_file}"
        puts "Directory: #{File.dirname(db_file)}"
        puts
        puts 'Troubleshooting SQLite issues:'
        puts '  1. Ensure the current directory is writable'
        puts '  2. Try running as administrator (Windows) or with sudo (Linux/Mac)'
        puts '  3. Change DATABASE_NAME to a different location (e.g., /tmp/source_license.db)'
        puts
        raise e
      end
    end

    # Build MySQL connection string
    def build_mysql_connection_string
      host = ENV['DATABASE_HOST'] || 'localhost'
      port = ENV['DATABASE_PORT'] || '3306'
      username = ENV['DATABASE_USER'] || 'root'
      password = ENV['DATABASE_PASSWORD'] || ''

      "mysql2://#{username}:#{password}@#{host}:#{port}/#{database_name}?encoding=utf8"
    end

    # Build PostgreSQL connection string
    def build_postgresql_connection_string
      host = ENV['DATABASE_HOST'] || 'localhost'
      port = ENV['DATABASE_PORT'] || '5432'
      username = ENV['DATABASE_USER'] || 'postgres'
      password = ENV['DATABASE_PASSWORD'] || ''

      "postgres://#{username}:#{password}@#{host}:#{port}/#{database_name}"
    end

    # Get database name from environment
    def database_name
      ENV['DATABASE_NAME'] || 'source_license'
    end

    # Get SQLite database file path
    def sqlite_database_path
      db_name = ENV['DATABASE_NAME'] || 'source_license.db'
      # Ensure .db extension for SQLite
      db_name += '.db' unless db_name.end_with?('.db')

      # Use relative path if it's just a filename, otherwise use as-is
      if File.dirname(db_name) == '.'
        # Simple filename - use relative to current directory
        "./#{db_name}"
      else
        # Path specified - use as-is
        db_name
      end
    end

    # Configure database logging
    def configure_logging
      return unless ENV['APP_ENV'] == 'development'

      DB.loggers << Logger.new($stdout)
    end

    # Check if migrations should be run
    def should_run_migrations?
      ENV['APP_ENV'] != 'production' || ENV['RUN_MIGRATIONS'] == 'true'
    end

    # Check if default admin should be created
    def should_create_admin?
      ENV['APP_ENV'] != 'production' || ENV['CREATE_ADMIN'] == 'true'
    end

    # Run database migrations
    def run_migrations
      require_relative 'migrations'
      Migrations.run_all
    end

    # Create default admin user
    def create_default_admin
      return unless defined?(Admin)

      admin_email = ENV['ADMIN_EMAIL'] || 'admin@example.com'
      admin_password = ENV['ADMIN_PASSWORD'] || 'admin123'

      return if Admin.first(email: admin_email)

      begin
        admin = Admin.new
        admin.email = admin_email
        admin.password = admin_password # This calls the setter which hashes the password
        admin.status = 'active'
        admin.roles = 'admin'
        admin.created_at = Time.now
        admin.password_changed_at = Time.now
        admin.save_changes

        puts "✓ Default admin user created: #{admin_email}"
        puts "  Password: #{admin_password}"
      rescue StandardError => e
        puts "✗ Failed to create default admin user: #{e.message}"
        puts "  Email: #{admin_email}"
        puts "  Password: #{admin_password}"
      end
    end
  end
end

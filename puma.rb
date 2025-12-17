#!/usr/bin/env puma
# frozen_string_literal: true

# Puma configuration for Source-License
# This file is automatically loaded by Puma when using rackup

# Set the environment
environment ENV.fetch('APP_ENV', 'development')

# Bind to host and port
bind "tcp://#{ENV.fetch('APP_HOST', '0.0.0.0')}:#{ENV.fetch('APP_PORT', '4567')}"

# Workers and threads configuration
# Check if we're on Windows - workers (clustering) not supported on Windows
is_windows = RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/

if is_windows
  # Windows: Use single mode with more threads for better concurrency
  puts '🔧 Windows detected - using single mode with enhanced threading'

  if ENV['APP_ENV'] == 'production'
    # Production on Windows: Use many threads for concurrency
    threads_count = ENV.fetch('RAILS_MAX_THREADS', 64).to_i
    threads 16, threads_count
  else
    # Development on Windows: Use moderate threading
    threads_count = ENV.fetch('RAILS_MAX_THREADS', 32).to_i
    threads 8, threads_count
  end

else
  # Unix/Linux/macOS: Use workers for better concurrency
  puts '🔧 Unix-like system detected - using clustered mode with workers'

  workers ENV.fetch('WEB_WORKERS', 2).to_i

  if ENV['APP_ENV'] == 'production'
    # Production: Use 2 workers with more threads for better concurrency
    threads_count = ENV.fetch('RAILS_MAX_THREADS', 32).to_i
    threads 8, threads_count

    # Preload application for better memory usage with workers
    preload_app!

    # Handle worker fork for database connections
    on_worker_boot do
      # Reconnect to database after fork
      Database.reconnect if defined?(Database) && Database.respond_to?(:reconnect)

      # Clear any cached connections or objects
      if defined?(DB)
        DB.disconnect
        require_relative 'lib/database'
        Database.setup
      end
    end

    # Clean up resources before fork
    before_fork do
      # Close database connections before forking
      DB.disconnect if defined?(DB)
    end

  else
    # Development: Use 2 workers with moderate threading
    threads_count = ENV.fetch('RAILS_MAX_THREADS', 16).to_i
    threads 4, threads_count

    # Preload application for faster startup
    preload_app!

    # Clean up resources before fork (prevents SQLite fork warning)
    before_fork do
      DB.disconnect if defined?(DB)
    end

    # Enable worker fork handling even in development
    on_worker_boot do
      Database.reconnect if defined?(Database) && Database.respond_to?(:reconnect)

      if defined?(DB)
        DB.disconnect
        require_relative 'lib/database'
        Database.setup
      end
    end
  end
end

# Tag for process identification
tag ENV.fetch('PUMA_TAG', 'source-license')

# Logging
quiet false

puts '🚀 Puma configuration loaded from puma.rb'

if is_windows
  if ENV['APP_ENV'] == 'production'
    puts "   Mode: Single (Windows) with #{ENV.fetch('RAILS_MAX_THREADS', 64)} max threads"
    puts "   Threads: 16-#{ENV.fetch('RAILS_MAX_THREADS', 64)}"
  else
    puts "   Mode: Single (Windows) with #{ENV.fetch('RAILS_MAX_THREADS', 32)} max threads"
    puts "   Threads: 8-#{ENV.fetch('RAILS_MAX_THREADS', 32)}"
  end
else
  puts "   Mode: Clustered with #{ENV.fetch('WEB_WORKERS', 2)} workers"
  if ENV['APP_ENV'] == 'production'
    puts "   Threads: 8-#{ENV.fetch('RAILS_MAX_THREADS', 32)} per worker"
  else
    puts "   Threads: 4-#{ENV.fetch('RAILS_MAX_THREADS', 16)} per worker"
  end
end

puts "   Environment: #{ENV['APP_ENV'] || 'development'}"
puts "   Platform: #{is_windows ? 'Windows' : 'Unix-like'}"

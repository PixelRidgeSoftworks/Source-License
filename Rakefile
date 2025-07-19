# frozen_string_literal: true

# Rakefile for Source License Management System
# Provides convenient tasks for development, testing, and deployment

require 'rake'
require 'rake/testtask'

# Default task
task default: [:test]

# Test tasks
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
  t.warning = false
end

# Individual test tasks
namespace :test do
  Rake::TestTask.new(:models) do |t|
    t.libs << 'test'
    t.libs << 'lib'
    t.test_files = FileList['test/models_test.rb']
    t.verbose = true
  end

  Rake::TestTask.new(:app) do |t|
    t.libs << 'test'
    t.libs << 'lib'
    t.test_files = FileList['test/app_test.rb']
    t.verbose = true
  end

  Rake::TestTask.new(:helpers) do |t|
    t.libs << 'test'
    t.libs << 'lib'
    t.test_files = FileList['test/helpers_test.rb']
    t.verbose = true
  end

  Rake::TestTask.new(:customization) do |t|
    t.libs << 'test'
    t.libs << 'lib'
    t.test_files = FileList['test/customization_test.rb']
    t.verbose = true
  end

  desc 'Run all tests with coverage'
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task['test'].invoke
  end
end

# RuboCop tasks
begin
  require 'rubocop/rake_task'

  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ['--display-cop-names']
  end

  namespace :rubocop do
    desc 'Auto-correct RuboCop offenses'
    RuboCop::RakeTask.new(:autocorrect) do |task|
      task.options = ['--auto-correct']
    end

    desc 'Auto-correct RuboCop offenses (safe only)'
    RuboCop::RakeTask.new(:autocorrect_safe) do |task|
      task.options = ['--auto-correct', '--safe']
    end

    desc 'Check specific files'
    task :check, [:files] do |_task, args|
      files = args[:files] || 'app.rb lib/'
      system("bundle exec rubocop #{files}")
    end
  end
rescue LoadError
  desc 'RuboCop not available'
  task :rubocop do
    puts 'RuboCop not available. Install with: gem install rubocop'
  end
end

# Database tasks
namespace :db do
  desc 'Create database and run migrations'
  task :setup do
    puts 'Setting up database...'
    ruby 'lib/migrations.rb'
    puts 'Database setup complete!'
  end

  desc 'Run database migrations'
  task :migrate do
    puts 'Running migrations...'
    ruby 'lib/migrations.rb'
    puts 'Migrations complete!'
  end

  desc 'Reset database (drop and recreate)'
  task :reset do
    puts 'Resetting database...'
    ENV['RESET_DB'] = 'true'
    ruby 'lib/migrations.rb'
    puts 'Database reset complete!'
  end

  desc 'Seed database with sample data'
  task :seed do
    puts 'Seeding database...'
    require_relative 'test/test_helper'

    # Create sample admin
    admin = Admin.create(
      email: ENV['ADMIN_EMAIL'] || 'admin@example.com',
      password_hash: BCrypt::Password.create(ENV['ADMIN_PASSWORD'] || 'admin123')
    )
    puts "Created admin: #{admin.email}"

    # Create sample products
    products = [
      {
        name: 'Professional IDE License',
        description: 'Full-featured development environment for professional developers.',
        price: 199.99,
        max_activations: 3,
        version: '2024.1',
        download_file: 'professional-ide.zip',
        features: ['Syntax highlighting', 'IntelliSense', 'Git integration', 'Plugin support'].to_json,
      },
      {
        name: 'Code Editor Pro',
        description: 'Lightweight but powerful code editor for developers.',
        price: 49.99,
        max_activations: 5,
        version: '1.5.2',
        download_file: 'code-editor-pro.zip',
        features: ['Multi-language support', 'Themes', 'Extensions', 'Live preview'].to_json,
      },
      {
        name: 'Developer Tools Suite',
        description: 'Complete toolkit for modern web development.',
        price: 29.99,
        max_activations: 10,
        version: '3.0.1',
        download_file: 'dev-tools-suite.zip',
        features: ['Browser dev tools', 'API testing', 'Performance monitoring', 'Deployment tools'].to_json,
        subscription: true,
      },
    ]

    products.each do |product_data|
      product = Product.create(product_data)
      puts "Created product: #{product.name} ($#{product.price})"
    end

    puts 'Database seeding complete!'
  end
end

# Application tasks
namespace :app do
  desc 'Start the application server'
  task :server do
    puts 'Starting Source License server...'
    exec 'ruby launch.rb'
  end

  desc 'Start with auto-reload for development'
  task :dev do
    if system('which rerun > /dev/null')
      puts 'Starting development server with auto-reload...'
      exec 'rerun "ruby launch.rb"'
    else
      puts 'Rerun gem not found. Install with: gem install rerun'
      puts 'Starting regular server...'
      Rake::Task['app:server'].invoke
    end
  end

  desc 'Check application health'
  task :health do
    require_relative 'app'

    puts 'Checking application health...'

    # Check database connection
    begin
      require_relative 'lib/database'
      Database.setup
      puts '✓ Database connection successful'
    rescue StandardError => e
      puts "✗ Database connection failed: #{e.message}"
    end

    # Check required environment variables
    required_vars = %w[APP_SECRET]
    missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

    if missing_vars.empty?
      puts '✓ Required environment variables present'
    else
      puts "✗ Missing environment variables: #{missing_vars.join(', ')}"
    end

    # Check optional but recommended variables
    optional_vars = %w[STRIPE_SECRET_KEY PAYPAL_CLIENT_ID SMTP_HOST]
    configured_vars = optional_vars.select { |var| ENV.fetch(var, nil) && !ENV[var].empty? }

    puts "Optional integrations configured: #{configured_vars.join(', ')}" unless configured_vars.empty?
    puts 'No optional integrations configured' if configured_vars.empty?

    puts 'Health check complete!'
  end
end

# Development tasks
namespace :dev do
  desc 'Setup development environment'
  task :setup do
    puts 'Setting up development environment...'

    # Install dependencies
    puts 'Installing gems...'
    system('bundle install')

    # Setup database
    Rake::Task['db:setup'].invoke

    # Create .env file if it doesn't exist
    unless File.exist?('.env')
      puts 'Creating .env file from example...'
      require 'fileutils'
      FileUtils.cp('.env.example', '.env')
      puts 'Please edit .env file with your configuration'
    end

    puts 'Development environment setup complete!'
    puts ''
    puts 'Next steps:'
    puts '1. Edit .env file with your configuration'
    puts '2. Run: rake db:seed (to add sample data)'
    puts '3. Run: rake app:dev (to start development server)'
  end

  desc 'Run full development checks'
  task :check do
    puts 'Running development checks...'

    puts "\n1. Running RuboCop..."
    Rake::Task['rubocop'].invoke

    puts "\n2. Running tests..."
    Rake::Task['test'].invoke

    puts "\n3. Checking application health..."
    Rake::Task['app:health'].invoke

    puts "\nAll checks complete!"
  end

  desc 'Clean up development files'
  task :clean do
    puts 'Cleaning up development files...'

    # Remove test database
    FileUtils.rm_f('test.db')

    # Remove coverage reports
    FileUtils.rm_rf('coverage')

    # Remove log files
    FileUtils.rm_rf('log')

    # Remove temporary files
    FileUtils.rm_rf('tmp')

    # Remove customizations file
    FileUtils.rm_f('config/customizations.yml')

    puts 'Cleanup complete!'
  end
end

# Documentation tasks
namespace :docs do
  desc 'Generate API documentation'
  task :api do
    puts 'Generating API documentation...'

    api_docs = {
      'API Endpoints' => {
        'Authentication' => 'POST /api/auth',
        'License Validation' => 'GET /api/license/:key/validate',
        'License Activation' => 'POST /api/license/:key/activate',
        'Order Creation' => 'POST /api/orders',
        'Order Status' => 'GET /api/orders/:id',
        'Webhooks' => 'POST /api/webhook/:provider',
      },
      'Admin Routes' => {
        'Dashboard' => 'GET /admin',
        'Products' => 'GET /admin/products',
        'Licenses' => 'GET /admin/licenses',
        'Settings' => 'GET /admin/settings',
        'Customization' => 'GET /admin/customize',
        'Code Guide' => 'GET /admin/customize/code-guide',
      },
      'Public Routes' => {
        'Homepage' => 'GET /',
        'Product Details' => 'GET /product/:id',
        'License Lookup' => 'GET /my-licenses',
        'Cart' => 'GET /cart',
        'Checkout' => 'GET /checkout',
      },
    }

    File.open('API_DOCUMENTATION.md', 'w') do |f|
      f.puts '# Source License API Documentation'
      f.puts ''

      api_docs.each do |section, endpoints|
        f.puts "## #{section}"
        f.puts ''
        endpoints.each do |name, route|
          f.puts "- **#{name}**: `#{route}`"
        end
        f.puts ''
      end
    end

    puts 'API documentation generated: API_DOCUMENTATION.md'
  end

  desc 'Generate test coverage report'
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task['test'].invoke
    puts 'Coverage report generated in coverage/index.html'
  end
end

# Production tasks
namespace :production do
  desc 'Prepare for production deployment'
  task :prepare do
    puts 'Preparing for production deployment...'

    # Check for required environment variables
    required_vars = %w[APP_SECRET DATABASE_URL]
    missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

    unless missing_vars.empty?
      puts "Error: Missing required environment variables: #{missing_vars.join(', ')}"
      exit 1
    end

    # Run tests
    puts 'Running tests...'
    Rake::Task['test'].invoke

    # Run RuboCop
    puts 'Running code quality checks...'
    Rake::Task['rubocop'].invoke

    # Run migrations
    puts 'Running database migrations...'
    Rake::Task['db:migrate'].invoke

    puts 'Production preparation complete!'
  end

  desc 'Check production readiness'
  task :check do
    puts 'Checking production readiness...'

    checks = [
      ['Environment variables', -> { ENV.fetch('APP_SECRET', nil) && ENV.fetch('DATABASE_URL', nil) }],
      ['Database connection', -> {
        begin
          require_relative 'lib/database'
          Database.setup
          true
        rescue StandardError
          false
        end
      },],
      ['Payment configuration', -> { ENV['STRIPE_SECRET_KEY'] || ENV.fetch('PAYPAL_CLIENT_ID', nil) }],
      ['Email configuration', -> { ENV.fetch('SMTP_HOST', nil) }],
    ]

    checks.each do |name, check|
      result = check.call
      puts "#{result ? '✓' : '✗'} #{name}"
    end

    puts 'Production readiness check complete!'
  end
end

# Help task
desc 'Show available tasks'
task :help do
  puts 'Source License Management System - Available Tasks:'
  puts ''
  puts 'Development:'
  puts '  rake dev:setup          - Setup development environment'
  puts '  rake dev:check          - Run all development checks'
  puts '  rake dev:clean          - Clean up development files'
  puts ''
  puts 'Testing:'
  puts '  rake test               - Run all tests'
  puts '  rake test:models        - Run model tests'
  puts '  rake test:app           - Run application tests'
  puts '  rake test:coverage      - Run tests with coverage'
  puts ''
  puts 'Code Quality:'
  puts '  rake rubocop            - Run RuboCop linter'
  puts '  rake rubocop:autocorrect - Auto-fix RuboCop issues'
  puts ''
  puts 'Database:'
  puts '  rake db:setup           - Setup database'
  puts '  rake db:migrate         - Run migrations'
  puts '  rake db:seed            - Add sample data'
  puts '  rake db:reset           - Reset database'
  puts ''
  puts 'Application:'
  puts '  rake app:server         - Start server'
  puts '  rake app:dev            - Start development server'
  puts '  rake app:health         - Check application health'
  puts ''
  puts 'Production:'
  puts '  rake production:prepare - Prepare for deployment'
  puts '  rake production:check   - Check production readiness'
  puts ''
  puts 'Documentation:'
  puts '  rake docs:api           - Generate API docs'
  puts '  rake docs:coverage      - Generate coverage report'
end

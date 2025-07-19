#!/usr/bin/env ruby
# frozen_string_literal: true

# Test runner script for Source License System
# Provides a simple way to run tests and demonstrate functionality

require 'fileutils'

puts '=' * 60
puts 'Source License Management System - Test Runner'
puts '=' * 60
puts ''

# Check if we're in the right directory
unless File.exist?('app.rb') && File.exist?('Gemfile')
  puts 'Error: Please run this script from the project root directory'
  exit 1
end

# Function to run command and show output
def run_command(description, command)
  puts "#{description}..."
  puts "Running: #{command}"
  puts '-' * 40

  success = system(command)

  puts ''
  if success
    puts "✓ #{description} completed successfully"
  else
    puts "✗ #{description} failed"
  end

  puts ''
  success
end

# Function to check file exists
def file_exists?(path, description)
  if File.exist?(path)
    puts "✓ #{description}: #{path}"
    true
  else
    puts "✗ #{description} missing: #{path}"
    false
  end
end

# Function to show test summary
def show_test_summary
  puts '=' * 60
  puts 'TEST SUMMARY'
  puts '=' * 60

  test_files = Dir.glob('test/*_test.rb')
  puts "Test files found: #{test_files.length}"
  test_files.each { |file| puts "  - #{file}" }

  puts ''
  puts 'Key components tested:'
  puts '  - Database models and associations'
  puts '  - Web application routes and responses'
  puts '  - Template helpers and utilities'
  puts '  - Customization system functionality'
  puts '  - License generation and validation'
  puts '  - Admin authentication and authorization'
  puts '  - API endpoints and JSON responses'
  puts ''
end

# Start the test process
puts 'Starting comprehensive test suite...'
puts ''

# 1. Check project structure
puts '1. Checking project structure...'
files_to_check = [
  ['app.rb', 'Main application file'],
  ['Gemfile', 'Gem dependencies'],
  ['.rubocop.yml', 'RuboCop configuration'],
  ['Rakefile', 'Rake tasks'],
  ['test/test_helper.rb', 'Test helper'],
  ['test/factories.rb', 'Test factories'],
  ['lib/customization.rb', 'Customization system'],
  ['lib/models.rb', 'Database models'],
  ['lib/helpers.rb', 'Template helpers'],
]

all_files_present = true
files_to_check.each do |path, desc|
  all_files_present &= file_exists?(path, desc)
end

puts ''
if all_files_present
  puts '✓ All required files present'
else
  puts '✗ Some required files are missing'
  puts 'Please ensure all files have been created properly'
  exit 1
end

puts ''

# 2. Install dependencies (if needed)
if File.exist?('Gemfile.lock')
  puts '2. Dependencies already installed (Gemfile.lock exists)'
  puts ''
else
  puts '2. Installing dependencies...'
  unless run_command('Bundle install', 'bundle install')
    puts 'Failed to install dependencies. Please run "bundle install" manually.'
    exit 1
  end
end

# 3. Run RuboCop for code quality
puts '3. Running code quality checks...'
rubocop_success = run_command('RuboCop code analysis', 'bundle exec rubocop --format simple')

# 4. Setup test environment
puts '4. Setting up test environment...'
ENV['APP_ENV'] = 'test'
ENV['RACK_ENV'] = 'test'

# Clean up any existing test files
FileUtils.rm_f('test.db')
FileUtils.rm_rf('coverage')

puts 'Test environment prepared'
puts ''

# 5. Run the test suite
puts '5. Running comprehensive test suite...'
puts ''

test_commands = [
  ['Model tests', 'bundle exec ruby -Itest test/models_test.rb'],
  ['Application tests', 'bundle exec ruby -Itest test/app_test.rb'],
  ['Helper tests', 'bundle exec ruby -Itest test/helpers_test.rb'],
  ['Customization tests', 'bundle exec ruby -Itest test/customization_test.rb'],
]

test_results = []

test_commands.each do |description, command|
  success = run_command(description, command)
  test_results << [description, success]
end

# 6. Show results
puts '=' * 60
puts 'FINAL RESULTS'
puts '=' * 60

puts ''
puts 'Code Quality:'
puts rubocop_success ? '✓ RuboCop passed' : '✗ RuboCop found issues'

puts ''
puts 'Test Results:'
test_results.each do |description, success|
  puts "#{success ? '✓' : '✗'} #{description}"
end

all_tests_passed = test_results.all? { |_, success| success }

puts ''
if all_tests_passed && rubocop_success
  puts '🎉 ALL TESTS PASSED! 🎉'
  puts ''
  puts 'The Source License Management System is working correctly!'
  puts ''
  puts 'Key features verified:'
  puts '✓ Database models and relationships'
  puts '✓ License generation and validation'
  puts '✓ Web interface and API endpoints'
  puts '✓ Admin authentication and management'
  puts '✓ Template customization system'
  puts '✓ Helper functions and utilities'
  puts '✓ Error handling and edge cases'
  puts ''
  puts 'Next steps:'
  puts '1. Run: rake dev:setup (to setup development environment)'
  puts '2. Run: rake db:seed (to add sample data)'
  puts '3. Run: rake app:dev (to start the development server)'
  puts '4. Visit: http://localhost:4567 (to see the application)'
else
  puts '❌ SOME TESTS FAILED'
  puts ''
  puts 'Please review the output above and fix any issues.'
  puts ''
  puts 'Common solutions:'
  puts '- Run: bundle install (if dependencies are missing)'
  puts '- Check: .env file configuration'
  puts '- Ensure: All required files are present'
  puts '- Review: Error messages in the test output'
end

puts ''
show_test_summary

# 7. Generate coverage report if SimpleCov is available
if File.exist?('coverage/index.html')
  puts '📊 Test coverage report available: coverage/index.html'
  puts ''
end

# 8. Show available rake tasks
puts 'Available Rake tasks:'
puts '  rake test              - Run all tests'
puts '  rake rubocop           - Run code quality checks'
puts '  rake dev:setup         - Setup development environment'
puts '  rake app:dev           - Start development server'
puts '  rake db:seed           - Add sample data'
puts '  rake help              - Show all available tasks'

puts ''
puts 'Test run completed!'

# Exit with appropriate code
exit(all_tests_passed && rubocop_success ? 0 : 1)

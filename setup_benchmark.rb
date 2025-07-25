#!/usr/bin/env ruby
# frozen_string_literal: true

# Setup script for API benchmarking dependencies

puts '🔧 Setting up API benchmark dependencies...'
puts

# Check for required gems
required_gems = ['concurrent-ruby']
missing_gems = []

required_gems.each do |gem_name|
  require gem_name.tr('-', '/')
  puts "✅ #{gem_name} already installed"
rescue LoadError
  missing_gems << gem_name
  puts "❌ #{gem_name} not found"
end

puts
if missing_gems.any?
  puts 'Installing missing gems...'
  missing_gems.each do |gem_name|
    puts "Installing #{gem_name}..."
    system("gem install #{gem_name}")
  end
else
  puts '✅ All dependencies are already installed!'
end

puts
puts '🚀 Ready to benchmark!'
puts
puts 'Usage Examples:'
puts '  Basic benchmark:     ruby benchmark_api.rb'
puts '  Custom host/port:    ruby benchmark_api.rb --host localhost --port 4567'
puts '  More requests:       ruby benchmark_api.rb --requests 500 --threads 20'
puts '  Verbose output:      ruby benchmark_api.rb --verbose'
puts
puts 'Before running benchmarks:'
puts '  1. Start your server: ruby app.rb'
puts '  2. Wait for it to be ready'
puts '  3. Run: ruby benchmark_api.rb'
puts

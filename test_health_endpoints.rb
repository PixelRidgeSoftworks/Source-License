#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify health check endpoints are working
# Usage: ruby test_health_endpoints.rb [host] [port]

require 'net/http'
require 'json'
require 'uri'

class HealthCheckTester
  def initialize(host = 'localhost', port = 4567)
    @host = host
    @port = port
    @base_url = "http://#{@host}:#{@port}"
  end

  def run_tests
    puts 'Testing Source-License Health Check Endpoints'
    puts '=' * 50
    puts "Target: #{@base_url}"
    puts

    test_health_endpoint
    puts
    test_readiness_endpoint
    puts
    test_invalid_methods
    puts

    puts 'Health check tests completed!'
  end

  private

  def test_health_endpoint
    puts 'Testing /health endpoint...'

    begin
      response = make_request('/health')

      if response.code == '200'
        data = JSON.parse(response.body)
        puts '✅ Health check PASSED'
        puts "   Status: #{data['status']}"
        puts "   Version: #{data['version']}"
        puts "   Environment: #{data['environment']}"
        puts "   Database: #{data['database']}"
        puts "   Uptime: #{data['uptime']} seconds"

        if data['monitoring']
          puts '   Monitoring Config:'
          puts "     Error Tracking: #{data['monitoring']['error_tracking']}"
          puts "     Security Webhooks: #{data['monitoring']['security_webhooks']}"
          puts "     Log Format: #{data['monitoring']['log_format']}"
          puts "     Log Level: #{data['monitoring']['log_level']}"
        end
      else
        puts '❌ Health check FAILED'
        puts "   HTTP Status: #{response.code}"
        puts "   Response: #{response.body}"
      end
    rescue StandardError => e
      puts "❌ Health check ERROR: #{e.message}"
    end
  end

  def test_readiness_endpoint
    puts 'Testing /ready endpoint...'

    begin
      response = make_request('/ready')

      if %w[200 503].include?(response.code)
        data = JSON.parse(response.body)
        puts '✅ Readiness check RESPONDED'
        puts "   Overall Status: #{data['status']}"
        puts "   Version: #{data['version']}"
        puts "   Environment: #{data['environment']}"

        if data['summary']
          summary = data['summary']
          puts '   Summary:'
          puts "     Total Checks: #{summary['total_checks']}"
          puts "     OK: #{summary['ok']}"
          puts "     Warnings: #{summary['warnings']}"
          puts "     Errors: #{summary['errors']}"
        end

        if data['checks']
          puts '   Individual Checks:'
          data['checks'].each do |check_name, check_data|
            status_icon = case check_data['status']
                          when 'ok' then '✅'
                          when 'warning' then '⚠️ '
                          when 'error' then '❌'
                          when 'disabled' then '⏸️ '
                          else '❓'
                          end
            puts "     #{status_icon} #{check_name}: #{check_data['message']}"
          end
        end
      else
        puts '❌ Readiness check FAILED'
        puts "   HTTP Status: #{response.code}"
        puts "   Response: #{response.body}"
      end
    rescue StandardError => e
      puts "❌ Readiness check ERROR: #{e.message}"
    end
  end

  def test_invalid_methods
    puts 'Testing invalid HTTP methods...'

    %w[POST PUT DELETE PATCH].each do |method|
      uri = URI("#{@base_url}/health")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP.const_get(method.capitalize).new(uri.path)
      response = http.request(request)

      if response.code == '405'
        puts "✅ #{method} /health correctly rejected (405)"
      else
        puts "❌ #{method} /health unexpected response: #{response.code}"
      end
    rescue StandardError => e
      puts "❌ #{method} /health error: #{e.message}"
    end
  end

  def make_request(path)
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.path)
    request['Accept'] = 'application/json'

    http.request(request)
  end
end

# Command line interface
if __FILE__ == $0
  host = ARGV[0] || 'localhost'
  port = (ARGV[1] || 4567).to_i

  puts 'Source-License Health Check Endpoint Tester'
  puts "Testing endpoints at #{host}:#{port}"
  puts

  tester = HealthCheckTester.new(host, port)
  tester.run_tests
end

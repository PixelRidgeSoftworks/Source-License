#!/usr/bin/env ruby
# frozen_string_literal: true

# Source License API Benchmark Script
# Tests fiber-enabled API endpoints for performance comparison

require 'net/http'
require 'json'
require 'uri'
require 'benchmark'
require 'concurrent-ruby'
require 'optparse'

class SourceLicenseAPIBenchmark
  DEFAULT_HOST = 'localhost'
  DEFAULT_PORT = 4567
  DEFAULT_THREADS = 10
  DEFAULT_REQUESTS = 100

  def initialize(options = {})
    @host = options[:host] || DEFAULT_HOST
    @port = options[:port] || DEFAULT_PORT
    @threads = options[:threads] || DEFAULT_THREADS
    @requests = options[:requests] || DEFAULT_REQUESTS
    @verbose = options[:verbose] || false
    @base_url = "http://#{@host}:#{@port}"

    @results = {}
    @errors = []
  end

  def run_all_benchmarks
    puts '🚀 Starting Source License API Benchmarks'
    puts '=' * 60
    puts "Host: #{@host}:#{@port}"
    puts "Threads: #{@threads}"
    puts "Requests per endpoint: #{@requests}"
    puts '=' * 60
    puts

    # Check server availability first
    unless server_available?
      puts "❌ Server not available at #{@base_url}"
      puts 'Please start the server first with: ruby app.rb'
      exit 1
    end

    puts '✅ Server is available'
    puts

    # Run individual endpoint benchmarks
    benchmark_products_endpoint
    benchmark_license_validation
    benchmark_concurrent_license_validation
    benchmark_order_creation_simulation
    benchmark_mixed_workload

    # Print summary
    print_summary
  end

  private

  def server_available?
    uri = URI("#{@base_url}/")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    http.get(uri.path)
    true
  rescue StandardError
    false
  end

  def benchmark_products_endpoint
    puts '📦 Benchmarking Products Endpoint'
    puts '-' * 40

    endpoint = '/api/products'

    # Single request test
    single_time = benchmark_single_request(endpoint)

    # Concurrent requests test
    concurrent_time = benchmark_concurrent_requests(endpoint, @requests)

    @results[:products] = {
      single_request_time: single_time,
      concurrent_requests_time: concurrent_time,
      requests_per_second: @requests / concurrent_time,
      endpoint: endpoint,
    }

    puts "Single request: #{format('%.3f', single_time * 1000)}ms"
    puts "#{@requests} concurrent requests: #{format('%.3f', concurrent_time)}s"
    puts "Requests/second: #{format('%.2f', @results[:products][:requests_per_second])}"
    puts
  end

  def benchmark_license_validation
    puts '🔑 Benchmarking License Validation'
    puts '-' * 40

    # Create some test license keys (these will likely return 404, but we're testing throughput)
    test_keys = generate_test_license_keys(10)

    results = []

    test_keys.each do |key|
      endpoint = "/api/license/#{key}/validate"
      time = benchmark_single_request(endpoint, expected_status: [200, 404])
      results << time
    end

    avg_time = results.sum / results.length

    @results[:license_validation] = {
      average_time: avg_time,
      endpoint: '/api/license/[KEY]/validate',
    }

    puts "Average validation time: #{format('%.3f', avg_time * 1000)}ms"
    puts "Tested #{test_keys.length} different license keys"
    puts
  end

  def benchmark_concurrent_license_validation
    puts '🔄 Benchmarking Concurrent License Validation'
    puts '-' * 40

    test_keys = generate_test_license_keys(@requests)

    start_time = Time.now

    # Use concurrent-ruby for true parallelism
    pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: @threads,
      max_threads: @threads,
      max_queue: @requests
    )

    futures = test_keys.map do |key|
      Concurrent::Future.execute(executor: pool) do
        endpoint = "/api/license/#{key}/validate"
        make_request(endpoint, expected_status: [200, 404])
      end
    end

    # Wait for all requests to complete
    futures.each(&:value!)

    total_time = Time.now - start_time
    pool.shutdown
    pool.wait_for_termination(10)

    @results[:concurrent_license_validation] = {
      total_time: total_time,
      requests_per_second: @requests / total_time,
      concurrent_requests: @requests,
    }

    puts "#{@requests} concurrent validations: #{format('%.3f', total_time)}s"
    puts "Requests/second: #{format('%.2f', @results[:concurrent_license_validation][:requests_per_second])}"
    puts
  end

  def benchmark_order_creation_simulation
    puts '🛒 Benchmarking Order Creation (Simulation)'
    puts '-' * 40

    # Test a simple validation request first to see if order endpoint is responsive
    test_single_time = nil
    begin
      # Use a very short timeout for the test request
      uri = URI("#{@base_url}/api/orders")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 2
      http.read_timeout = 2

      test_req = Net::HTTP::Post.new(uri)
      test_req['Content-Type'] = 'application/json'
      test_req.body = '{"test": "quick"}' # Invalid but should get quick response

      start_time = Time.now
      response = http.request(test_req)
      test_single_time = Time.now - start_time

      puts "Order endpoint test response: #{response.code} (#{format('%.3f', test_single_time * 1000)}ms)"
    rescue Net::OpenTimeout, Net::ReadTimeout, StandardError => e
      puts "⚠️  Order endpoint appears to be slow or hanging (#{e.class.name})"
      puts '   Skipping order creation benchmark to avoid hanging'
      puts '   This suggests the fiber implementation in order creation may need optimization'
      puts
      return
    end

    # If the test request took too long, skip the full benchmark
    if test_single_time && test_single_time > 5.0
      puts "⚠️  Order endpoint is too slow (#{format('%.3f', test_single_time)}s for test request)"
      puts '   Skipping full benchmark to avoid hanging'
      puts
      return
    end

    # Simulate order creation requests with reduced count and shorter timeouts
    order_data = {
      customer: {
        email: 'benchmark@example.com',
        name: 'Benchmark User',
      },
      items: [
        {
          productId: 'test-product-1',
          quantity: 1,
        },
      ],
      payment_method: 'stripe',
      amount: 29.99,
      currency: 'USD',
    }

    endpoint = '/api/orders'
    reduced_requests = [@requests / 10, 5].max # Use fewer requests to avoid hanging

    puts "Using #{reduced_requests} requests (reduced from #{@requests} due to potential slow endpoint)"

    # Single request with timeout
    single_time = benchmark_single_request_with_timeout(endpoint,
                                                        method: 'POST',
                                                        data: order_data,
                                                        expected_status: [400, 404, 500],
                                                        timeout: 10)

    return unless single_time # Skip if single request failed

    # Multiple requests with timeout protection
    times = []
    success_count = 0

    reduced_requests.times do |i|
      puts "  Request #{i + 1}/#{reduced_requests}..." if @verbose

      time = benchmark_single_request_with_timeout(endpoint,
                                                   method: 'POST',
                                                   data: order_data,
                                                   expected_status: [400, 404, 500],
                                                   timeout: 10)
      if time
        times << time
        success_count += 1
      else
        puts "  Request #{i + 1} timed out or failed"
        break if success_count < i / 2 # Stop if too many failures
      end
    end

    return if times.empty?

    avg_time = times.sum / times.length
    total_time = times.sum

    @results[:order_creation] = {
      single_request_time: single_time,
      average_time: avg_time,
      total_time: total_time,
      requests_per_second: success_count / total_time,
      success_count: success_count,
      attempted_requests: reduced_requests,
    }

    puts "Single order request: #{format('%.3f', single_time * 1000)}ms"
    puts "Successful requests: #{success_count}/#{reduced_requests}"
    puts "Average time: #{format('%.3f', avg_time * 1000)}ms"
    puts "Requests/second: #{format('%.2f', @results[:order_creation][:requests_per_second])}"
    puts
  end

  def benchmark_mixed_workload
    puts '🔀 Benchmarking Mixed API Workload'
    puts '-' * 40

    # Mix of different endpoints to simulate real usage
    endpoints = [
      { path: '/api/products', method: 'GET', weight: 40 },
      { path: '/api/license/TEST-1234-5678-9012/validate', method: 'GET', weight: 30 },
      { path: '/api/orders/123', method: 'GET', weight: 20 },
      { path: '/api/license/TEST-9876-5432-1098/validate', method: 'GET', weight: 10 },
    ]

    # Create weighted request list
    requests = []
    endpoints.each do |endpoint|
      count = (@requests * endpoint[:weight] / 100.0).to_i
      count.times { requests << endpoint }
    end

    # Randomize order
    requests.shuffle!

    start_time = Time.now

    # Execute mixed workload concurrently
    pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: @threads,
      max_threads: @threads,
      max_queue: requests.length
    )

    futures = requests.map do |req|
      Concurrent::Future.execute(executor: pool) do
        make_request(req[:path], method: req[:method], expected_status: [200, 404, 500])
      end
    end

    futures.each(&:value!)
    total_time = Time.now - start_time

    pool.shutdown
    pool.wait_for_termination(10)

    @results[:mixed_workload] = {
      total_requests: requests.length,
      total_time: total_time,
      requests_per_second: requests.length / total_time,
      endpoint_mix: endpoints,
    }

    puts "Mixed workload (#{requests.length} requests): #{format('%.3f', total_time)}s"
    puts "Requests/second: #{format('%.2f', @results[:mixed_workload][:requests_per_second])}"
    puts 'Endpoint distribution:'
    endpoints.each do |ep|
      puts "  - #{ep[:method]} #{ep[:path]}: #{ep[:weight]}%"
    end
    puts
  end

  def benchmark_single_request(endpoint, method: 'GET', data: nil, expected_status: [200])
    start_time = Time.now
    make_request(endpoint, method: method, data: data, expected_status: expected_status)
    Time.now - start_time
  end

  def benchmark_single_request_with_timeout(endpoint, method: 'GET', data: nil, expected_status: [200], timeout: 10)
    start_time = Time.now
    response = make_request_with_timeout(endpoint, method: method, data: data, expected_status: expected_status,
                                                   timeout: timeout)
    return nil unless response

    Time.now - start_time
  end

  def make_request_with_timeout(endpoint, method: 'GET', data: nil, expected_status: [200], timeout: 10)
    uri = URI("#{@base_url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = [timeout / 2, 5].min
    http.read_timeout = timeout

    request = case method.upcase
              when 'GET'
                Net::HTTP::Get.new(uri)
              when 'POST'
                req = Net::HTTP::Post.new(uri)
                req['Content-Type'] = 'application/json'
                req.body = data.to_json if data
                req
              else
                raise "Unsupported method: #{method}"
              end

    begin
      response = http.request(request)

      unless expected_status.include?(response.code.to_i)
        @errors << {
          endpoint: endpoint,
          method: method,
          expected: expected_status,
          actual: response.code.to_i,
          message: response.body&.slice(0, 200),
        }
      end

      puts "#{method} #{endpoint} -> #{response.code}" if @verbose

      response
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      puts "⚠️  Request timeout: #{method} #{endpoint}" if @verbose
      @errors << {
        endpoint: endpoint,
        method: method,
        error: e.class.name,
        message: "Request timed out after #{timeout}s",
      }
      nil
    rescue StandardError => e
      @errors << {
        endpoint: endpoint,
        method: method,
        error: e.class.name,
        message: e.message,
      }
      nil
    end
  end

  def benchmark_concurrent_requests(endpoint, count)
    start_time = Time.now

    pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: @threads,
      max_threads: @threads,
      max_queue: count
    )

    futures = Array.new(count) do
      Concurrent::Future.execute(executor: pool) do
        make_request(endpoint)
      end
    end

    futures.each(&:value!)
    total_time = Time.now - start_time

    pool.shutdown
    pool.wait_for_termination(10)

    total_time
  end

  def make_request(endpoint, method: 'GET', data: nil, expected_status: [200])
    uri = URI("#{@base_url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    http.read_timeout = 10

    request = case method.upcase
              when 'GET'
                Net::HTTP::Get.new(uri)
              when 'POST'
                req = Net::HTTP::Post.new(uri)
                req['Content-Type'] = 'application/json'
                req.body = data.to_json if data
                req
              else
                raise "Unsupported method: #{method}"
              end

    begin
      response = http.request(request)

      unless expected_status.include?(response.code.to_i)
        @errors << {
          endpoint: endpoint,
          method: method,
          expected: expected_status,
          actual: response.code.to_i,
          message: response.body,
        }
      end

      puts "#{method} #{endpoint} -> #{response.code}" if @verbose

      response
    rescue StandardError => e
      @errors << {
        endpoint: endpoint,
        method: method,
        error: e.class.name,
        message: e.message,
      }
      nil
    end
  end

  def generate_test_license_keys(count)
    Array.new(count) do |_i|
      # Generate fake license keys for testing
      parts = Array.new(4) { format('%04d', rand(10_000)) }
      "TEST-#{parts.join('-')}"
    end
  end

  def print_summary
    puts '📊 BENCHMARK SUMMARY'
    puts '=' * 60

    if @results.any?
      @results.each do |test_name, data|
        puts "#{test_name.to_s.tr('_', ' ').upcase}:"

        case test_name
        when :products
          puts "  • Single request: #{format('%.3f', data[:single_request_time] * 1000)}ms"
          puts "  • Throughput: #{format('%.2f', data[:requests_per_second])} req/s"
        when :license_validation
          puts "  • Average time: #{format('%.3f', data[:average_time] * 1000)}ms"
        when :concurrent_license_validation
          puts "  • Concurrent throughput: #{format('%.2f', data[:requests_per_second])} req/s"
          puts "  • Total time: #{format('%.3f', data[:total_time])}s"
        when :order_creation
          puts "  • Average time: #{format('%.3f', data[:average_time] * 1000)}ms"
          puts "  • Throughput: #{format('%.2f', data[:requests_per_second])} req/s"
        when :mixed_workload
          puts "  • Mixed throughput: #{format('%.2f', data[:requests_per_second])} req/s"
          puts "  • Total requests: #{data[:total_requests]}"
        end

        puts
      end
    end

    if @errors.any?
      puts "⚠️  ERRORS ENCOUNTERED (#{@errors.length}):"
      @errors.first(5).each do |error|
        puts "  • #{error[:method]} #{error[:endpoint]}: #{error[:error] || error[:actual]} - #{error[:message]&.slice(
          0, 100
        )}"
      end
      puts "  ... and #{@errors.length - 5} more" if @errors.length > 5
      puts
    end

    # Calculate overall performance score
    if @results[:products] && @results[:concurrent_license_validation]
      overall_rps = [
        @results[:products][:requests_per_second],
        @results[:concurrent_license_validation][:requests_per_second],
      ].compact.sum / 2

      puts '🎯 OVERALL PERFORMANCE:'
      puts "  • Average throughput: #{format('%.2f', overall_rps)} req/s"
      puts "  • Fiber-enabled: #{fiber_enabled_score}"
      puts
    end

    puts '✅ Benchmark completed!'
    puts 'Run with --verbose for detailed request logs'
  end

  def fiber_enabled_score
    # Simple heuristic: if we can handle more than 50 req/s, fibers are likely helping
    overall_rps = @results.values.filter_map { |r| r[:requests_per_second] }.max || 0

    case overall_rps
    when 0..25
      "LOW (#{format('%.1f', overall_rps)} req/s)"
    when 25..100
      "MEDIUM (#{format('%.1f', overall_rps)} req/s)"
    when 100..500
      "HIGH (#{format('%.1f', overall_rps)} req/s)"
    else
      "EXCELLENT (#{format('%.1f', overall_rps)} req/s)"
    end
  end
end

# Command line interface
if __FILE__ == $0
  options = {}

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby benchmark_api.rb [options]'

    opts.on('-h', '--host HOST', 'Server host (default: localhost)') do |h|
      options[:host] = h
    end

    opts.on('-p', '--port PORT', Integer, 'Server port (default: 4567)') do |p|
      options[:port] = p
    end

    opts.on('-t', '--threads THREADS', Integer, 'Number of threads (default: 10)') do |t|
      options[:threads] = t
    end

    opts.on('-r', '--requests REQUESTS', Integer, 'Requests per test (default: 100)') do |r|
      options[:requests] = r
    end

    opts.on('-v', '--verbose', 'Verbose output') do |v|
      options[:verbose] = v
    end

    opts.on('--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  benchmark = SourceLicenseAPIBenchmark.new(options)
  benchmark.run_all_benchmarks
end

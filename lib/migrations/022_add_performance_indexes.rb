# frozen_string_literal: true

# Source-License: Migration 22 - Add Performance Indexes
# Adds performance indexes for license validation optimization

class Migrations::AddPerformanceIndexes < BaseMigration
  VERSION = 22

  def up
    puts 'Adding performance indexes for license validation optimization...'

    # Add critical indexes for license validation performance
    add_performance_index_if_not_exists(:licenses, :license_key, 'licenses_license_key_perf_idx')

    # Composite index for license validation query (license_key + status + expires_at)
    add_performance_index_if_not_exists(:licenses, %i[license_key status expires_at],
                                        'licenses_validation_composite_idx')

    # Index for product lookups in joins (id + name for efficient JOINs)
    add_performance_index_if_not_exists(:products, %i[id name], 'products_id_name_perf_idx')

    # Index for license expiration date queries
    add_performance_index_if_not_exists(:licenses, :expires_at, 'licenses_expires_at_perf_idx') unless index_exists?(
      :licenses, :expires_at
    )

    # Index for activation counts (for activation limit checks)
    add_performance_index_if_not_exists(:licenses, :activation_count, 'licenses_activation_count_perf_idx')

    # Composite index for license-product joins with status
    add_performance_index_if_not_exists(:licenses, %i[product_id status], 'licenses_product_status_perf_idx')

    # Index for customer email lookups
    unless index_exists?(:licenses, :customer_email)
      add_performance_index_if_not_exists(:licenses, :customer_email,
                                          'licenses_customer_email_perf_idx')
    end

    # Composite index for custom license configurations
    add_performance_index_if_not_exists(:licenses, %i[custom_max_activations custom_expires_at],
                                        'licenses_custom_config_idx')

    puts '✓ Added performance indexes for license validation optimization'
  end
end

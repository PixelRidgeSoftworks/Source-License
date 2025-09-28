# frozen_string_literal: true

# Source-License: Migration 9 - Enhance Licensing System
# Enhances licensing system with subscription billing capabilities

class Migrations::EnhanceLicensingSystem < BaseMigration
  VERSION = 9

  def up
    puts 'Enhancing licensing system for subscription billing...'

    # Add new columns to products table for subscription billing
    DB.alter_table :products do
      add_column :billing_cycle, String, size: 50 # 'weekly', 'monthly', 'tri_monthly', 'semi_monthly', 'semi_annually', 'annually'
      add_column :billing_interval, Integer, default: 1 # e.g., every 3 months for tri_monthly
      add_column :trial_period_days, Integer, default: 0 # free trial period
      add_column :setup_fee, :decimal, size: [10, 2], default: 0.00 # one-time setup fee
      add_column :grace_period_days, Integer, default: 7 # days after failed payment before suspension
    end

    # Add new columns to licenses table for per-license configuration
    DB.alter_table :licenses do
      add_column :custom_max_activations, Integer # overrides product default if set
      add_column :custom_expires_at, DateTime # overrides product default if set
      add_column :license_type, String, size: 50, default: 'perpetual' # 'perpetual', 'subscription', 'trial'
      add_column :trial_ends_at, DateTime # for trial licenses
      add_column :grace_period_ends_at, DateTime # when license gets suspended after failed payment
    end

    # Enhance subscriptions table with billing cycle information
    DB.alter_table :subscriptions do
      add_column :billing_cycle, String, size: 50 # copy from product for historical tracking
      add_column :billing_interval, Integer, default: 1
      add_column :next_billing_date, DateTime
      add_column :last_payment_date, DateTime
      add_column :failed_payment_count, Integer, default: 0
      add_column :trial_ends_at, DateTime
      add_column :payment_method_id, String, size: 255 # Stripe payment method ID
    end

    # Create billing_cycles table for managing different billing frequencies
    create_billing_cycles_table

    # Create subscription_billing_histories table to track billing history
    create_subscription_billing_histories_table

    # Seed default billing cycles
    seed_billing_cycles

    puts '✓ Enhanced licensing system for subscription billing'
  end

  private

  def create_billing_cycles_table
    DB.create_table :billing_cycles do
      primary_key :id
      String :name, null: false, unique: true, size: 50 # 'weekly', 'monthly', etc.
      String :display_name, null: false, size: 100 # 'Weekly', 'Monthly', etc.
      Integer :days, null: false # number of days in cycle
      String :stripe_interval, size: 20 # 'week', 'month', 'year' for Stripe
      Integer :stripe_interval_count, default: 1 # for Stripe (e.g., every 3 months)
      Boolean :active, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :name
      index :active
    end
  end

  def create_subscription_billing_histories_table
    DB.create_table :subscription_billing_histories do
      primary_key :id
      foreign_key :subscription_id, :subscriptions, null: false, on_delete: :cascade
      Decimal :amount, size: [10, 2], null: false
      String :currency, size: 3, default: 'USD'
      String :status, null: false # 'pending', 'paid', 'failed', 'refunded'
      String :payment_intent_id, size: 255
      String :invoice_id, size: 255
      DateTime :billing_period_start, null: false
      DateTime :billing_period_end, null: false
      DateTime :paid_at
      DateTime :failed_at
      Text :failure_reason
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :subscription_id
      index :status
      index :billing_period_start
    end
  end

  def seed_billing_cycles
    cycles = [
      { name: 'weekly', display_name: 'Weekly', days: 7, stripe_interval: 'week', stripe_interval_count: 1 },
      { name: 'semi_monthly', display_name: 'Semi-Monthly (Every 2 weeks)', days: 14, stripe_interval: 'week',
        stripe_interval_count: 2, },
      { name: 'monthly', display_name: 'Monthly', days: 30, stripe_interval: 'month', stripe_interval_count: 1 },
      { name: 'tri_monthly', display_name: 'Tri-Monthly (Every 3 months)', days: 90, stripe_interval: 'month',
        stripe_interval_count: 3, },
      { name: 'semi_annually', display_name: 'Semi-Annually (Every 6 months)', days: 182, stripe_interval: 'month',
        stripe_interval_count: 6, },
      { name: 'annually', display_name: 'Annually', days: 365, stripe_interval: 'year', stripe_interval_count: 1 },
    ]

    cycles.each do |cycle|
      DB[:billing_cycles].insert_ignore.insert(
        cycle.merge(created_at: Time.now)
      )
    end
  end
end

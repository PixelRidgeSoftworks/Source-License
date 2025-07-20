# frozen_string_literal: true

# Source-License: Database Migrations
# Handles creation and updates of database schema

class Migrations
  class << self
    # Run all migrations in order
    def run_all
      puts 'Running database migrations...'

      create_schema_info_table
      run_migration(1, :create_admins_table)
      run_migration(2, :create_products_table)
      run_migration(3, :create_orders_table)
      run_migration(4, :create_order_items_table)
      run_migration(5, :create_licenses_table)
      run_migration(6, :create_subscriptions_table)
      run_migration(7, :create_license_activations_table)
      run_migration(8, :create_settings_table)
      run_migration(9, :enhance_licensing_system)
      run_migration(10, :add_missing_product_fields)
      run_migration(11, :add_customer_name_to_orders)
      run_migration(12, :create_users_table)
      run_migration(13, :add_user_id_to_licenses)
      run_migration(14, :create_failed_login_attempts_table)
      run_migration(15, :create_account_bans_table)
      run_migration(16, :enhance_admin_table_for_security)
      run_migration(17, :create_taxes_table)
      run_migration(18, :create_order_taxes_table)
      run_migration(19, :add_tax_fields_to_orders)

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
    def run_migration(version, method_name)
      return if migration_exists?(version)

      puts "Running migration #{version}: #{method_name}"
      send(method_name)
      record_migration(version)
      puts "✓ Migration #{version} completed"
    end

    # Check if a migration has already been run
    def migration_exists?(version)
      DB[:schema_info].where(version: version).any?
    end

    # Record that a migration has been run
    def record_migration(version)
      DB[:schema_info].insert(version: version, created_at: Time.now)
    end

    # Migration 1: Create admins table
    def create_admins_table
      DB.create_table :admins do
        primary_key :id
        String :email, null: false, unique: true, size: 255
        String :password_hash, null: false, size: 255
        String :status, default: 'active', size: 50
        String :roles, default: 'admin', size: 255

        # Authentication tracking
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :last_login_at
        String :last_login_ip, size: 45
        String :last_login_user_agent, size: 500
        Integer :login_count, default: 0

        # Password management
        DateTime :password_changed_at
        Boolean :must_change_password, default: false
        String :password_reset_token, size: 255
        DateTime :password_reset_sent_at

        # Two-factor authentication
        String :two_factor_secret, size: 255
        Boolean :two_factor_enabled, default: false
        DateTime :two_factor_enabled_at
        DateTime :two_factor_disabled_at

        # Account status tracking
        DateTime :activated_at
        DateTime :deactivated_at
        DateTime :locked_at
        DateTime :unlocked_at

        index :email
        index :status
        index :password_reset_token
        index :last_login_at
      end
    end

    # Migration 2: Create products table
    def create_products_table
      DB.create_table :products do
        primary_key :id
        String :name, null: false, size: 255
        Text :description
        Text :features # JSON field for product features
        Decimal :price, size: [10, 2], null: false
        String :license_type, null: false, default: 'one_time' # 'one_time' or 'subscription'
        Integer :license_duration_days # null for one-time, number for subscription
        Integer :max_activations, default: 1
        String :download_file, size: 255 # filename in downloads directory
        String :version, size: 50
        Boolean :active, default: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :name
        index :license_type
        index :active
      end
    end

    # Migration 3: Create orders table
    def create_orders_table
      DB.create_table :orders do
        primary_key :id
        String :email, null: false, size: 255
        String :customer_name, size: 255 # customer's full name
        Decimal :amount, size: [10, 2], null: false
        String :currency, default: 'USD', size: 3
        String :status, null: false, default: 'pending' # pending, completed, failed, refunded
        String :payment_method, size: 50 # stripe, paypal, free, manual
        String :payment_intent_id, size: 255 # external payment ID
        String :transaction_id, size: 255 # final transaction ID
        Text :payment_details # JSON field for additional payment info
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :completed_at

        index :email
        index :status
        index :payment_intent_id
      end
    end

    # Migration 4: Create order_items table
    def create_order_items_table
      DB.create_table :order_items do
        primary_key :id
        foreign_key :order_id, :orders, null: false, on_delete: :cascade
        foreign_key :product_id, :products, null: false
        Integer :quantity, null: false, default: 1
        Decimal :price, size: [10, 2], null: false # price at time of purchase
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :order_id
        index :product_id
      end
    end

    # Migration 5: Create licenses table
    def create_licenses_table
      DB.create_table :licenses do
        primary_key :id
        String :license_key, null: false, unique: true, size: 255
        foreign_key :order_id, :orders, null: false
        foreign_key :product_id, :products, null: false
        String :customer_email, null: false, size: 255
        String :status, null: false, default: 'active' # active, suspended, revoked, expired
        Integer :max_activations, null: false, default: 1
        Integer :activation_count, default: 0
        Integer :download_count, default: 0
        DateTime :expires_at # null for lifetime licenses
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :last_activated_at
        DateTime :last_downloaded_at

        index :license_key
        index :customer_email
        index :status
        index :order_id
        index :product_id
      end
    end

    # Migration 6: Create subscriptions table (for subscription-based licenses)
    def create_subscriptions_table
      DB.create_table :subscriptions do
        primary_key :id
        foreign_key :license_id, :licenses, null: false, on_delete: :cascade
        String :external_subscription_id, size: 255 # Stripe/PayPal subscription ID
        String :status, null: false, default: 'active' # active, canceled, past_due, unpaid
        DateTime :current_period_start, null: false
        DateTime :current_period_end, null: false
        DateTime :canceled_at
        Boolean :auto_renew, default: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :license_id
        index :external_subscription_id
        index :status
      end
    end

    # Migration 7: Create license_activations table (for tracking activations)
    def create_license_activations_table
      DB.create_table :license_activations do
        primary_key :id
        foreign_key :license_id, :licenses, null: false, on_delete: :cascade
        String :machine_fingerprint, size: 255 # unique machine identifier
        String :ip_address, size: 45 # supports both IPv4 and IPv6
        String :user_agent, size: 500
        Text :system_info # JSON field for system information
        Boolean :active, default: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :deactivated_at

        index :license_id
        index :machine_fingerprint
        index %i[license_id machine_fingerprint], unique: true
      end
    end

    # Migration 8: Create settings table
    def create_settings_table
      DB.create_table :settings do
        primary_key :id
        String :key, null: false, unique: true, size: 255
        Text :value
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :key
      end
    end

    # Migration 9: Enhance licensing system with subscription billing
    def enhance_licensing_system
      puts 'Enhancing licensing system for subscription billing...'

      # Add new columns to products table for subscription billing
      DB.alter_table :products do
        add_column :billing_cycle,
                   String, size: 50 # 'weekly', 'monthly', 'tri_monthly', 'semi_monthly', 'semi_annually', 'annually'
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

      # Create subscription_billing_histories table to track billing history
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

      # Seed default billing cycles
      seed_billing_cycles

      puts '✓ Enhanced licensing system for subscription billing'
    end

    # Seed default billing cycles
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

    # Migration 10: Add missing product fields
    def add_missing_product_fields
      puts 'Adding missing product fields...'

      # Add missing fields to products table
      DB.alter_table :products do
        add_column :download_url, String, size: 500 # external download URL
        add_column :file_size, String, size: 50 # display file size
        add_column :featured, :boolean, default: false # featured product flag
      end

      puts '✓ Added missing product fields'
    end

    # Migration 11: Add customer_name to orders table
    def add_customer_name_to_orders
      puts 'Adding customer_name field to orders table...'

      # Add customer_name field if it doesn't exist
      unless DB.schema(:orders).any? { |col| col[0] == :customer_name }
        DB.alter_table :orders do
          add_column :customer_name, String, size: 255
        end
      end

      puts '✓ Added customer_name field to orders table'
    end

    # Migration 12: Create users table
    def create_users_table
      puts 'Creating users table for customer accounts...'

      DB.create_table :users do
        primary_key :id
        String :email, null: false, unique: true, size: 255
        String :name, size: 255
        String :password_hash, null: false, size: 255
        String :status, default: 'active', size: 50

        # Email verification
        Boolean :email_verified, default: false
        String :email_verification_token, size: 255
        DateTime :email_verification_sent_at
        DateTime :email_verified_at

        # Password management
        DateTime :password_changed_at
        String :password_reset_token, size: 255
        DateTime :password_reset_sent_at

        # Authentication tracking
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :last_login_at
        String :last_login_ip, size: 45
        String :last_login_user_agent, size: 500
        Integer :login_count, default: 0

        # Account status tracking
        DateTime :activated_at
        DateTime :deactivated_at
        DateTime :suspended_at

        index :email
        index :status
        index :email_verification_token
        index :password_reset_token
        index :last_login_at
      end

      puts '✓ Created users table'
    end

    # Migration 13: Add user_id to licenses table
    def add_user_id_to_licenses
      puts 'Adding user_id to licenses table...'

      # Add user_id foreign key to licenses table
      DB.alter_table :licenses do
        add_foreign_key :user_id, :users, null: true # Allow null for backward compatibility
      end

      # Add index for user_id
      DB.alter_table :licenses do
        add_index :user_id
      end

      puts '✓ Added user_id to licenses table'
    end

    # Migration 14: Create failed login attempts table for rate limiting
    def create_failed_login_attempts_table
      puts 'Creating failed_login_attempts table for authentication security...'

      DB.create_table :failed_login_attempts do
        primary_key :id
        String :email, null: false, size: 255
        Integer :admin_id, null: true  # null if not an admin account
        String :ip_address, size: 45   # Support both IPv4 and IPv6
        String :user_agent, text: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        
        # Indexes for performance
        index :email
        index :created_at
        index [:email, :created_at]
        index :ip_address
      end

      puts '✓ Created failed_login_attempts table'
    end

    # Migration 15: Create account bans table for progressive bans
    def create_account_bans_table
      puts 'Creating account_bans table for progressive ban system...'

      DB.create_table :account_bans do
        primary_key :id
        String :email, null: false, size: 255
        Integer :admin_id, null: true   # null if not an admin account
        Integer :ban_count, null: false, default: 1
        DateTime :banned_until, null: false
        String :reason, default: 'multiple_failed_login_attempts', size: 255
        String :ip_address, size: 45    # Support both IPv4 and IPv6
        String :user_agent, text: true
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: true
        
        # Indexes for performance
        index :email
        index :banned_until
        index [:email, :banned_until]
        index [:email, :created_at]
        index :created_at
      end

      puts '✓ Created account_bans table'
    end

    # Migration 16: Enhance admin table for security features
    def enhance_admin_table_for_security
      puts 'Enhancing admin table for security features...'

      # Add missing fields to admin table if they don't exist
      admin_schema = DB.schema(:admins).map { |col| col[0] }

      DB.alter_table :admins do
        # Add name field for admin management
        add_column :name, String, size: 255 unless admin_schema.include?(:name)
        
        # Add active boolean field (maps to status but easier to use)
        add_column :active, :boolean, default: true unless admin_schema.include?(:active)
        
        # Add session tracking for enhanced security
        add_column :current_session_id, String, size: 64 unless admin_schema.include?(:current_session_id)
        add_column :session_expires_at, DateTime unless admin_schema.include?(:session_expires_at)
        
        # Add failed login tracking
        add_column :failed_login_count, Integer, default: 0 unless admin_schema.include?(:failed_login_count)
        add_column :last_failed_login_at, DateTime unless admin_schema.include?(:last_failed_login_at)
        
        # Add password policy fields
        add_column :password_expires_at, DateTime unless admin_schema.include?(:password_expires_at)
        add_column :force_password_change, :boolean, default: false unless admin_schema.include?(:force_password_change)
      end

      # Add indexes for new fields
      begin
        DB.alter_table :admins do
          add_index :name unless DB.indexes(:admins).key?(:admins_name_index)
          add_index :active unless DB.indexes(:admins).key?(:admins_active_index)
          add_index :current_session_id unless DB.indexes(:admins).key?(:admins_current_session_id_index)
          add_index :failed_login_count unless DB.indexes(:admins).key?(:admins_failed_login_count_index)
        end
      rescue Sequel::DatabaseError => e
        puts "Note: Some indexes may already exist: #{e.message}"
      end

      puts '✓ Enhanced admin table for security features'
    end

    # Migration 17: Create taxes table
    def create_taxes_table
      puts 'Creating taxes table for custom tax configuration...'

      DB.create_table :taxes do
        primary_key :id
        String :name, null: false, size: 255
        String :description, size: 500
        Decimal :rate, size: [8, 4], null: false # percentage rate (e.g., 8.25 for 8.25%)
        String :status, default: 'active', size: 20 # active, inactive
        String :type, default: 'percentage', size: 20 # percentage, fixed (for future use)
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :name
        index :status
        index :rate
      end

      puts '✓ Created taxes table'
    end

    # Migration 18: Create order_taxes table
    def create_order_taxes_table
      puts 'Creating order_taxes table for tracking applied taxes...'

      DB.create_table :order_taxes do
        primary_key :id
        foreign_key :order_id, :orders, null: false, on_delete: :cascade
        foreign_key :tax_id, :taxes, null: true # null if tax was deleted
        String :tax_name, null: false, size: 255 # store name for historical purposes
        Decimal :rate, size: [8, 4], null: false # store rate at time of application
        Decimal :amount, size: [10, 2], null: false # calculated tax amount
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

        index :order_id
        index :tax_id
      end

      puts '✓ Created order_taxes table'
    end

    # Migration 19: Add tax fields to orders table
    def add_tax_fields_to_orders
      puts 'Adding tax fields to orders table...'

      # Add tax-related fields to orders table
      orders_schema = DB.schema(:orders).map { |col| col[0] }

      DB.alter_table :orders do
        add_column :subtotal, :decimal, size: [10, 2], default: 0.00 unless orders_schema.include?(:subtotal)
        add_column :tax_total, :decimal, size: [10, 2], default: 0.00 unless orders_schema.include?(:tax_total)
        add_column :tax_applied, :boolean, default: false unless orders_schema.include?(:tax_applied)
      end

      # Add indexes for the new fields
      begin
        DB.alter_table :orders do
          add_index :subtotal unless DB.indexes(:orders).key?(:orders_subtotal_index)
          add_index :tax_total unless DB.indexes(:orders).key?(:orders_tax_total_index)
          add_index :tax_applied unless DB.indexes(:orders).key?(:orders_tax_applied_index)
        end
      rescue Sequel::DatabaseError => e
        puts "Note: Some indexes may already exist: #{e.message}"
      end

      puts '✓ Added tax fields to orders table'
    end
  end
end

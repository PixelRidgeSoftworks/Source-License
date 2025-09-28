# frozen_string_literal: true

# Source-License: Migrations Registry
# Auto-loads all migration files and provides registry functionality

class Migrations::MigrationsRegistry
  class << self
    def load_all_migrations
      # Load all migration files in order
      migration_files.each do |file|
        require_relative file
      end
    end

    def all_migration_classes
      [
        CreateAdminsTable,
        CreateProductsTable,
        CreateOrdersTable,
        CreateOrderItemsTable,
        CreateLicensesTable,
        CreateSubscriptionsTable,
        CreateLicenseActivationsTable,
        CreateSettingsTable,
        EnhanceLicensingSystem,
        AddMissingProductFields,
        AddCustomerNameToOrders,
        CreateUsersTable,
        AddUserIdToLicenses,
        CreateFailedLoginAttemptsTable,
        CreateAccountBansTable,
        EnhanceAdminTableForSecurity,
        CreateTaxesTable,
        CreateOrderTaxesTable,
        AddTaxFieldsToOrders,
        AddRefundedAtToOrders,
        AddCustomerNameToLicenses,
        AddPerformanceIndexes,
      ]
    end

    private

    def migration_files
      %w[
        001_create_admins_table
        002_create_products_table
        003_create_orders_table
        004_create_order_items_table
        005_create_licenses_table
        006_create_subscriptions_table
        007_create_license_activations_table
        008_create_settings_table
        009_enhance_licensing_system
        010_add_missing_product_fields
        011_add_customer_name_to_orders
        012_create_users_table
        013_add_user_id_to_licenses
        014_create_failed_login_attempts_table
        015_create_account_bans_table
        016_enhance_admin_table_for_security
        017_create_taxes_table
        018_create_order_taxes_table
        019_add_tax_fields_to_orders
        020_add_refunded_at_to_orders
        021_add_customer_name_to_licenses
        022_add_performance_indexes
      ]
    end
  end
end

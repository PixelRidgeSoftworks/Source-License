# frozen_string_literal: true

# Source-License: Migration 16 - Enhance Admin Table for Security
# Enhances admin table for security features

class Migrations::EnhanceAdminTableForSecurity < BaseMigration
  VERSION = 16

  def up
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
end

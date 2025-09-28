# frozen_string_literal: true

# Source-License: Base Migration Class
# Provides common functionality for all migrations

class Migrations::BaseMigration
  def initialize
    @version = self.class.const_get(:VERSION)
  end

  attr_reader :version

  # Override this method in subclasses
  def up
    raise NotImplementedError, "#{self.class} must implement #up method"
  end

  protected

  # Helper method to add performance index if it doesn't already exist
  def add_performance_index_if_not_exists(table, columns, index_name)
    # Check if a similar index already exists
    if performance_index_exists?(table, columns, index_name)
      puts "  • Performance index #{index_name} or similar already exists, skipping"
      return
    end

    # Add the index
    DB.alter_table(table) do
      add_index columns, name: index_name
    end

    puts "  • Added performance index: #{index_name} on #{table}(#{columns})"
  rescue Sequel::DatabaseError => e
    if e.message.include?('already exists') || e.message.include?('duplicate')
      puts "  • Performance index #{index_name} already exists"
    else
      puts "  ⚠ Could not add performance index #{index_name}: #{e.message}"
    end
  end

  # Check if performance index exists (more comprehensive than basic index check)
  def performance_index_exists?(table, columns, index_name)
    indexes = DB.indexes(table)

    # Check by index name
    return true if indexes.key?(index_name.to_sym)

    # Check by column pattern (for cases where index exists with different name)
    target_columns = columns.is_a?(Array) ? columns : [columns]

    indexes.each_value do |index_info|
      index_columns = index_info[:columns] || []
      return true if index_columns == target_columns
    end

    false
  rescue StandardError
    false
  end

  # Basic index existence check (used by other methods)
  def index_exists?(table, column)
    indexes = DB.indexes(table)
    indexes.values.any? { |idx| idx[:columns]&.include?(column) }
  rescue StandardError
    false
  end

  # Helper method to check if column exists in table
  def column_exists?(table, column_name)
    DB.schema(table).any? { |col| col[0] == column_name }
  rescue StandardError
    false
  end

  # Helper method to safely add column if it doesn't exist
  def add_column_if_not_exists(table, column_name, column_type, options = {})
    return if column_exists?(table, column_name)

    DB.alter_table(table) do
      add_column column_name, column_type, options
    end
  end

  # Helper method to safely add index if it doesn't exist
  def add_index_if_not_exists(table, columns, options = {})
    index_name = options[:name] || "#{table}_#{Array(columns).join('_')}_index"

    return if index_exists_by_name?(table, index_name)

    DB.alter_table(table) do
      add_index columns, options
    end
  rescue Sequel::DatabaseError => e
    puts "Note: Index may already exist: #{e.message}" if e.message.include?('already exists')
  end

  # Check if index exists by name
  def index_exists_by_name?(table, index_name)
    DB.indexes(table).key?(index_name.to_sym)
  rescue StandardError
    false
  end
end

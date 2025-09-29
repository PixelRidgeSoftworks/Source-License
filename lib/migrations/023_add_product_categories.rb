# frozen_string_literal: true

# Source-License: Migration 23 - Add Product Categories
# Adds category system for products

class Migrations::AddProductCategories < Migrations::BaseMigration
  VERSION = 23

  def up
    puts 'Adding product categories support...'

    # Create categories table
    DB.create_table :product_categories do
      primary_key :id
      String :name, null: false, size: 100
      String :slug, null: false, size: 100
      Text :description
      String :color, size: 7, default: '#6c757d' # hex color for category badge
      String :icon, size: 50, default: 'fas fa-folder' # FontAwesome icon class
      Integer :sort_order, default: 0
      Boolean :active, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :name
      index :active
      index :sort_order
    end

    # Add category_id to products table if it doesn't exist
    unless DB[:products].columns.include?(:category_id)
      DB.alter_table :products do
        add_foreign_key :category_id, :product_categories, null: true, on_delete: :set_null
      end
    end

    # Add index if it doesn't exist
    unless DB.indexes(:products).key?(:idx_products_category_id)
      DB.alter_table :products do
        add_index :category_id, name: :idx_products_category_id
      end
    end

    # Create some default categories
    DB[:product_categories].insert(
      name: 'Software',
      slug: 'software',
      description: 'Desktop and web applications',
      color: '#007bff',
      icon: 'fas fa-desktop',
      sort_order: 1,
      active: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    DB[:product_categories].insert(
      name: 'Plugins',
      slug: 'plugins',
      description: 'Extensions and add-ons',
      color: '#28a745',
      icon: 'fas fa-puzzle-piece',
      sort_order: 2,
      active: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    DB[:product_categories].insert(
      name: 'Themes',
      slug: 'themes',
      description: 'Visual themes and templates',
      color: '#ffc107',
      icon: 'fas fa-palette',
      sort_order: 3,
      active: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    DB[:product_categories].insert(
      name: 'Services',
      slug: 'services',
      description: 'Consulting and support services',
      color: '#17a2b8',
      icon: 'fas fa-cogs',
      sort_order: 4,
      active: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    puts '✓ Added product categories support with default categories'
  end

  def down
    puts 'Removing product categories support...'

    DB.alter_table :products do
      drop_foreign_key :category_id
    end

    DB.drop_table :product_categories

    puts '✓ Removed product categories support'
  end
end

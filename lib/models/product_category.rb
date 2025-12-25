# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'

# Product categories for organizing products
class ProductCategory < Sequel::Model
  include BaseModelMethods

  set_dataset :product_categories
  one_to_many :products, key: :category_id

  # Generate slug from name
  def before_save
    self.slug = generate_slug(name) if name && (new? || name_changed?)
    self.updated_at = Time.now
    super
  end

  # Get formatted color for display
  def badge_color
    color || '#6c757d'
  end

  # Get icon class
  def icon_class
    icon || 'fas fa-folder'
  end

  # Get products count
  def products_count
    products_dataset.count
  end

  # Get active products count
  def active_products_count
    products_dataset.where(active: true).count
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:slug, 'cannot be empty') if !slug || slug.strip.empty?

    # Check slug uniqueness
    if slug
      existing = ProductCategory.where(slug: slug).exclude(id: id).first
      errors.add(:slug, 'already exists') if existing
    end

    # Validate color format (hex color)
    # Use Regexp#match? to avoid allocating MatchData when only checking boolean
    return unless color && !/\A#[0-9A-Fa-f]{6}\z/.match?(color)

    errors.add(:color, 'must be a valid hex color (e.g., #007bff)')
  end

  private

  def generate_slug(text)
    return '' unless text

    # Convert to lowercase, replace spaces and special chars with hyphens
    slug = text.downcase.strip
    slug = slug.gsub(/[^a-z0-9\s-]/, '') # Remove special characters
    slug = slug.gsub(/\s+/, '-') # Replace spaces with hyphens
    slug = slug.squeeze('-') # Replace multiple hyphens with single
    slug = slug.gsub(/^-|-$/, '') # Remove leading/trailing hyphens

    # Ensure uniqueness
    base_slug = slug
    counter = 1
    while ProductCategory.where(slug: slug).exclude(id: id).any?
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug
  end
end

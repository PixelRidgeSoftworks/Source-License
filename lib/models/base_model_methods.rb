# frozen_string_literal: true

# Base model with common functionality
module BaseModelMethods
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Automatically set updated_at timestamp
  def before_update
    super
    self.updated_at = Time.now if respond_to?(:updated_at)
  end

  # Convert to hash for JSON serialization
  def to_hash_for_api
    values.reject { |k, _| k.to_s.include?('password') }
  end

  module ClassMethods
    # Add any class methods here if needed
  end
end

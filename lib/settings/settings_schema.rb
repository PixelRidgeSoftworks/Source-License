# frozen_string_literal: true

# Source-License: Settings Schema Definition
# Refactored to use modular schema architecture for better maintainability

require_relative 'schemas/schema_registry'

# Maintain backward compatibility with the original SETTINGS_SCHEMA constant
SETTINGS_SCHEMA = Settings::Schemas::SchemaRegistry.all_settings

module Settings
end

class Settings::SettingsSchema
  class << self
    def get_schema(key)
      Settings::Schemas::SchemaRegistry.get_schema(key)
    end

    def valid_key?(key)
      Settings::Schemas::SchemaRegistry.valid_key?(key)
    end

    def categories
      Settings::Schemas::SchemaRegistry.categories
    end

    def get_category_settings(category)
      Settings::Schemas::SchemaRegistry.get_category_settings(category)
    end

    def web_editable_settings
      Settings::Schemas::SchemaRegistry.web_editable_settings
    end

    def all_settings
      Settings::Schemas::SchemaRegistry.all_settings
    end
  end
end

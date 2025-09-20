# frozen_string_literal: true

# Source-License: Settings Management System
# Manages application configuration through database and environment variables

require_relative 'settings/settings_schema'
require_relative 'settings/settings_store'
require_relative 'settings/settings_validator'
require_relative 'settings/settings_exporter'
require_relative 'settings/settings_configuration_tester'

# Modular settings management system
# Delegates functionality to specialized classes for better maintainability
class SettingsManager
  class << self
    # Core setting operations
    def get(key)
      Settings::SettingsStore.get(key)
    end

    def assign(key, value)
      Settings::SettingsStore.update_setting(key, value)
    end

    # Alias for assign method
    def set(key, value)
      assign(key, value)
    end

    def get_category(category)
      Settings::SettingsStore.get_category(category)
    end

    # Schema operations
    def categories
      Settings::SettingsSchema.categories
    end

    def web_editable_settings
      Settings::SettingsSchema.web_editable_settings.map do |setting|
        {
          key: setting[:key],
          value: get(setting[:key]),
          schema: setting[:schema],
        }
      end
    end

    # Import/Export operations
    def export_to_yaml
      Settings::SettingsExporter.export_to_yaml
    end

    def import_from_yaml(yaml_content)
      Settings::SettingsExporter.import_from_yaml(yaml_content)
    end

    def generate_env_file
      Settings::SettingsExporter.generate_env_file
    end

    # Configuration testing
    def test_configuration(category = nil)
      Settings::SettingsConfigurationTester.test_configuration(category)
    end
  end
end

# frozen_string_literal: true

# Source-License: Settings Import/Export
# Handles importing and exporting settings to/from YAML and environment files

require 'yaml'
require_relative 'settings_schema'
require_relative 'settings_store'

class Settings::SettingsExporter
  class << self
    # Export settings to YAML
    def export_to_yaml
      settings = {}
      SettingsSchema.all_settings.each_key do |key|
        value = SettingsStore.get(key)
        settings[key] = value unless value == SettingsSchema.get_schema(key)[:default]
      end
      settings.to_yaml
    end

    # Import settings from YAML
    def import_from_yaml(yaml_content)
      settings = YAML.safe_load(yaml_content)
      imported = 0

      settings.each do |key, value|
        next unless SettingsSchema.valid_key?(key)

        begin
          SettingsStore.update_setting(key, value)
          imported += 1
        rescue ArgumentError
          # Skip invalid settings
        end
      end

      imported
    end

    # Generate .env file content
    def generate_env_file
      lines = ["# Generated .env file - #{Time.now}"]

      SettingsSchema.categories.each do |category|
        lines << ''
        lines << "# #{category.capitalize} Settings"

        SettingsStore.get_category(category).each do |setting|
          env_key = env_key_for(setting[:key])
          value = setting[:value]

          # Skip empty values
          next if value.nil? || value == ''

          # Add description as comment
          lines << "# #{setting[:schema][:description]}"
          lines << "#{env_key}=#{value}"
        end
      end

      lines.join("\n")
    end

    private

    def env_key_for(key)
      # Delegate to SettingsStore's private method logic
      # This is a simplified version - in practice, you might want to extract
      # the key_to_env method to a shared utility
      case key
      when 'app.name' then 'APP_NAME'
      when 'app.environment' then 'APP_ENV'
      when 'app.secret' then 'APP_SECRET'
      when 'app.host' then 'APP_HOST'
      when 'app.port' then 'PORT'
      else
        key.tr('.', '_').upcase
      end
    end
  end
end

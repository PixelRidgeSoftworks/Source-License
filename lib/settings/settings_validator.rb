# frozen_string_literal: true

# Source-License: Settings Validation
# Handles validation of setting values based on their type and constraints

class Settings::SettingsValidator
  class << self
    def valid_value?(value, schema)
      case schema[:type]
      when 'email'
        validate_email?(value)
      when 'url'
        validate_url?(value)
      when 'number'
        validate_number?(value)
      when 'select'
        validate_select?(value, schema[:options])
      else
        true
      end
    end

    private

    def validate_email?(value)
      return true if value.nil? || value.to_s.empty?

      value.to_s.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
    end

    def validate_url?(value)
      return true if value.nil? || value.to_s.empty?

      value.to_s.match?(/\Ahttps?:\/\//)
    end

    def validate_number?(value)
      return true if value.nil? || value.to_s.empty?

      value.to_s.match?(/\A\d+\z/)
    end

    def validate_select?(value, options)
      return true if value.nil? || value.to_s.empty?

      options&.include?(value.to_s)
    end
  end
end

# frozen_string_literal: true

# Source-License: Settings Schema Registry
# Aggregates all individual schema files and provides unified access

require_relative 'application_schema'
require_relative 'social_schema'
require_relative 'payment_schema'
require_relative 'webhook_schema'
require_relative 'email_schema'
require_relative 'security_schema'
require_relative 'system_schema'

class Settings::Schemas::SchemaRegistry
  # Aggregate all settings from individual schema files
  ALL_SCHEMAS = [
    ApplicationSchema,
    SocialSchema,
    PaymentSchema,
    WebhookSchema,
    EmailSchema,
    SecuritySchema,
    SystemSchema,
  ].freeze

  class << self
    def all_settings
      @all_settings ||= ALL_SCHEMAS.each_with_object({}) do |schema_class, settings|
        settings.merge!(schema_class.settings)
      end.freeze
    end

    def get_schema(key)
      all_settings[key] || { type: 'string', default: nil, category: 'unknown' }
    end

    def valid_key?(key)
      all_settings.key?(key)
    end

    def categories
      @categories ||= all_settings.values.map { |s| s[:category] }.uniq.sort
    end

    def get_category_settings(category)
      all_settings.filter_map do |key, schema|
        next unless schema[:category] == category

        { key: key, schema: schema }
      end
    end

    def web_editable_settings
      all_settings.filter_map do |key, schema|
        next unless schema[:web_editable]

        { key: key, schema: schema }
      end
    end

    # Convenience methods for accessing individual schema classes
    def application_schema
      ApplicationSchema
    end

    def social_schema
      SocialSchema
    end

    def payment_schema
      PaymentSchema
    end

    def webhook_schema
      WebhookSchema
    end

    def email_schema
      EmailSchema
    end

    def security_schema
      SecuritySchema
    end

    def system_schema
      SystemSchema
    end

    # Method to get settings by schema type
    def get_schema_settings(schema_type)
      case schema_type.to_sym
      when :application
        ApplicationSchema.settings
      when :social
        SocialSchema.settings
      when :payment
        PaymentSchema.settings
      when :webhook, :webhooks
        WebhookSchema.settings
      when :email
        EmailSchema.settings
      when :security
        SecuritySchema.settings
      when :system
        SystemSchema.settings
      else
        {}
      end
    end

    # Method to reload all schemas (useful for development)
    def reload!
      @all_settings = nil
      @categories = nil
      ALL_SCHEMAS.each(&:reload) if defined?(Rails) && Rails.env.development?
    end
  end
end

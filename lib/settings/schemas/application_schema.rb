# frozen_string_literal: true

# Source-License: Application Settings Schema
# Defines application-specific settings with their metadata

class Settings::Schemas::ApplicationSchema
  APPLICATION_SETTINGS = {
    'app.name' => {
      type: 'string',
      default: 'Source-License',
      category: 'application',
      description: 'Application name displayed throughout the interface',
      web_editable: true,
    },
    'app.description' => {
      type: 'text',
      default: 'Professional license management system',
      category: 'application',
      description: 'Application description for SEO and branding',
      web_editable: true,
    },
    'app.contact_email' => {
      type: 'email',
      default: 'admin@example.com',
      category: 'application',
      description: 'Contact email for customer support',
      web_editable: true,
    },
    'app.support_email' => {
      type: 'email',
      default: 'support@yourdomain.com',
      category: 'application',
      description: 'Support email for customer inquiries',
      web_editable: true,
    },
    'app.organization_name' => {
      type: 'string',
      default: 'Your Organization',
      category: 'application',
      description: 'Organization name for branding and legal purposes',
      web_editable: true,
    },
    'app.organization_url' => {
      type: 'url',
      default: 'https://yourdomain.com',
      category: 'application',
      description: 'Organization website URL',
      web_editable: true,
    },
    'app.timezone' => {
      type: 'select',
      default: 'UTC',
      options: ['UTC', 'America/New_York', 'America/Los_Angeles', 'Europe/London', 'Asia/Tokyo'],
      category: 'application',
      description: 'Default timezone for the application',
      web_editable: true,
    },
    'app.environment' => {
      type: 'select',
      default: 'development',
      options: %w[development production test],
      category: 'application',
      description: 'Application environment mode',
      web_editable: false,
    },
    'app.version' => {
      type: 'string',
      default: '1.0.0',
      category: 'application',
      description: 'Application version number',
      web_editable: false,
    },
    'app.secret' => {
      type: 'password',
      default: '',
      category: 'application',
      description: 'Application secret key for sessions and encryption',
      web_editable: false,
      sensitive: true,
    },
    'app.host' => {
      type: 'string',
      default: 'localhost',
      category: 'application',
      description: 'Application host/domain name',
      web_editable: true,
    },
    'app.port' => {
      type: 'number',
      default: 4567,
      category: 'application',
      description: 'Application port number',
      web_editable: true,
    },

    # Update Management
    'app.skip_update_check' => {
      type: 'boolean',
      default: false,
      category: 'application',
      description: 'Skip automatic update checks on startup (WARNING: May expose security vulnerabilities)',
      web_editable: true,
    },
  }.freeze

  class << self
    def settings
      APPLICATION_SETTINGS
    end
  end
end

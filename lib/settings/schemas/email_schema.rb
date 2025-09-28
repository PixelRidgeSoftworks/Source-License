# frozen_string_literal: true

# Source-License: Email Settings Schema
# Defines email configuration settings with their metadata

class Settings::Schemas::EmailSchema
  EMAIL_SETTINGS = {
    'email.smtp.host' => {
      type: 'string',
      default: '',
      category: 'email',
      description: 'SMTP server hostname',
      web_editable: true,
    },
    'email.smtp.port' => {
      type: 'number',
      default: 587,
      category: 'email',
      description: 'SMTP server port (587 for TLS, 465 for SSL)',
      web_editable: true,
    },
    'email.smtp.username' => {
      type: 'string',
      default: '',
      category: 'email',
      description: 'SMTP authentication username',
      web_editable: true,
    },
    'email.smtp.password' => {
      type: 'password',
      default: '',
      category: 'email',
      description: 'SMTP authentication password',
      web_editable: true,
      sensitive: true,
    },
    'email.smtp.tls' => {
      type: 'boolean',
      default: true,
      category: 'email',
      description: 'Enable TLS encryption for SMTP',
      web_editable: true,
    },
    'email.from_name' => {
      type: 'string',
      default: 'Source License',
      category: 'email',
      description: 'From name for outgoing emails',
      web_editable: true,
    },
    'email.from_address' => {
      type: 'email',
      default: '',
      category: 'email',
      description: 'From address for outgoing emails',
      web_editable: true,
    },
  }.freeze

  class << self
    def settings
      EMAIL_SETTINGS
    end
  end
end

# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'
require 'json'

# License activation tracking
class LicenseActivation < Sequel::Model
  include BaseModelMethods

  set_dataset :license_activations
  many_to_one :license

  # Parse system info from JSON
  def system_info_hash
    return {} unless system_info

    JSON.parse(system_info)
  rescue JSON::ParserError
    {}
  end

  # Set system info as JSON
  def system_info_hash=(hash)
    self.system_info = hash.to_json
  end

  # Deactivate this activation
  def deactivate!
    update(active: false, deactivated_at: Time.now)
  end

  # Validation
  def validate
    super
    errors.add(:machine_fingerprint, 'cannot be empty') if !machine_fingerprint || machine_fingerprint.strip.empty?

    # Validate machine_id if license requires it
    return unless license&.requires_machine_id?

    return unless !machine_id || machine_id.strip.empty?

    errors.add(:machine_id,
               'cannot be empty when license requires machine ID')
  end
end

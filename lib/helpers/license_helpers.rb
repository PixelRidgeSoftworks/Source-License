# frozen_string_literal: true

# Source-License: License Helper Functions
# Provides license-specific helper methods for templates and controllers

# License-specific helper functions
module LicenseHelpers
  # Check if license key format is valid (must be uppercase and digits)
  def valid_license_format?(key)
    key.to_s.match?(/\A[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
  end

  # Format license key for display
  def format_license_key(key)
    k = key.to_s.upcase
    return 'Invalid' unless valid_license_format?(k)

    k
  end

  # Generate license status icon
  def license_status_icon(status)
    case status.to_s.downcase
    when 'active'
      '<i class="fas fa-check-circle text-success"></i>'
    when 'suspended'
      '<i class="fas fa-pause-circle text-warning"></i>'
    when 'expired'
      '<i class="fas fa-clock text-danger"></i>'
    when 'revoked'
      '<i class="fas fa-times-circle text-danger"></i>'
    else
      '<i class="fas fa-question-circle text-muted"></i>'
    end
  end

  # Calculate license expiration
  def license_expires_in(expires_at)
    return 'Never' unless expires_at
    return 'Expired' if expires_at < Time.now

    diff = expires_at - Time.now
    days = (diff / 86_400).to_i

    if days > 365
      "#{(days / 365).to_i} year(s)"
    elsif days > 30
      "#{(days / 30).to_i} month(s)"
    elsif days.positive?
      "#{days} day(s)"
    else
      hours = (diff / 3600).to_i
      "#{hours} hour(s)"
    end
  end

  # Generate activation progress bar
  def activation_progress(used, total)
    return '' unless used && total

    percentage = [(used.to_f / total * 100).to_i, 100].min
    color_class = case percentage
                  when 0..50 then 'bg-success'
                  when 51..80 then 'bg-warning'
                  else 'bg-danger'
                  end

    "<div class=\"progress\" style=\"height: 8px;\">
      <div class=\"progress-bar #{color_class}\" style=\"width: #{percentage}%\">
      </div>
    </div>
    <small class=\"text-muted\">#{used}/#{total} activations used</small>"
  end
end

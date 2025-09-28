# frozen_string_literal: true

# Source-License: Admin Helper Functions
# Provides admin-specific helper methods for templates and controllers

# Admin-specific helper functions
module AdminHelpers
  # Check if admin is the original admin created from .env
  def is_original_admin?(admin)
    return false unless admin

    # Check if this admin's email matches the initial admin email from .env
    initial_admin_email = ENV.fetch('INITIAL_ADMIN_EMAIL', nil)
    return false unless initial_admin_email

    admin.email&.downcase == initial_admin_email.downcase
  end

  # Check if admin is protected (original or system admin)
  def is_protected_admin?(admin)
    return false unless admin

    # Protect the original admin from .env
    return true if is_original_admin?(admin)

    # Protect the first admin in the system (fallback)
    first_admin = Admin.order(:id).first
    return true if first_admin && admin.id == first_admin.id

    # Additional protection logic could be added here
    false
  end

  # Get admin protection reason
  def admin_protection_reason(admin)
    return nil unless is_protected_admin?(admin)

    if is_original_admin?(admin)
      'Original admin account created during installation'
    elsif Admin.order(:id).first&.id == admin.id
      'First administrator account in the system'
    else
      'Protected system account'
    end
  end

  # Check if admin can be modified by current user
  def can_modify_admin?(target_admin, current_admin)
    return false unless target_admin && current_admin

    # Can't modify yourself for certain operations
    return false if target_admin.id == current_admin.id

    # Can't modify protected admins
    return false if is_protected_admin?(target_admin)

    true
  end

  # Get admin display name
  def admin_display_name(admin)
    return 'Unknown Admin' unless admin

    if admin.name && !admin.name.empty?
      admin.name
    else
      admin.email&.split('@')&.first || 'Admin'
    end
  end

  # Check if admin is system critical
  def is_system_critical_admin?(admin)
    return false unless admin

    # Check if this is the last active admin
    active_admin_count = Admin.where(active: true).count
    return true if active_admin_count <= 1 && admin.active?

    # Check if this is a protected admin
    is_protected_admin?(admin)
  end

  # Get admin status with protection info
  def admin_status_with_protection(admin)
    status = admin.active? ? 'Active' : 'Inactive'

    if is_protected_admin?(admin)
      protection_reason = admin_protection_reason(admin)
      "#{status} (Protected: #{protection_reason})"
    else
      status
    end
  end

  # Admin security level indicator
  def admin_security_level(admin)
    return 'Unknown' unless admin

    level = 0

    # Recent login
    level += 1 if admin.last_login_at && admin.last_login_at > (Time.now - (30 * 24 * 60 * 60))

    # Has name set
    level += 1 if admin.name && !admin.name.empty?

    # Email verified (if field exists)
    level += 1 if admin.respond_to?(:email_verified) && admin.email_verified

    # Two-factor enabled (if field exists)
    level += 1 if admin.respond_to?(:two_factor_enabled) && admin.two_factor_enabled

    # Recent password change (if field exists)
    if admin.respond_to?(:password_changed_at) && admin.password_changed_at && (admin.password_changed_at > (Time.now - (90 * 24 * 60 * 60)))
      level += 1
    end

    case level
    when 0..1
      '<span class="badge bg-danger">Low</span>'
    when 2..3
      '<span class="badge bg-warning">Medium</span>'
    else
      '<span class="badge bg-success">High</span>'
    end
  end
end

# frozen_string_literal: true

# Source-License: Password Management Module
# Handles password operations, validation, and policy enforcement

module Auth::PasswordManager
  include Auth::BaseAuth

  #
  # PASSWORD MANAGEMENT
  #

  # Generate secure random password
  def generate_secure_password(length = 16)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['!', '@', '#', '$', '%', '^', '&', '*']
    Array.new(length) { chars.sample }.join
  end

  # Hash password using BCrypt
  def hash_password(password)
    BCrypt::Password.create(password)
  end

  # Verify password against hash
  def verify_password(password, hash)
    BCrypt::Password.new(hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Password policy validation
  def validate_password_policy(password)
    errors = []

    # Length requirement
    if password.length < MIN_PASSWORD_LENGTH
      errors << "Password must be at least #{MIN_PASSWORD_LENGTH} characters long"
    end

    # Complexity requirements
    errors << 'Password must contain at least one lowercase letter' unless password.match?(/[a-z]/)

    errors << 'Password must contain at least one uppercase letter' unless password.match?(/[A-Z]/)

    errors << 'Password must contain at least one number' unless password.match?(/[0-9]/)

    errors << 'Password must contain at least one special character' unless password.match?(/[^a-zA-Z0-9]/)

    # Check against common passwords
    errors << 'Password is too common. Please choose a more unique password' if common_password?(password)

    # Check for repeated characters
    errors << 'Password cannot contain more than 2 consecutive identical characters' if password.match?(/(.)\1{2,}/)

    errors
  end

  private

  def common_password?(password)
    # Check against a list of common passwords
    common_passwords = %w[
      password password123 admin admin123 123456 qwerty
      letmein welcome changeme password1 abc123 administrator
    ]

    common_passwords.include?(password.downcase)
  end
end

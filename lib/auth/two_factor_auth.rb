# frozen_string_literal: true

require 'rotp'
require 'rqrcode'
require 'webauthn'
require 'base64'
require 'json'

# Source-License: Two-Factor Authentication Module
# Provides TOTP and WebAuthn support for enhanced security

module Auth::TwoFactorAuth
  include Auth::BaseAuth

  # WebAuthn Configuration
  WEBAUTHN_ORIGIN = ENV.fetch('WEBAUTHN_ORIGIN', 'https://localhost:4567')
  WEBAUTHN_RP_NAME = ENV.fetch('WEBAUTHN_RP_NAME', 'Source-License')
  WEBAUTHN_RP_ID = ENV.fetch('WEBAUTHN_RP_ID', 'localhost')

  #
  # TOTP (Time-based One-Time Password) Implementation
  #

  # Generate a new TOTP secret for a user
  def generate_totp_secret(user_id)
    secret = ROTP::Base32.random_base32

    # Store in database
    DB[:user_totp_settings].insert_conflict(:replace).insert(
      user_id: user_id,
      secret: secret,
      enabled: false,
      created_at: Time.now,
      updated_at: Time.now
    )

    secret
  end

  # Get TOTP settings for a user
  def get_totp_settings(user_id)
    DB[:user_totp_settings].where(user_id: user_id).first
  end

  # Generate QR code for TOTP setup
  def generate_totp_qr_code(user_email, secret, issuer = WEBAUTHN_RP_NAME)
    totp = ROTP::TOTP.new(secret, issuer: issuer)
    provisioning_uri = totp.provisioning_uri(user_email)

    qr = RQRCode::QRCode.new(provisioning_uri)

    # Generate SVG QR code
    qr.as_svg(
      offset: 0,
      color: '000',
      shape_rendering: 'crispEdges',
      module_size: 4,
      standalone: true
    )
  end

  # Verify TOTP token
  def verify_totp_token(user_id, token, drift: 30)
    totp_settings = get_totp_settings(user_id)
    return false unless totp_settings && totp_settings[:enabled]

    totp = ROTP::TOTP.new(totp_settings[:secret])

    # Verify with drift allowance for clock skew
    if totp.verify(token, drift_behind: drift, drift_ahead: drift)
      # Update last used timestamp
      DB[:user_totp_settings].where(user_id: user_id).update(
        last_used_at: Time.now,
        updated_at: Time.now
      )

      # Update user's last 2FA usage
      DB[:users].where(id: user_id).update(last_2fa_used_at: Time.now)

      log_auth_event('totp_verification_success', { user_id: user_id })
      return true
    end

    log_auth_event('totp_verification_failed', { user_id: user_id, token: "#{token[0..2]}***" })
    false
  end

  # Enable TOTP for a user after verification
  def enable_totp(user_id, verification_token)
    return false unless verify_totp_setup(user_id, verification_token)

    # Generate backup codes
    backup_codes = generate_backup_codes

    DB.transaction do
      # Enable TOTP
      DB[:user_totp_settings].where(user_id: user_id).update(
        enabled: true,
        enabled_at: Time.now,
        backup_codes: backup_codes.to_json,
        backup_codes_used: 0,
        updated_at: Time.now
      )

      # Update user 2FA status
      DB[:users].where(id: user_id).update(
        two_factor_enabled: true,
        two_factor_enabled_at: Time.now,
        backup_codes_generated_at: Time.now,
        preferred_2fa_method: 'totp'
      )
    end

    log_auth_event('totp_enabled', { user_id: user_id })
    backup_codes
  end

  # Verify TOTP setup (before enabling)
  def verify_totp_setup(user_id, token)
    totp_settings = get_totp_settings(user_id)
    return false unless totp_settings

    totp = ROTP::TOTP.new(totp_settings[:secret])
    totp.verify(token, drift_behind: 30, drift_ahead: 30)
  end

  # Disable TOTP for a user
  def disable_totp(user_id)
    DB.transaction do
      DB[:user_totp_settings].where(user_id: user_id).update(
        enabled: false,
        updated_at: Time.now
      )

      # Check if user has other 2FA methods
      webauthn_count = DB[:user_webauthn_credentials].where(user_id: user_id).count

      if webauthn_count.zero?
        # No other 2FA methods, disable 2FA entirely
        DB[:users].where(id: user_id).update(
          two_factor_enabled: false,
          preferred_2fa_method: nil
        )
      else
        # User still has WebAuthn, set as preferred
        DB[:users].where(id: user_id).update(
          preferred_2fa_method: 'webauthn'
        )
      end
    end

    log_auth_event('totp_disabled', { user_id: user_id })
  end

  #
  # WebAuthn Implementation
  #

  # Initialize WebAuthn relying party
  def webauthn_rp
    @webauthn_rp ||= WebAuthn::RelyingParty.new(
      origin: WEBAUTHN_ORIGIN,
      name: WEBAUTHN_RP_NAME,
      id: WEBAUTHN_RP_ID
    )
  end

  # Begin WebAuthn credential registration
  def begin_webauthn_registration(user_id, user_email)
    user = DB[:users].where(id: user_id).first
    return nil unless user

    # Get existing credentials for excludeCredentials
    existing_credentials = DB[:user_webauthn_credentials]
      .where(user_id: user_id)
      .map { |cred| cred[:external_id] }

    options = webauthn_rp.options_for_registration(
      user: {
        id: user_id.to_s,
        name: user_email,
        display_name: user[:email] || user_email,
      },
      exclude: existing_credentials
    )

    # Store challenge in session for verification
    session[:webauthn_challenge] = options.challenge
    session[:webauthn_user_id] = user_id

    options
  end

  # Complete WebAuthn credential registration
  def complete_webauthn_registration(credential_params, nickname)
    user_id = session[:webauthn_user_id]
    challenge = session[:webauthn_challenge]

    return { error: 'Invalid session' } unless user_id && challenge

    begin
      webauthn_credential = webauthn_rp.verify_registration(
        credential_params,
        challenge
      )

      # Store credential in database
      DB[:user_webauthn_credentials].insert(
        user_id: user_id,
        external_id: Base64.strict_encode64(webauthn_credential.id),
        public_key: Base64.strict_encode64(webauthn_credential.public_key),
        nickname: nickname,
        sign_count: webauthn_credential.sign_count,
        aaguid: webauthn_credential.aaguid,
        attestation_format: webauthn_credential.attestation_format,
        attestation_statement: webauthn_credential.attestation_statement.to_json,
        transports: (webauthn_credential.transports || []).to_json,
        backup_eligible: webauthn_credential.backup_eligible?,
        backup_state: webauthn_credential.backup_state?,
        created_at: Time.now,
        updated_at: Time.now
      )

      # Update user 2FA status
      DB[:users].where(id: user_id).update(
        two_factor_enabled: true,
        two_factor_enabled_at: Time.now,
        preferred_2fa_method: 'webauthn'
      )

      # Clear session data
      session.delete(:webauthn_challenge)
      session.delete(:webauthn_user_id)

      log_auth_event('webauthn_credential_registered', {
        user_id: user_id,
        nickname: nickname,
        aaguid: webauthn_credential.aaguid,
      })

      { success: true, credential_id: Base64.strict_encode64(webauthn_credential.id) }
    rescue WebAuthn::Error => e
      log_auth_event('webauthn_registration_failed', {
        user_id: user_id,
        error: e.message,
      })
      { error: e.message }
    end
  end

  # Begin WebAuthn authentication
  def begin_webauthn_authentication(user_id)
    credentials = DB[:user_webauthn_credentials]
      .where(user_id: user_id)
      .map { |cred| Base64.strict_decode64(cred[:external_id]) }

    return nil if credentials.empty?

    options = webauthn_rp.options_for_authentication(
      allow: credentials
    )

    # Store challenge in session
    session[:webauthn_auth_challenge] = options.challenge
    session[:webauthn_auth_user_id] = user_id

    options
  end

  # Complete WebAuthn authentication
  def complete_webauthn_authentication(credential_params)
    user_id = session[:webauthn_auth_user_id]
    challenge = session[:webauthn_auth_challenge]

    return false unless user_id && challenge

    begin
      # Find the credential being used
      credential_id = Base64.strict_encode64(credential_params['id'])
      stored_credential = DB[:user_webauthn_credentials]
        .where(user_id: user_id, external_id: credential_id)
        .first

      return false unless stored_credential

      # Verify the authentication
      webauthn_credential = webauthn_rp.verify_authentication(
        credential_params,
        challenge,
        public_key: Base64.strict_decode64(stored_credential[:public_key]),
        sign_count: stored_credential[:sign_count]
      )

      # Update sign count and last used timestamp
      DB[:user_webauthn_credentials]
        .where(id: stored_credential[:id])
        .update(
          sign_count: webauthn_credential.sign_count,
          last_used_at: Time.now,
          updated_at: Time.now
        )

      # Update user's last 2FA usage
      DB[:users].where(id: user_id).update(last_2fa_used_at: Time.now)

      # Clear session data
      session.delete(:webauthn_auth_challenge)
      session.delete(:webauthn_auth_user_id)

      log_auth_event('webauthn_authentication_success', {
        user_id: user_id,
        credential_nickname: stored_credential[:nickname],
      })

      true
    rescue WebAuthn::Error => e
      log_auth_event('webauthn_authentication_failed', {
        user_id: user_id,
        error: e.message,
      })
      false
    end
  end

  # Get user's WebAuthn credentials
  def get_webauthn_credentials(user_id)
    DB[:user_webauthn_credentials]
      .where(user_id: user_id)
      .order(:created_at)
      .all
  end

  # Delete a WebAuthn credential
  def delete_webauthn_credential(user_id, credential_id)
    credential = DB[:user_webauthn_credentials]
      .where(user_id: user_id, id: credential_id)
      .first

    return false unless credential

    DB[:user_webauthn_credentials]
      .where(id: credential_id)
      .delete

    # Check if user has other 2FA methods
    totp_enabled = DB[:user_totp_settings]
      .where(user_id: user_id, enabled: true)
      .any?

    webauthn_count = DB[:user_webauthn_credentials]
      .where(user_id: user_id)
      .count

    if !totp_enabled && webauthn_count.zero?
      # No 2FA methods left, disable 2FA
      DB[:users].where(id: user_id).update(
        two_factor_enabled: false,
        preferred_2fa_method: nil
      )
    elsif !totp_enabled && webauthn_count.positive?
      # Still has WebAuthn credentials
      DB[:users].where(id: user_id).update(preferred_2fa_method: 'webauthn')
    elsif totp_enabled && webauthn_count.zero?
      # Only TOTP left
      DB[:users].where(id: user_id).update(preferred_2fa_method: 'totp')
    end

    log_auth_event('webauthn_credential_deleted', {
      user_id: user_id,
      credential_nickname: credential[:nickname],
    })

    true
  end

  #
  # Backup Codes
  #

  # Generate backup codes
  def generate_backup_codes(count = 8)
    codes = []
    count.times do
      codes << SecureRandom.alphanumeric(8).downcase
    end
    codes
  end

  # Verify backup code
  def verify_backup_code(user_id, code)
    totp_settings = get_totp_settings(user_id)
    return false unless totp_settings && totp_settings[:backup_codes]

    backup_codes = JSON.parse(totp_settings[:backup_codes])
    return false unless backup_codes.include?(code)

    # Remove used backup code
    backup_codes.delete(code)

    DB[:user_totp_settings].where(user_id: user_id).update(
      backup_codes: backup_codes.to_json,
      backup_codes_used: totp_settings[:backup_codes_used] + 1,
      last_used_at: Time.now,
      updated_at: Time.now
    )

    # Update user's last 2FA usage
    DB[:users].where(id: user_id).update(last_2fa_used_at: Time.now)

    log_auth_event('backup_code_used', {
      user_id: user_id,
      remaining_codes: backup_codes.length,
    })

    true
  end

  # Get remaining backup codes count
  def get_backup_codes_count(user_id)
    totp_settings = get_totp_settings(user_id)
    return 0 unless totp_settings && totp_settings[:backup_codes]

    backup_codes = JSON.parse(totp_settings[:backup_codes])
    backup_codes.length
  end

  # Regenerate backup codes
  def regenerate_backup_codes(user_id)
    new_codes = generate_backup_codes

    DB[:user_totp_settings].where(user_id: user_id).update(
      backup_codes: new_codes.to_json,
      backup_codes_used: 0,
      updated_at: Time.now
    )

    DB[:users].where(id: user_id).update(
      backup_codes_generated_at: Time.now
    )

    log_auth_event('backup_codes_regenerated', { user_id: user_id })
    new_codes
  end

  #
  # 2FA Status and Helpers
  #

  # Check if user has 2FA enabled
  def user_has_2fa?(user_id)
    user = DB[:users].where(id: user_id).first
    return false unless user

    user[:two_factor_enabled] == true
  end

  # Check if user is required to have 2FA
  def user_requires_2fa?(user_id)
    user = DB[:users].where(id: user_id).first
    return false unless user

    user[:require_2fa] == true
  end

  # Get user's preferred 2FA method
  def get_preferred_2fa_method(user_id)
    user = DB[:users].where(id: user_id).first
    return nil unless user

    user[:preferred_2fa_method]
  end

  # Get available 2FA methods for user
  def get_available_2fa_methods(user_id)
    methods = []

    # Check TOTP
    totp_settings = get_totp_settings(user_id)
    methods << 'totp' if totp_settings && totp_settings[:enabled]

    # Check WebAuthn
    webauthn_count = DB[:user_webauthn_credentials].where(user_id: user_id).count
    methods << 'webauthn' if webauthn_count.positive?

    methods
  end

  # Verify any 2FA method
  def verify_2fa(user_id, method, token_or_credential)
    case method
    when 'totp'
      verify_totp_token(user_id, token_or_credential)
    when 'backup_code'
      verify_backup_code(user_id, token_or_credential)
    when 'webauthn'
      complete_webauthn_authentication(token_or_credential)
    else
      false
    end
  end
end

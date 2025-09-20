# frozen_string_literal: true

# Specialized logging functionality for auth, payment, and API requests
module SpecializedLoggers
  def self.log_auth_event(logger, event_type, details = {})
    context = {
      event_type: 'authentication',
      auth_event: event_type,
      details: details,
    }

    logger.log(:info, "Auth event: #{event_type}", context)
  end

  def self.log_payment_event(logger, event_type, details = {})
    # Sanitize payment details to remove sensitive data
    sanitized_details = sanitize_payment_details(details)

    context = {
      event_type: 'payment',
      payment_event: event_type,
      details: sanitized_details,
    }

    logger.log(:info, "Payment event: #{event_type}", context)
  end

  def self.log_api_request(logger, request_params, details = {})
    method = request_params[:method]
    path = request_params[:path]
    status = request_params[:status]
    duration = request_params[:duration]

    context = build_api_context(method, path, status, duration, details)
    level = determine_log_level(status)
    logger.log(level, "#{method} #{path} #{status} (#{duration}ms)", context)
  end

  private_class_method def self.build_api_context(method, path, status, duration, details)
    {
      event_type: 'api_request',
      http_method: method,
      path: path,
      status_code: status,
      duration_ms: duration,
      details: details,
    }
  end

  private_class_method def self.determine_log_level(status)
    if status >= 500
      :error
    else
      (status >= 400 ? :warn : :info)
    end
  end

  private_class_method def self.sanitize_payment_details(details)
    # Remove sensitive payment information
    sanitized = details.dup

    # Remove or mask sensitive fields
    sensitive_fields = %w[
      credit_card_number
      cvv
      ssn
      bank_account_number
      stripe_secret_key
      paypal_client_secret
    ]

    sensitive_fields.each do |field|
      if sanitized[field] || sanitized[field.to_sym]
        sanitized[field] = '[REDACTED]'
        sanitized[field.to_sym] = '[REDACTED]'
      end
    end

    # Mask partial information
    sanitized[:email] = mask_email(sanitized[:email]) if sanitized[:email]
    sanitized['email'] = mask_email(sanitized['email']) if sanitized['email']

    sanitized
  end

  private_class_method def self.mask_email(email)
    return email unless email.include?('@')

    local, domain = email.split('@')
    masked_local = local.length > 2 ? "#{local[0]}***#{local[-1]}" : '***'
    "#{masked_local}@#{domain}"
  end
end

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
    if admin.respond_to?(:password_changed_at) && admin.password_changed_at &&
       (admin.password_changed_at > (Time.now - (90 * 24 * 60 * 60)))
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

  # Log management helper methods
  def available_log_files
    log_directories = [
      ENV['LOG_PATH'] || './logs',
      './logs',
      './log',
    ].compact.uniq

    log_files = []

    log_directories.each do |log_dir|
      next unless Dir.exist?(log_dir)

      Dir.glob(File.join(log_dir, '*.log')).each do |file_path|
        next unless File.readable?(file_path)

        file_stat = File.stat(file_path)
        log_files << {
          name: File.basename(file_path),
          path: file_path,
          size: file_stat.size,
          size_formatted: format_file_size(file_stat.size),
          modified_at: file_stat.mtime,
          modified_formatted: file_stat.mtime.strftime('%Y-%m-%d %H:%M:%S'),
        }
      end
    end

    log_files.sort_by { |f| f[:modified_at] }.reverse
  rescue StandardError => e
    puts "Error getting log files: #{e.message}"
    []
  end

  def recent_log_entries(limit = 100)
    log_entries = []

    # Get file-based logs
    file_limit = limit / 2 # Split between file and database logs

    # Try to get entries from multiple log sources
    log_sources = [
      { type: 'application', path: ENV['LOG_PATH'] || './logs/application.log' },
      { type: 'error', path: './logs/error.log' },
      { type: 'access', path: './logs/access.log' },
      { type: 'payment', path: './logs/payment.log' },
      { type: 'security', path: './logs/security.log' },
    ]

    log_sources.each do |source|
      next unless File.exist?(source[:path]) && File.readable?(source[:path])

      begin
        entries = parse_log_file(source[:path], source[:type], file_limit / log_sources.length)
        log_entries.concat(entries)
      rescue StandardError => e
        puts "Error reading #{source[:type]} log: #{e.message}"
      end
    end

    # Get database logs
    db_limit = limit / 2
    db_entries = database_log_entries(db_limit)
    log_entries.concat(db_entries)

    # Sort by timestamp and limit
    log_entries.sort_by { |entry| entry[:timestamp] }.reverse.first(limit)
  rescue StandardError => e
    puts "Error getting recent log entries: #{e.message}"
    []
  end

  def log_entries(log_type, limit = 50, offset = 0)
    log_paths = {
      'application' => ENV['LOG_PATH'] || './logs/application.log',
      'error' => './logs/error.log',
      'access' => './logs/access.log',
      'payment' => './logs/payment.log',
      'security' => './logs/security.log',
    }

    log_path = log_paths[log_type] || log_paths['application']

    return [] unless File.exist?(log_path) && File.readable?(log_path)

    entries = parse_log_file(log_path, log_type, limit + offset)
    entries.drop(offset).first(limit)
  rescue StandardError => e
    puts "Error getting log entries for #{log_type}: #{e.message}"
    []
  end

  private

  def parse_log_file(file_path, log_type, limit)
    entries = []
    line_count = 0

    File.foreach(file_path) do |line|
      line_count += 1
      next if line.strip.empty?

      entry = parse_log_line(line.strip, log_type, line_count)
      entries << entry if entry

      # Stop if we have enough entries (reading from end would be better for large files)
      break if entries.length >= limit * 2 # Get extra to account for parsing failures
    end

    entries.last(limit) # Get the most recent entries
  rescue StandardError => e
    puts "Error parsing log file #{file_path}: #{e.message}"
    []
  end

  def parse_log_line(line, log_type, line_number)
    # Try to parse different log formats
    timestamp = nil
    level = 'INFO'
    message = line

    # Common timestamp patterns
    timestamp_patterns = [
      /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/,           # 2024-01-01 12:00:00
      /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/,           # 2024-01-01T12:00:00
      /^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/,       # [2024-01-01 12:00:00]
      /^(\w{3} \d{2} \d{2}:\d{2}:\d{2})/, # Jan 01 12:00:00
    ]

    timestamp_patterns.each do |pattern|
      match = line.match(pattern)
      next unless match

      begin
        timestamp = Time.parse(match[1])
        message = line.sub(pattern, '').strip
        break
      rescue ArgumentError
        # Invalid timestamp, continue
      end
    end

    # Extract log level
    level_match = message.match(/^\[?(DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\]?\s*/i)
    if level_match
      level = level_match[1].upcase
      message = message.sub(/^\[?(DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\]?\s*/i, '')
    end

    # Use current time if no timestamp found
    timestamp ||= Time.now

    {
      timestamp: timestamp,
      timestamp_formatted: timestamp.strftime('%Y-%m-%d %H:%M:%S'),
      level: level,
      message: message,
      log_type: log_type,
      line_number: line_number,
      level_class: log_level_class(level),
    }
  rescue StandardError => e
    puts "Error parsing log line: #{e.message}"
    {
      timestamp: Time.now,
      timestamp_formatted: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      level: 'ERROR',
      message: "Failed to parse: #{line}",
      log_type: log_type,
      line_number: line_number,
      level_class: 'danger',
    }
  end

  def log_level_class(level)
    case level.upcase
    when 'DEBUG'
      'secondary'
    when 'INFO'
      'info'
    when 'WARN', 'WARNING'
      'warning'
    when 'ERROR', 'FATAL'
      'danger'
    else
      'primary'
    end
  end

  def format_file_size(bytes)
    return '0 B' if bytes.zero?

    units = %w[B KB MB GB TB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min

    format('%.1f %s', bytes.to_f / (1024**exp), units[exp])
  end

  # Get database log entries from security tables
  def database_log_entries(limit = 50)
    entries = []

    begin
      # Get failed login attempts
      if DB.table_exists?(:failed_login_attempts)
        failed_logins = DB[:failed_login_attempts]
          .order(Sequel.desc(:created_at))
          .limit(limit / 4)
          .all

        failed_logins.each do |record|
          entries << {
            timestamp: record[:created_at],
            timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
            level: 'WARN',
            level_class: 'warning',
            log_type: 'security',
            message: "Failed login attempt for #{record[:email]} from IP #{record[:ip_address]}",
            line_number: record[:id],
            source: 'database',
            table: 'failed_login_attempts',
            metadata: {
              email: record[:email],
              ip_address: record[:ip_address],
              user_agent: record[:user_agent],
            },
          }
        end
      end

      # Get account bans
      if DB.table_exists?(:account_bans)
        bans = DB[:account_bans]
          .order(Sequel.desc(:created_at))
          .limit(limit / 4)
          .all

        bans.each do |record|
          entries << {
            timestamp: record[:created_at],
            timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
            level: 'ERROR',
            level_class: 'danger',
            log_type: 'security',
            message: "Account ban for #{record[:email]} (Ban ##{record[:ban_count]}) - #{record[:reason]}",
            line_number: record[:id],
            source: 'database',
            table: 'account_bans',
            metadata: {
              email: record[:email],
              ban_count: record[:ban_count],
              banned_until: record[:banned_until],
              reason: record[:reason],
              ip_address: record[:ip_address],
            },
          }
        end
      end

      # Get license audit logs
      if DB.table_exists?(:license_audit_logs)
        audit_logs = DB[:license_audit_logs]
          .order(Sequel.desc(:created_at))
          .limit(limit / 4)
          .all

        audit_logs.each do |record|
          level = record[:success] ? 'INFO' : 'WARN'
          level_class = record[:success] ? 'info' : 'warning'

          message = "License #{record[:action]}"
          message += " for key #{record[:license_key_partial]}***" if record[:license_key_partial]
          message += " from IP #{record[:ip_address]}" if record[:ip_address]
          message += " - #{record[:failure_reason]}" if !record[:success] && record[:failure_reason]

          entries << {
            timestamp: record[:created_at],
            timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
            level: level,
            level_class: level_class,
            log_type: 'license',
            message: message,
            line_number: record[:id],
            source: 'database',
            table: 'license_audit_logs',
            metadata: {
              license_id: record[:license_id],
              license_key_partial: record[:license_key_partial],
              action: record[:action],
              success: record[:success],
              ip_address: record[:ip_address],
              machine_fingerprint_partial: record[:machine_fingerprint_partial],
              failure_reason: record[:failure_reason],
            },
          }
        end
      end

      # Get rate limits (when exceeded)
      if DB.table_exists?(:rate_limits)
        rate_limits = DB[:rate_limits]
          .where { requests > 10 } # Only show rate limits with significant traffic
          .order(Sequel.desc(:window_start))
          .limit(limit / 4)
          .all

        rate_limits.each do |record|
          entries << {
            timestamp: record[:window_start],
            timestamp_formatted: record[:window_start].strftime('%Y-%m-%d %H:%M:%S'),
            level: 'WARN',
            level_class: 'warning',
            log_type: 'security',
            message: "Rate limit hit: #{record[:requests]} requests from #{record[:key_type]}:#{record[:key_value]} for #{record[:endpoint] || 'all endpoints'}",
            line_number: record[:id],
            source: 'database',
            table: 'rate_limits',
            metadata: {
              key_type: record[:key_type],
              key_value: record[:key_value],
              endpoint: record[:endpoint],
              requests: record[:requests],
              expires_at: record[:expires_at],
            },
          }
        end
      end
    rescue StandardError => e
      puts "Error getting database log entries: #{e.message}"
      # Add an error entry
      entries << {
        timestamp: Time.now,
        timestamp_formatted: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        level: 'ERROR',
        level_class: 'danger',
        log_type: 'system',
        message: "Failed to retrieve database logs: #{e.message}",
        line_number: 0,
        source: 'database',
        table: 'error',
      }
    end

    entries
  end

  # Get mixed file logs (for 'all' type)
  def mixed_file_logs(limit = 25, offset = 0)
    entries = []

    log_sources = [
      { type: 'application', path: ENV['LOG_PATH'] || './logs/application.log' },
      { type: 'error', path: './logs/error.log' },
      { type: 'access', path: './logs/access.log' },
      { type: 'payment', path: './logs/payment.log' },
      { type: 'security', path: './logs/security.log' },
    ]

    log_sources.each do |source|
      next unless File.exist?(source[:path]) && File.readable?(source[:path])

      begin
        file_entries = parse_log_file(source[:path], source[:type], limit / log_sources.length)
        entries.concat(file_entries)
      rescue StandardError => e
        puts "Error reading #{source[:type]} log: #{e.message}"
      end
    end

    # Sort by timestamp, apply offset and limit
    entries.sort_by { |entry| entry[:timestamp] }.reverse.drop(offset).first(limit)
  rescue StandardError => e
    puts "Error getting mixed file logs: #{e.message}"
    []
  end

  # Get database log entries filtered by type
  def database_log_entries_by_type(log_type, limit = 50, offset = 0)
    entries = []

    begin
      case log_type
      when 'security'
        # Get failed login attempts
        if DB.table_exists?(:failed_login_attempts)
          failed_logins = DB[:failed_login_attempts]
            .order(Sequel.desc(:created_at))
            .offset(offset)
            .limit(limit / 2)
            .all

          failed_logins.each do |record|
            entries << {
              timestamp: record[:created_at],
              timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
              level: 'WARN',
              level_class: 'warning',
              log_type: 'security',
              message: "Failed login attempt for #{record[:email]} from IP #{record[:ip_address]}",
              line_number: record[:id],
              source: 'database',
              table: 'failed_login_attempts',
            }
          end
        end

        # Get account bans
        if DB.table_exists?(:account_bans)
          bans = DB[:account_bans]
            .order(Sequel.desc(:created_at))
            .offset(offset / 2)
            .limit(limit / 2)
            .all

          bans.each do |record|
            entries << {
              timestamp: record[:created_at],
              timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
              level: 'ERROR',
              level_class: 'danger',
              log_type: 'security',
              message: "Account ban for #{record[:email]} (Ban ##{record[:ban_count]}) - #{record[:reason]}",
              line_number: record[:id],
              source: 'database',
              table: 'account_bans',
            }
          end
        end

      when 'license'
        if DB.table_exists?(:license_audit_logs)
          audit_logs = DB[:license_audit_logs]
            .order(Sequel.desc(:created_at))
            .offset(offset)
            .limit(limit)
            .all

          audit_logs.each do |record|
            level = record[:success] ? 'INFO' : 'WARN'
            level_class = record[:success] ? 'info' : 'warning'

            message = "License #{record[:action]}"
            message += " for key #{record[:license_key_partial]}***" if record[:license_key_partial]
            message += " from IP #{record[:ip_address]}" if record[:ip_address]
            message += " - #{record[:failure_reason]}" if !record[:success] && record[:failure_reason]

            entries << {
              timestamp: record[:created_at],
              timestamp_formatted: record[:created_at].strftime('%Y-%m-%d %H:%M:%S'),
              level: level,
              level_class: level_class,
              log_type: 'license',
              message: message,
              line_number: record[:id],
              source: 'database',
              table: 'license_audit_logs',
            }
          end
        end

      when 'system'
        # For system logs, we could check various system events
        # For now, return empty array as system logs are mainly file-based
        entries = []
      end
    rescue StandardError => e
      puts "Error getting database log entries by type #{log_type}: #{e.message}"
      entries << {
        timestamp: Time.now,
        timestamp_formatted: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        level: 'ERROR',
        level_class: 'danger',
        log_type: 'system',
        message: "Failed to retrieve #{log_type} logs: #{e.message}",
        line_number: 0,
        source: 'database',
        table: 'error',
      }
    end

    # Sort by timestamp
    entries.sort_by { |entry| entry[:timestamp] }.reverse
  end
end

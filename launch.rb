#!/usr/bin/env ruby
# frozen_string_literal: true

# Source-License: Cross-Platform Launcher
# Automatically detects OS and Ruby version, then launches the application

require 'rbconfig'

class SourceLicenseLauncher
  REQUIRED_RUBY_VERSION = '3.4.4'

  def self.launch
    new.launch
  end

  def initialize
    @os = detect_os
    @ruby_version = RUBY_VERSION
    @script_dir = __dir__
  end

  def launch
    puts 'Source-License Application Launcher'
    puts '==================================='
    puts

    # Check Ruby version
    unless ruby_version_valid?
      puts "❌ Ruby version #{REQUIRED_RUBY_VERSION} or higher is required."
      puts "Current version: #{@ruby_version}"
      puts
      puts "Please install Ruby #{REQUIRED_RUBY_VERSION} or higher and try again."
      exit 1
    end

    puts "✅ Ruby version check passed (#{@ruby_version})"

    # Check for pending updates
    check_for_updates unless skip_update_check?

    # Check if bundler is installed
    unless bundler_installed?
      puts '❌ Bundler is not installed.'
      puts 'Installing bundler...'
      system('gem install bundler') || exit(1)
    end

    puts '✅ Bundler is available'

    # Check if gems are installed
    if gems_installed?
      puts '✅ Required gems are installed'
    else
      puts '📦 Installing required gems...'
      puts 'This may take a few minutes on first run...'
      puts

      if system('bundle install')
        puts '✅ Gems installed successfully'
      else
        puts '❌ Failed to install gems'
        exit 1
      end
    end

    # Check environment file
    check_environment_file

    # Test database connection and run migrations
    test_database_and_migrate

    # Show system information
    show_system_info

    # Launch the application
    launch_application
  end

  private

  def skip_update_check?
    # Load .env file early to check SKIP_UPDATE_CHECK setting
    load_env_file_early unless @env_loaded_early

    # Check for override flags (prioritized order)
    ENV['SKIP_UPDATE_CHECK']&.downcase == 'true' ||
      ARGV.include?('--skip-update-check') ||
      ARGV.include?('--force-start') ||
      ENV['APP_ENV'] == 'development'
  end

  def load_env_file_early
    return if @env_loaded_early

    env_file = File.join(@script_dir, '.env')
    if File.exist?(env_file)
      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        next unless key && value

        # Only set essential variables early, and only if not already set
        ENV[key] = value if %w[SKIP_UPDATE_CHECK APP_ENV].include?(key) && !ENV.key?(key)
      end
    end

    @env_loaded_early = true
  end

  def git_available?
    system('git --version > /dev/null 2>&1') || system('git --version > NUL 2>&1')
  end

  def in_git_repository?
    File.exist?(File.join(@script_dir, '.git'))
  end

  def check_for_updates
    puts
    puts 'Update Check:'
    puts '-------------'

    # Check if git is available
    unless git_available?
      puts '⚠️  Git not found - skipping update check'
      puts '💡 Install Git to enable automatic update checking'
      return
    end

    # Check if we're in a git repository
    unless in_git_repository?
      puts '⚠️  Not in a Git repository - skipping update check'
      puts '💡 Initialize Git repository to enable update checking'
      return
    end

    begin
      # Get current branch
      current_branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      if current_branch.empty?
        puts '⚠️  Could not determine current Git branch - skipping update check'
        return
      end

      puts "🔍 Checking for updates on branch '#{current_branch}'..."

      # Check if we have a remote origin
      remote_url = `git remote get-url origin 2>/dev/null`.strip
      if remote_url.empty?
        puts '⚠️  No remote origin configured - skipping update check'
        puts '💡 Add a remote origin to enable update checking'
        return
      end

      puts "📡 Remote: #{remote_url}"

      # Fetch latest changes (with timeout)
      puts '📥 Fetching latest changes from remote...'

      fetch_success = system("timeout 30 git fetch origin #{current_branch} 2>/dev/null") ||
                      system("git fetch origin #{current_branch} 2>/dev/null")

      unless fetch_success
        puts '⚠️  Failed to fetch from remote - continuing anyway'
        puts '💡 Check your internet connection and Git credentials'
        return
      end

      # Compare local and remote commits
      local_commit = `git rev-parse HEAD 2>/dev/null`.strip
      remote_commit = `git rev-parse origin/#{current_branch} 2>/dev/null`.strip

      if local_commit.empty? || remote_commit.empty?
        puts '⚠️  Could not compare local and remote commits - continuing anyway'
        return
      end

      if local_commit == remote_commit
        puts '✅ Repository is up to date'
        return
      end

      # Check if local is ahead of remote
      ahead_count = `git rev-list --count origin/#{current_branch}..HEAD 2>/dev/null`.strip.to_i
      behind_count = `git rev-list --count HEAD..origin/#{current_branch} 2>/dev/null`.strip.to_i

      if ahead_count.positive? && behind_count.zero?
        puts "✅ Local repository is #{ahead_count} commit(s) ahead of remote"
        return
      end

      if behind_count.positive?
        puts
        puts '🚨 PENDING UPDATES DETECTED!'
        puts '=' * 50
        puts "Your local repository is #{behind_count} commit(s) behind the remote."
        puts
        puts 'Recent changes available:'

        # Show recent commits
        recent_commits = `git log --oneline HEAD..origin/#{current_branch} 2>/dev/null | head -5`.strip
        unless recent_commits.empty?
          recent_commits.split("\n").each do |commit|
            puts "  • #{commit}"
          end

          total_commits = `git rev-list --count HEAD..origin/#{current_branch} 2>/dev/null`.strip.to_i
          puts "  ... and #{total_commits - 5} more commit(s)" if total_commits > 5
        end

        puts
        puts '🔧 RECOMMENDED ACTIONS:'
        puts '1. Run the update script: ./update.sh'
        puts "2. Or update manually: git pull origin #{current_branch}"
        puts '3. For deployed services: sudo ./deploy.sh update-service'
        puts
        puts '⚠️  SECURITY NOTICE:'
        puts 'Running outdated software may expose your system to security vulnerabilities.'
        puts 'It is strongly recommended to update before proceeding.'
        puts

        # Check for security-related keywords in commits
        security_commits = `git log --oneline HEAD..origin/#{current_branch} 2>/dev/null`.downcase
        has_security_updates = security_commits.match?(/security|vulnerability|cve|patch|fix|urgent/)

        if has_security_updates
          puts '🔴 CRITICAL: Security updates detected in pending changes!'
          puts 'Please update immediately before starting the application.'
          puts
        end

        handle_update_prompt(current_branch, has_security_updates)
      end
    rescue StandardError => e
      puts "⚠️  Update check failed: #{e.message}"
      puts '💡 Continuing with application startup anyway'
    end
  end

  def handle_update_prompt(branch, has_security_updates)
    if has_security_updates
      puts '❌ STARTUP BLOCKED: Critical security updates are available.'
      puts
      puts 'To continue anyway (NOT RECOMMENDED), use one of these options:'
      puts '1. Set environment variable: SKIP_UPDATE_CHECK=true'
      puts '2. Use command line flag: ruby launch.rb --force-start'
      puts '3. Set APP_ENV=development in your .env file'
      puts
      puts 'To update now:'
      puts '  ./update.sh    (recommended - automated update)'
      puts "  git pull origin #{branch} && bundle install    (manual update)"
      puts
      exit 1
    else
      puts 'Choose an action:'
      puts '  [1] Update now and restart (recommended)'
      puts '  [2] Continue without updating (not recommended)'
      puts '  [3] Exit and update manually'
      puts
      print 'Enter your choice [1-3]: '

      begin
        # Use a timeout for the input to avoid hanging in non-interactive environments
        choice = nil
        if $stdin.tty?
          choice = $stdin.gets&.chomp
        else
          # Non-interactive environment - default to exit
          puts '3 (non-interactive mode)'
          choice = '3'
        end

        puts
        case choice
        when '1'
          puts '🔄 Starting automatic update...'

          if File.exist?(File.join(@script_dir, 'update.sh'))
            puts 'Using update.sh script...'
            system("chmod +x #{File.join(@script_dir, 'update.sh')}")

            if system(File.join(@script_dir, 'update.sh'))
              puts '✅ Update completed successfully!'
              puts '🔄 Restarting application...'
              exec("ruby #{__FILE__}")
            else
              puts '❌ Update failed. Please update manually and try again.'
              exit 1
            end
          else
            puts 'Update script not found. Trying manual git pull...'
            if system("git pull origin #{branch}")
              puts '✅ Code updated successfully!'
              puts '📦 Installing/updating dependencies...'
              system('bundle install')
              puts '🔄 Restarting application...'
              exec("ruby #{__FILE__}")
            else
              puts '❌ Git pull failed. Please resolve conflicts and try again.'
              exit 1
            end
          end

        when '2'
          puts '⚠️  Continuing with outdated version...'
          puts '💡 Remember to update soon to get the latest features and security fixes.'
          puts

        when '3', '', nil
          puts '👋 Exiting for manual update...'
          puts
          puts 'To update, run one of these commands:'
          puts '  ./update.sh'
          puts "  git pull origin #{branch} && bundle install"
          puts
          exit 0

        else
          puts '❌ Invalid choice. Exiting for safety.'
          puts 'Use --force-start flag to bypass this check.'
          exit 1
        end
      rescue Interrupt
        puts "\n\n👋 Update cancelled by user. Exiting..."
        exit 0
      end
    end
  end

  def detect_os
    case RbConfig::CONFIG['host_os']
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
    when /darwin|mac os/
      :macos
    when /linux/
      :linux
    when /solaris|bsd/
      :unix
    else
      :unknown
    end
  end

  def ruby_version_valid?
    Gem::Version.new(@ruby_version) >= Gem::Version.new(REQUIRED_RUBY_VERSION)
  end

  def bundler_installed?
    system('bundle --version > /dev/null 2>&1') || system('bundle --version > NUL 2>&1')
  end

  def gems_installed?
    (File.exist?(File.join(@script_dir, 'Gemfile.lock')) &&
      system('bundle check > /dev/null 2>&1')) || system('bundle check > NUL 2>&1')
  end

  def check_environment_file
    env_file = File.join(@script_dir, '.env')
    env_example = File.join(@script_dir, '.env.example')

    if File.exist?(env_file)
      puts '✅ Environment file found'
    elsif File.exist?(env_example)
      puts '⚠️  Environment file (.env) not found'
      puts '📋 Copying .env.example to .env'

      begin
        File.write(env_file, File.read(env_example))
        puts '✅ Created .env file from template'
        puts
        puts '🔧 Please edit .env file to configure your settings:'
        puts '   - Database credentials'
        puts '   - Payment gateway settings (Stripe/PayPal)'
        puts '   - Email settings'
        puts '   - Admin credentials'
        puts
      rescue StandardError => e
        puts "❌ Failed to create .env file: #{e.message}"
      end
    else
      puts '⚠️  No environment configuration found'
      puts 'Please create a .env file with your configuration'
    end
  end

  def show_system_info
    puts
    puts 'System Information:'
    puts '-------------------'
    puts "Operating System: #{@os.to_s.capitalize}"
    puts "Ruby Version: #{@ruby_version}"
    puts "Ruby Platform: #{RbConfig::CONFIG['host']}"
    puts "Script Directory: #{@script_dir}"

    # Show available shells
    case @os
    when :windows
      puts 'Available Shells: PowerShell, Command Prompt'
      puts "PowerShell Version: #{powershell_version}" if ENV['PSModulePath']
    when :linux, :macos, :unix
      puts 'Available Shells: Bash, Zsh, etc.'
      puts "Current Shell: #{ENV['SHELL'] || 'Unknown'}"
    end

    puts
  end

  def test_database_and_migrate
    puts
    puts 'Database Setup:'
    puts '---------------'

    # Load environment variables
    load_environment

    # Test database connection and run migrations
    begin
      require_relative 'lib/database'

      puts '🔍 Testing database connection...'

      # Test the database setup
      Database.setup

      puts '✅ Database connection successful'
      puts '✅ Database migrations completed'

      # Create default admin user if none exists
      create_default_admin_user
    rescue StandardError => e
      puts "❌ Database setup failed: #{e.message}"
      puts

      # Handle specific database errors
      if e.message.include?('Incorrect MySQL client library version')
        puts '🔧 MySQL Client Library Version Mismatch Detected!'
        puts
        puts 'This error occurs when the mysql2 gem was compiled for a different MySQL version.'
        puts 'Here are several solutions:'
        puts
        puts '1. RECOMMENDED: Switch to SQLite (easier for development):'
        puts '   - Open .env file'
        puts '   - Change DATABASE_ADAPTER=sqlite'
        puts '   - Remove or comment out DATABASE_HOST, DATABASE_PORT, DATABASE_USER, DATABASE_PASSWORD'
        puts '   - Add DATABASE_NAME=source_license.db'
        puts
        puts '2. Reinstall mysql2 gem with correct MySQL version:'
        puts '   - Run: gem uninstall mysql2'
        puts '   - Run: bundle install'
        puts
        puts '3. Install compatible MySQL version:'
        puts '   - Download MySQL 8.0+ from https://dev.mysql.com/downloads/mysql/'
        puts '   - Or use XAMPP/WAMP which includes compatible MySQL'
        puts
        puts '4. Use PostgreSQL instead:'
        puts '   - Change DATABASE_ADAPTER=postgresql in .env'
        puts '   - Install PostgreSQL from https://www.postgresql.org/download/'
        puts
      elsif e.message.include?('unable to open database file') || e.message.include?('CantOpenException')
        puts '🔧 SQLite Database File Permission Issue Detected!'
        puts
        puts 'SQLite cannot create the database file due to permissions.'
        puts 'Here are several solutions:'
        puts
        puts '1. Run as administrator/elevated permissions:'
        puts '   - Windows: Right-click and "Run as administrator"'
        puts '   - Linux/Mac: Use "sudo ruby launch.rb"'
        puts
        puts '2. Change database location to a writable directory:'
        puts '   - Edit .env file'
        puts '   - Change DATABASE_NAME to: C:/temp/source_license.db (Windows)'
        puts '   - Or change to: /tmp/source_license.db (Linux/Mac)'
        puts
        puts '3. Create the database file manually:'
        puts '   - Create an empty file: source_license.db'
        puts '   - Ensure it has write permissions'
        puts
        puts '4. Use a different directory:'
        puts '   - Change to your user documents folder'
        puts '   - Or use the temp directory'
        puts
      else
        puts 'Please ensure:'
        puts '  1. Your database server is running'
        puts '  2. Database credentials in .env are correct'
        puts '  3. The database user has proper permissions'
        puts

        case ENV['DATABASE_ADAPTER']&.downcase
        when 'mysql'
          puts 'For MySQL:'
          puts '  - Ensure MySQL server is running'
          puts '  - Check DATABASE_HOST, DATABASE_PORT, DATABASE_USER, DATABASE_PASSWORD'
          puts '  - Database user should have CREATE, ALTER, INSERT, SELECT, UPDATE, DELETE privileges'
        when 'postgresql', 'postgres'
          puts 'For PostgreSQL:'
          puts '  - Ensure PostgreSQL server is running'
          puts '  - Check DATABASE_HOST, DATABASE_PORT, DATABASE_USER, DATABASE_PASSWORD'
          puts '  - Database user should have CREATEDB and standard privileges'
        else
          puts 'Database adapter not configured. Please set DATABASE_ADAPTER in .env'
        end
      end

      puts
      puts 'Would you like to continue anyway? (y/N)'
      response = $stdin.gets.chomp.downcase

      unless %w[y yes].include?(response)
        puts 'Exiting due to database connection failure.'
        exit 1
      end

      puts '⚠️  Continuing without database - some features may not work'
    end
  end

  def create_default_admin_user
    # Load models to access Admin class
    require_relative 'lib/models'
    require 'bcrypt'

    # Check if any admin users already exist
    if defined?(Admin) && Admin.any?
      puts '✅ Admin user already exists'
      return
    end

    # Get admin credentials from environment
    admin_email = ENV['INITIAL_ADMIN_EMAIL'] || 'admin@yourdomain.com'
    admin_password = ENV['INITIAL_ADMIN_PASSWORD'] || 'admin123'

    # Create the admin user using the secure method
    admin = Admin.create_secure_admin(admin_email, admin_password, ['admin'])

    if admin
      puts '✅ Default admin user created successfully'
      puts "   Email: #{admin_email}"
      puts "   Password: #{admin_password}"
      puts
      puts '⚠️  IMPORTANT: Please change the default admin password after first login!'
      puts '   You can do this through the admin panel or by updating the .env file'
    else
      puts '⚠️  Failed to create default admin user'
    end
  rescue StandardError => e
    puts "⚠️  Could not create admin user: #{e.message}"
    puts '   This is not critical - you can create an admin user manually'
  end

  def load_environment
    env_file = File.join(@script_dir, '.env')
    env_example = File.join(@script_dir, '.env.example')

    puts '🔧 Loading environment configuration...'

    # Get all environment variables from .env.example
    required_env_vars = []
    if File.exist?(env_example)
      File.readlines(env_example).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, _value = line.split('=', 2)
        next unless key

        # Skip commented out variables
        next if key.start_with?('#')

        required_env_vars << key
      end
    else
      # Fallback to essential variables if .env.example doesn't exist
      required_env_vars = %w[
        APP_ENV APP_SECRET APP_HOST APP_PORT JWT_SECRET
        DATABASE_ADAPTER DATABASE_HOST DATABASE_PORT DATABASE_NAME DATABASE_USER DATABASE_PASSWORD
        INITIAL_ADMIN_EMAIL INITIAL_ADMIN_PASSWORD
        STRIPE_PUBLISHABLE_KEY STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET
        PAYPAL_CLIENT_ID PAYPAL_CLIENT_SECRET PAYPAL_ENVIRONMENT
        SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_TLS
      ]
    end

    # Check which variables are already set in the environment
    existing_vars = required_env_vars.select { |var| ENV.fetch(var, nil) }
    missing_vars = required_env_vars - existing_vars

    puts "📋 Found #{required_env_vars.length} possible environment variables"
    puts "✅ Already set: #{existing_vars.length} variables"
    puts "⚠️  Missing: #{missing_vars.length} variables"

    if existing_vars.any?
      puts
      puts 'Existing environment variables:'
      existing_vars.first(5).each do |var|
        # Show value for non-sensitive variables, hide for sensitive ones
        if var.include?('SECRET') || var.include?('PASSWORD') || var.include?('KEY')
          puts "   #{var}: [HIDDEN]"
        else
          puts "   #{var}: #{ENV.fetch(var, nil)}"
        end
      end

      puts "   ... and #{existing_vars.length - 5} more" if existing_vars.length > 5
    end

    # Load .env file only for missing variables
    if File.exist?(env_file) && missing_vars.any?
      puts
      puts '📁 Loading missing variables from .env file...'

      loaded_count = 0
      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        next unless key && value

        # Only set if not already in environment
        unless ENV[key]
          ENV[key] = value
          loaded_count += 1 if missing_vars.include?(key)
        end
      end

      puts "   Loaded #{loaded_count} missing variables from .env"
    elsif !File.exist?(env_file) && missing_vars.any?
      puts
      puts '⚠️  No .env file found and missing environment variables'
      puts '💡 You can either:'
      puts '   1. Create a .env file (will copy from .env.example)'
      puts '   2. Set environment variables directly:'
      puts '      DATABASE_ADAPTER=sqlite APP_SECRET=dev_secret JWT_SECRET=jwt_secret ruby launch.rb'
      puts
      puts 'Missing variables:'
      missing_vars.first(10).each do |var|
        puts "   - #{var}"
      end
      puts "   ... and #{missing_vars.length - 10} more" if missing_vars.length > 10
      puts
    elsif missing_vars.empty?
      puts '✅ All environment variables are set!'
    end

    # Show essential configuration
    puts
    puts 'Essential Configuration:'
    puts '------------------------'
    puts "DATABASE_ADAPTER: #{ENV['DATABASE_ADAPTER'] || 'NOT SET'}"
    puts "APP_ENV: #{ENV['APP_ENV'] || 'development'}"
    puts "APP_HOST: #{ENV['APP_HOST'] || 'localhost'}"
    puts "APP_PORT: #{ENV['APP_PORT'] || '4567'}"
    puts "INITIAL_ADMIN_EMAIL: #{ENV['INITIAL_ADMIN_EMAIL'] || 'NOT SET'}"

    # Show payment configuration status
    stripe_configured = ENV.fetch('STRIPE_SECRET_KEY', nil) && !ENV['STRIPE_SECRET_KEY'].empty?
    paypal_configured = ENV.fetch('PAYPAL_CLIENT_ID', nil) && !ENV['PAYPAL_CLIENT_ID'].empty?
    puts "STRIPE: #{stripe_configured ? '✅ Configured' : '❌ Not configured'}"
    puts "PAYPAL: #{paypal_configured ? '✅ Configured' : '❌ Not configured'}"

    # Show email configuration status
    email_configured = ENV.fetch('SMTP_HOST', nil) && !ENV['SMTP_HOST'].empty?
    puts "EMAIL: #{email_configured ? '✅ Configured' : '❌ Not configured'}"
    puts
  end

  def powershell_version
    version_output = `powershell -Command "$PSVersionTable.PSVersion.Major" 2>NUL`.strip
    version_output.empty? ? 'Unknown' : "#{version_output}.x"
  rescue StandardError
    'Unknown'
  end

  def launch_application
    puts '🚀 Starting Source-License Application...'
    puts 'Press Ctrl+C to stop the server'
    puts

    # Determine the best way to launch based on OS
    case @os
    when :windows
      launch_on_windows
    else
      launch_on_unix
    end
  end

  def launch_on_windows
    # Try PowerShell first, then fall back to cmd
    if ENV['PSModulePath'] && system('powershell -Command "exit 0" > NUL 2>&1')
      puts 'Using PowerShell to launch application...'

      # Create PowerShell script
      ps_script = create_powershell_script

      # Execute the PowerShell script
      exec("powershell -ExecutionPolicy Bypass -File \"#{ps_script}\"")
    else
      puts 'Using Command Prompt to launch application...'

      # Create batch script
      batch_script = create_batch_script

      # Execute the batch script
      exec("\"#{batch_script}\"")
    end
  end

  def launch_on_unix
    # Use bash script
    puts 'Using Bash to launch application...'

    bash_script = create_bash_script

    # Make executable and run
    File.chmod(0o755, bash_script)
    exec("bash \"#{bash_script}\"")
  end

  def create_powershell_script
    script_path = File.join(@script_dir, 'launch.ps1')

    script_content = <<~POWERSHELL
      # Source-License PowerShell Launcher

      Write-Host "Starting Source-License Application..." -ForegroundColor Green
      Write-Host "Application will be available at: http://localhost:4567" -ForegroundColor Cyan
      Write-Host "Admin panel will be available at: http://localhost:4567/admin" -ForegroundColor Cyan
      Write-Host ""
      Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
      Write-Host ""

      Set-Location "#{@script_dir}"

      try {
          bundle exec puma -C puma.rb config.ru
      }
      catch {
          Write-Host "Error starting application: $_" -ForegroundColor Red
          Write-Host "Please check your configuration and try again." -ForegroundColor Red
          Read-Host "Press Enter to exit"
          exit 1
      }
    POWERSHELL

    File.write(script_path, script_content)
    script_path
  end

  def create_batch_script
    script_path = File.join(@script_dir, 'launch.bat')

    script_content = <<~BATCH
      @echo off
      REM Source-License Batch Launcher

      echo Starting Source-License Application...
      echo Application will be available at: http://localhost:4567
      echo Admin panel will be available at: http://localhost:4567/admin
      echo.
      echo Press Ctrl+C to stop the server
      echo.

      cd /d "#{@script_dir}"

      bundle exec puma -C puma.rb config.ru

      if errorlevel 1 (
          echo Error starting application
          echo Please check your configuration and try again.
          pause
          exit /b 1
      )
    BATCH

    File.write(script_path, script_content)
    script_path
  end

  def create_bash_script
    script_path = File.join(@script_dir, 'launch.sh')

    script_content = <<~BASH
      #!/bin/bash
      # Source-License Bash Launcher

      echo "Starting Source-License Application..."
      echo "Application will be available at: http://localhost:4567"
      echo "Admin panel will be available at: http://localhost:4567/admin"
      echo ""
      echo "Press Ctrl+C to stop the server"
      echo ""

      cd "#{@script_dir}"

      if bundle exec puma -C puma.rb config.ru; then
          echo "Application stopped normally"
      else
          echo "Error starting application"
          echo "Please check your configuration and try again."
          read -p "Press Enter to exit"
          exit 1
      fi
    BASH

    File.write(script_path, script_content)
    script_path
  end
end

# Run the launcher if this file is executed directly
if __FILE__ == $0
  begin
    SourceLicenseLauncher.launch
  rescue Interrupt
    puts "\n\n👋 Application stopped by user"
    exit 0
  rescue StandardError => e
    puts "\n❌ Fatal error: #{e.message}"
    puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
    exit 1
  end
end

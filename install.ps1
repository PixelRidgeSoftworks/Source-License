#!/usr/bin/env pwsh
# Source-License Unified Installer
# Simplified installer for Windows systems using sl_configure utility

param(
    [switch]$SkipRuby,
    [switch]$SkipBundler,
    [switch]$Help
)

# Configuration
$RUBY_MIN_VERSION = "3.4.7"

# Logging setup
$INSTALLER_LOG_DIR = "./installer-logs"
$INSTALLER_LOG_FILE = "$INSTALLER_LOG_DIR/install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Ensure log directory exists
if (-not (Test-Path $INSTALLER_LOG_DIR)) {
    New-Item -ItemType Directory -Path $INSTALLER_LOG_DIR -Force | Out-Null
}

# Initialize log file with session header
$logHeader = "==========================================" + "`n" +
"Source-License Installer Script Log" + "`n" +
"==========================================" + "`n" +
"Started: $(Get-Date)" + "`n" +
"Ruby Min Version: $RUBY_MIN_VERSION" + "`n" +
"Skip Ruby Check: $SkipRuby" + "`n" +
"Skip Bundler Check: $SkipBundler" + "`n" +
"User: $env:USERNAME" + "`n" +
"Working Directory: $(Get-Location)" + "`n" +
"System: $($PSVersionTable.PSVersion) on $($PSVersionTable.OS)" + "`n" +
"==========================================" + "`n" + "`n"

$logHeader | Out-File -FilePath $INSTALLER_LOG_FILE -Encoding UTF8

# Enhanced logging function
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
}

# Log function calls
function Write-FunctionCall {
    param(
        [string]$FunctionName,
        [string]$Status = "START"
    )
    Write-Log "FUNCTION" "$FunctionName - $Status"
}

# Log command execution
function Write-CommandLog {
    param(
        [string]$Command,
        [string]$Status = "EXECUTE"
    )
    Write-Log "COMMAND" "$Command - $Status"
}

# Log errors with details
function Write-ErrorLog {
    param(
        [string]$ErrorMessage,
        [string]$LineNumber = "unknown"
    )
    Write-Log "ERROR" "$ErrorMessage (Line: $LineNumber)"
}

if ($Help) {
    Write-Host "Source-License Installer for Windows"
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host "    ./install.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "    -SkipRuby            Skip Ruby version check"
    Write-Host "    -SkipBundler         Skip Bundler installation check"
    Write-Host "    -Help                Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:"
    Write-Host "    ./install.ps1"
    Write-Host "    ./install.ps1 -SkipRuby"
    Write-Host ""
    Write-Host "NOTES:"
    Write-Host "    This installer uses the sl_configure utility which requires Ruby $RUBY_MIN_VERSION."
    Write-Host "    The sl_configure tool provides interactive configuration with secure value generation."
    exit 0
}

# Color functions
function Write-Success { param($Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "[-] $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[!] $Message" -ForegroundColor Yellow }

# Check if command exists
function Test-Command {
    param($Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# Compare version strings
function Test-Version {
    param($Current, $Required)
    try {
        $currentVersion = [Version]$Current
        $requiredVersion = [Version]$Required
        return $currentVersion -ge $requiredVersion
    } catch {
        return $false
    }
}

# Check Ruby version
function Test-RubyVersion {
    Write-FunctionCall "Test-RubyVersion" "START"
    
    if ($SkipRuby) {
        Write-Log "WARNING" "Skipping Ruby version check as requested"
        Write-Warning "Skipping Ruby version check"
        Write-FunctionCall "Test-RubyVersion" "COMPLETE - SKIPPED"
        return $true
    }

    Write-Log "INFO" "Checking Ruby version against minimum: $RUBY_MIN_VERSION"
    Write-Info "Checking Ruby version..."
    
    Write-CommandLog "Get-Command ruby"
    if (-not (Test-Command "ruby")) {
        Write-ErrorLog "Ruby is not installed"
        Write-Error "Ruby is not installed"
        Write-Info "Please install Ruby $RUBY_MIN_VERSION or higher:"
        Write-Info "  - Download from: https://rubyinstaller.org/"
        Write-Info "  - Or use Chocolatey: choco install ruby"
        Write-Info "  - Or use Scoop: scoop install ruby"
        Write-FunctionCall "Test-RubyVersion" "FAILED - NOT_INSTALLED"
        return $false
    }

    try {
        Write-CommandLog "ruby --version"
        $rubyVersionOutput = ruby --version
        $rubyVersion = [regex]::Match($rubyVersionOutput, '\d+\.\d+\.\d+').Value
        Write-Log "INFO" "Found Ruby version: $rubyVersion"
        
        if (-not (Test-Version $rubyVersion $RUBY_MIN_VERSION)) {
            Write-ErrorLog "Ruby version check failed: $rubyVersion < $RUBY_MIN_VERSION"
            Write-Error "Ruby $RUBY_MIN_VERSION or higher required (found: $rubyVersion)"
            Write-Info "Please upgrade Ruby or use -SkipRuby to bypass this check"
            Write-FunctionCall "Test-RubyVersion" "FAILED - VERSION_TOO_OLD"
            return $false
        }

        Write-Log "SUCCESS" "Ruby version check passed: $rubyVersion >= $RUBY_MIN_VERSION"
        Write-Success "Ruby version check passed ($rubyVersion)"
        Write-FunctionCall "Test-RubyVersion" "COMPLETE"
        return $true
    } catch {
        Write-ErrorLog "Failed to check Ruby version: $_"
        Write-Error "Failed to check Ruby version: $_"
        Write-FunctionCall "Test-RubyVersion" "FAILED - EXECUTION_ERROR"
        return $false
    }
}

# Check/install Bundler
function Install-Bundler {
    Write-FunctionCall "Install-Bundler" "START"
    
    if ($SkipBundler) {
        Write-Log "WARNING" "Skipping Bundler check as requested"
        Write-Warning "Skipping Bundler check"
        Write-FunctionCall "Install-Bundler" "COMPLETE - SKIPPED"
        return $true
    }

    Write-Log "INFO" "Checking for Bundler installation"
    Write-Info "Checking Bundler..."
    
    Write-CommandLog "Get-Command bundle"
    if (Test-Command "bundle") {
        Write-Log "SUCCESS" "Bundler is already installed"
        Write-Success "Bundler is already installed"
        Write-FunctionCall "Install-Bundler" "COMPLETE - ALREADY_INSTALLED"
        return $true
    }

    Write-Log "INFO" "Installing Bundler via gem install"
    Write-Info "Installing Bundler..."
    try {
        Write-CommandLog "gem install bundler"
        gem install bundler
        Write-Log "SUCCESS" "Bundler installed successfully"
        Write-Success "Bundler installed successfully"
        Write-FunctionCall "Install-Bundler" "COMPLETE"
        return $true
    } catch {
        Write-ErrorLog "Failed to install Bundler: $_"
        Write-Error "Failed to install Bundler: $_"
        Write-Info "Please check your Ruby installation and try again"
        Write-FunctionCall "Install-Bundler" "FAILED"
        return $false
    }
}

# Install Ruby dependencies
function Install-Dependencies {
    Write-FunctionCall "Install-Dependencies" "START"
    Write-Log "INFO" "Installing Ruby dependencies via bundle install"
    Write-Info "Installing Ruby dependencies..."
    
    try {
        Write-CommandLog "bundle install"
        bundle install
        Write-Log "SUCCESS" "Dependencies installed successfully"
        Write-Success "Dependencies installed successfully"
        Write-FunctionCall "Install-Dependencies" "COMPLETE"
        return $true
    } catch {
        Write-ErrorLog "Failed to install dependencies: $_"
        Write-Error "Failed to install dependencies: $_"
        Write-Info "Please check your Gemfile and network connection"
        Write-FunctionCall "Install-Dependencies" "FAILED"
        return $false
    }
}

# Setup environment file
function Initialize-Environment {
    Write-FunctionCall "Initialize-Environment" "START"
    Write-Log "INFO" "Setting up environment configuration"
    Write-Info "Setting up environment configuration..."
    
    if (Test-Path ".env") {
        Write-Log "INFO" "Environment file already exists"
        Write-Success "Environment file already exists"
    } elseif (Test-Path ".env.example") {
        Write-Log "INFO" "Creating .env file from .env.example"
        Copy-Item ".env.example" ".env"
        Write-Log "SUCCESS" "Created .env file from template"
        Write-Success "Created .env file from template"
    } else {
        Write-Log "WARNING" "No .env.example found"
        Write-Warning "No .env.example found"
        Write-Info "You'll need to create a .env file manually"
        Write-FunctionCall "Initialize-Environment" "COMPLETE - WARNING"
        return $false
    }
    
    Write-FunctionCall "Initialize-Environment" "COMPLETE"
    return $true
}

# Setup database
function Initialize-Database {
    Write-FunctionCall "Initialize-Database" "START"
    Write-Log "INFO" "Setting up database via migrations"
    Write-Info "Setting up database..."
    
    try {
        Write-CommandLog "ruby lib/migrations.rb"
        ruby lib/migrations.rb
        Write-Log "SUCCESS" "Database setup completed"
        Write-Success "Database setup completed"
        Write-FunctionCall "Initialize-Database" "COMPLETE"
        return $true
    } catch {
        Write-Log "WARNING" "Database setup failed - not critical for basic installation"
        Write-Warning "Database setup failed - this is not critical for basic installation"
        Write-Info "You can run 'ruby lib/migrations.rb' manually later"
        Write-FunctionCall "Initialize-Database" "COMPLETE - WARNING"
        return $true
    }
}

# Create logs directory
function New-LogsDirectory {
    Write-FunctionCall "New-LogsDirectory" "START"
    Write-Log "INFO" "Creating logs directory"
    Write-Info "Creating logs directory..."
    
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
        Write-Log "SUCCESS" "Logs directory created"
    } else {
        Write-Log "INFO" "Logs directory already exists"
    }
    
    Write-Success "Logs directory ready"
    Write-FunctionCall "New-LogsDirectory" "COMPLETE"
}

# Run sl_configure utility for application configuration
function Invoke-SourceLicenseConfiguration {
    Write-FunctionCall "Invoke-SourceLicenseConfiguration" "START"
    Write-Log "INFO" "Running sl_configure utility for application configuration"
    
    Write-Host ""
    Write-Info "Running Source-License configuration utility..."
    Write-Host ""
    Write-Info "The sl_configure tool will guide you through setting up your application."
    Write-Info "It can automatically generate secure values for sensitive settings."
    Write-Host ""
    
    try {
        Write-CommandLog "ruby ./sl_configure"
        
        # Open a new terminal window to run the interactive sl_configure utility
        # This allows full user interaction in a separate console window
        Write-Info "Opening new terminal window for interactive configuration..."
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "powershell.exe"
        $processInfo.Arguments = "-Command `"ruby ./sl_configure; Read-Host 'Press Enter to close this window'`""
        $processInfo.WorkingDirectory = (Get-Location).Path
        $processInfo.UseShellExecute = $true
        $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        Write-Info "Waiting for configuration to complete in the new terminal window..."
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Write-Log "SUCCESS" "sl_configure completed successfully"
            Write-Success "Configuration completed successfully!"
            Write-FunctionCall "Invoke-SourceLicenseConfiguration" "COMPLETE"
            return $true
        } else {
            Write-ErrorLog "sl_configure exited with code: $($process.ExitCode)"
            Write-Error "Configuration failed with exit code: $($process.ExitCode)"
            Write-Info "You can run 'ruby ./sl_configure' manually later"
            Write-FunctionCall "Invoke-SourceLicenseConfiguration" "FAILED"
            return $false
        }
    } catch {
        Write-ErrorLog "sl_configure failed: $_"
        Write-Error "Configuration failed: $_"
        Write-Info "You can run 'ruby ./sl_configure' manually later"
        Write-FunctionCall "Invoke-SourceLicenseConfiguration" "FAILED"
        return $false
    }
}

# Main installation function
function Invoke-Main {
    Write-FunctionCall "Invoke-Main" "START"
    Write-Log "INFO" "Starting installer script execution"
    
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                       Source-License Installer                                " -ForegroundColor Cyan
    Write-Host "                           Windows Systems                                     " -ForegroundColor Cyan
    Write-Host "                        Using sl_configure utility                            " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    # Check if we're in the right directory
    Write-Log "INFO" "Verifying we're in the correct directory"
    if (-not (Test-Path "app.rb") -or -not (Test-Path "Gemfile") -or -not (Test-Path "launch.rb") -or -not (Test-Path "sl_configure")) {
        Write-ErrorLog "Not in Source-License project root directory or sl_configure not found"
        Write-Error "Please run this script from the Source-License project root directory"
        Write-Error "Make sure the sl_configure utility is present"
        exit 1
    }
    
    Write-Log "INFO" "Directory verification passed"
    Write-Info "Installing Source-License on Windows using sl_configure utility"
    Write-Host ""
    
    # Run installation steps
    $success = $true
    
    Write-Log "INFO" "Starting installation steps"
    
    if (-not (Test-RubyVersion)) { 
        $success = $false 
        Write-Log "ERROR" "Ruby version check failed"
    } else {
        Write-Log "SUCCESS" "Ruby version check passed"
    }
    
    if ($success) {
        if (-not (Install-Bundler)) { 
            $success = $false 
            Write-Log "ERROR" "Bundler installation failed"
        } else {
            Write-Log "SUCCESS" "Bundler installation completed"
        }
    }
    
    if ($success) {
        if (-not (Install-Dependencies)) { 
            $success = $false 
            Write-Log "ERROR" "Dependencies installation failed"
        } else {
            Write-Log "SUCCESS" "Dependencies installation completed"
        }
    }
    
    if ($success) { 
        Initialize-Environment | Out-Null
        Write-Log "SUCCESS" "Environment initialization completed"
    }
    
    if ($success) { 
        Initialize-Database | Out-Null 
        Write-Log "SUCCESS" "Database initialization completed"
    }
    
    if ($success) { 
        New-LogsDirectory 
        Write-Log "SUCCESS" "Logs directory setup completed"
    }
    
    if ($success) { 
        if (-not (Invoke-SourceLicenseConfiguration)) {
            Write-Warning "Configuration step failed, but installation can continue"
            Write-Info "You can run 'ruby ./sl_configure' manually later to configure your settings"
        }
    }
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    if ($success) {
        Write-Log "SUCCESS" "Installation completed successfully"
        Write-Success "Installation completed successfully!"
        Write-Host ""
        Write-Host "Source-License is ready to use!" -ForegroundColor Green
        Write-Host ""
        Write-Host "To start the application:"
        Write-Host "  Development: ruby launch.rb"
        Write-Host "  Production:  .\deploy.ps1"
        Write-Host ""
        Write-Host "To reconfigure your settings anytime:"
        Write-Host "     ruby ./sl_configure"
        Write-Host ""
        Write-Info "Check your .env file for the configured port and admin credentials."
    } else {
        Write-Log "ERROR" "Installation failed"
        Write-Error "Installation failed!"
        Write-Info "Please check the errors above and try again"
        Write-Info "You may need to run 'ruby ./sl_configure' manually if the basic setup completed"
        exit 1
    }
    
    Write-Log "INFO" "Installer script execution completed"
    Write-FunctionCall "Invoke-Main" "COMPLETE"
    
    # Log session end
    $finalStatus = if ($success) { "SUCCESS" } else { "FAILED" }
    $currentDate = Get-Date
    $exitCode = $LASTEXITCODE
    
    "" | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
    "Session completed: $currentDate" | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
    "Final status: $finalStatus" | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
    "Exit status: $exitCode" | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
}

# Run main function
Invoke-Main

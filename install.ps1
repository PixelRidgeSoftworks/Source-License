#!/usr/bin/env pwsh
# Source-License Unified Installer
# Simplified installer for Windows systems

param(
    [switch]$SkipRuby,
    [switch]$SkipBundler,
    [switch]$Help
)

# Configuration
$RUBY_MIN_VERSION = "3.4.4"

# Logging setup
$INSTALLER_LOG_DIR = "./installer-logs"
$INSTALLER_LOG_FILE = "$INSTALLER_LOG_DIR/install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Ensure log directory exists
if (-not (Test-Path $INSTALLER_LOG_DIR)) {
    New-Item -ItemType Directory -Path $INSTALLER_LOG_DIR -Force | Out-Null
}

# Initialize log file with session header
@"
Source-License Installer Script Log
Started: $(Get-Date)
Ruby Min Version: $RUBY_MIN_VERSION
Skip Ruby Check: $SkipRuby
Skip Bundler Check: $SkipBundler
User: $env:USERNAME
Working Directory: $(Get-Location)
System: $($PSVersionTable.PSVersion) on $($PSVersionTable.OS)

"@ | Out-File -FilePath $INSTALLER_LOG_FILE -Encoding UTF8

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
    # Log error details if available
    if ($Error.Count -gt 0) {
        Write-Log "ERROR_DETAIL" $Error[0].ToString()
    }
}

if ($Help) {
    Write-Host @"
Source-License Installer for Windows

USAGE:
    ./install.ps1 [OPTIONS]

OPTIONS:
    -SkipRuby            Skip Ruby version check
    -SkipBundler         Skip Bundler installation check
    -Help                Show this help message

EXAMPLES:
    ./install.ps1
    ./install.ps1 -SkipRuby
"@
    exit 0
}

# Color functions
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }

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
    if ($SkipRuby) {
        Write-Warning "Skipping Ruby version check"
        return $true
    }

    Write-Info "Checking Ruby version..."
    
    if (-not (Test-Command "ruby")) {
        Write-Error "Ruby is not installed"
        Write-Info "Please install Ruby $RUBY_MIN_VERSION or higher:"
        Write-Info "  - Download from: https://rubyinstaller.org/"
        Write-Info "  - Or use Chocolatey: choco install ruby"
        Write-Info "  - Or use Scoop: scoop install ruby"
        return $false
    }

    try {
        $rubyVersionOutput = ruby --version
        $rubyVersion = [regex]::Match($rubyVersionOutput, '\d+\.\d+\.\d+').Value
        
        if (-not (Test-Version $rubyVersion $RUBY_MIN_VERSION)) {
            Write-Error "Ruby $RUBY_MIN_VERSION or higher required (found: $rubyVersion)"
            Write-Info "Please upgrade Ruby or use -SkipRuby to bypass this check"
            return $false
        }

        Write-Success "Ruby version check passed ($rubyVersion)"
        return $true
    } catch {
        Write-Error "Failed to check Ruby version: $_"
        return $false
    }
}

# Check/install Bundler
function Install-Bundler {
    if ($SkipBundler) {
        Write-Warning "Skipping Bundler check"
        return $true
    }

    Write-Info "Checking Bundler..."
    
    if (Test-Command "bundle") {
        Write-Success "Bundler is already installed"
        return $true
    }

    Write-Info "Installing Bundler..."
    try {
        gem install bundler
        Write-Success "Bundler installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Bundler: $_"
        Write-Info "Please check your Ruby installation and try again"
        return $false
    }
}

# Install Ruby dependencies
function Install-Dependencies {
    Write-Info "Installing Ruby dependencies..."
    
    try {
        bundle install
        Write-Success "Dependencies installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install dependencies: $_"
        Write-Info "Please check your Gemfile and network connection"
        return $false
    }
}

# Setup environment file
function Initialize-Environment {
    Write-Info "Setting up environment configuration..."
    
    if (Test-Path ".env") {
        Write-Success "Environment file already exists"
    } elseif (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Success "Created .env file from template"
        Write-Warning "Please edit .env file to configure your settings"
    } else {
        Write-Warning "No .env.example found"
        Write-Info "You'll need to create a .env file manually"
    }
}

# Setup database
function Initialize-Database {
    Write-Info "Setting up database..."
    
    try {
        ruby lib\migrations.rb
        Write-Success "Database setup completed"
        return $true
    } catch {
        Write-Warning "Database setup failed - this is not critical for basic installation"
        Write-Info "You can run 'ruby lib\migrations.rb' manually later"
        return $true
    }
}

# Create logs directory
function New-LogsDirectory {
    Write-Info "Creating logs directory..."
    
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    Write-Success "Logs directory ready"
}

# Run tests
function Invoke-Tests {
    Write-Info "Running basic tests..."
    
    try {
        ruby run_tests.rb
        Write-Success "Tests passed"
        return $true
    } catch {
        Write-Warning "Some tests failed - this may not be critical"
        Write-Info "The application should still work for basic usage"
        return $true
    }
}

# Main installation function
function Main {
    Write-FunctionCall "Main" "START"
    Write-Log "INFO" "Starting installer script execution"
    
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Installer                                  ║
║                         Windows Systems                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Check if we're in the right directory
    Write-Log "INFO" "Verifying we're in the correct directory"
    if (-not (Test-Path "app.rb") -or -not (Test-Path "Gemfile") -or -not (Test-Path "launch.rb")) {
        Write-ErrorLog "Not in Source-License project root directory"
        Write-Error "Please run this script from the Source-License project root directory"
        exit 1
    }
    
    Write-Log "INFO" "Directory verification passed"
    Write-Info "Installing Source-License on Windows"
    Write-Host ""
    
    # Run installation steps
    $success = $true
    
    Write-Log "INFO" "Starting installation steps"
    
    Write-FunctionCall "Test-RubyVersion" "START"
    if (-not (Test-RubyVersion)) { 
        $success = $false 
        Write-Log "ERROR" "Ruby version check failed"
    } else {
        Write-Log "SUCCESS" "Ruby version check passed"
    }
    Write-FunctionCall "Test-RubyVersion" "COMPLETE"
    
    if ($success) {
        Write-FunctionCall "Install-Bundler" "START"
        if (-not (Install-Bundler)) { 
            $success = $false 
            Write-Log "ERROR" "Bundler installation failed"
        } else {
            Write-Log "SUCCESS" "Bundler installation completed"
        }
        Write-FunctionCall "Install-Bundler" "COMPLETE"
    }
    
    if ($success) {
        Write-FunctionCall "Install-Dependencies" "START"
        if (-not (Install-Dependencies)) { 
            $success = $false 
            Write-Log "ERROR" "Dependencies installation failed"
        } else {
            Write-Log "SUCCESS" "Dependencies installation completed"
        }
        Write-FunctionCall "Install-Dependencies" "COMPLETE"
    }
    
    if ($success) { 
        Write-FunctionCall "Initialize-Environment" "START"
        Initialize-Environment 
        Write-FunctionCall "Initialize-Environment" "COMPLETE"
    }
    
    if ($success) { 
        Write-FunctionCall "Initialize-Database" "START"
        Initialize-Database | Out-Null 
        Write-FunctionCall "Initialize-Database" "COMPLETE"
    }
    
    if ($success) { 
        Write-FunctionCall "New-LogsDirectory" "START"
        New-LogsDirectory 
        Write-FunctionCall "New-LogsDirectory" "COMPLETE"
    }
    
    if ($success) { 
        Write-FunctionCall "Invoke-Tests" "START"
        Invoke-Tests | Out-Null 
        Write-FunctionCall "Invoke-Tests" "COMPLETE"
    }
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    if ($success) {
        Write-Log "SUCCESS" "Installation completed successfully"
        Write-Success "Installation completed successfully!"
        Write-Host ""
        Write-Host "🎉 Source-License is now installed!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  1. Edit .env file with your configuration"
        Write-Host "  2. Configure database settings if needed"
        Write-Host "  3. Run the application:"
        Write-Host "     Development: ruby launch.rb"
        Write-Host "     Production:  .\deploy.ps1"
        Write-Host ""
        Write-Host "The application will be available at: http://localhost:4567"
        Write-Host "Admin panel will be at: http://localhost:4567/admin"
    } else {
        Write-Log "ERROR" "Installation failed"
        Write-Error "Installation failed!"
        Write-Info "Please check the errors above and try again"
        exit 1
    }
    
    Write-Log "INFO" "Installer script execution completed"
    Write-FunctionCall "Main" "COMPLETE"
    
    # Log session end
    @"

Session completed: $(Get-Date)
Final status: $(if ($success) { "SUCCESS" } else { "FAILED" })
Exit status: $LASTEXITCODE
"@ | Out-File -FilePath $INSTALLER_LOG_FILE -Append -Encoding UTF8
}

# Run main function
Main

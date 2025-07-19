#!/usr/bin/env pwsh
# PowerShell Installation Script for Source License Management System
# Windows-only installer

param(
    [string]$Domain = "localhost",
    [string]$Port = "4567",
    [string]$Environment = "production",
    [switch]$SkipRuby,
    [switch]$SkipNginx,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Source License Management System - Windows Installer

USAGE:
    ./install.ps1 [OPTIONS]

OPTIONS:
    -Domain <domain>      Domain name for the application (default: localhost)
    -Port <port>          Port for the application (default: 4567)
    -Environment <env>    Environment (development/production, default: production)
    -SkipRuby            Skip Ruby installation
    -SkipNginx           Skip Nginx installation
    -Help                Show this help message

EXAMPLES:
    ./install.ps1
    ./install.ps1 -Domain "license.example.com" -Port "3000"
    ./install.ps1 -Environment "development" -SkipNginx
"@
    exit 0
}

# Color functions
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }

# Check if running as administrator
function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if command exists
function Test-Command {
    param($Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# Install Chocolatey
function Install-Chocolatey {
    if (Test-Command "choco") {
        Write-Success "Chocolatey already installed"
        return $true
    }
    
    Write-Info "Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Success "Chocolatey installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Chocolatey: $_"
        return $false
    }
}

# Install Ruby
function Install-Ruby {
    if ($SkipRuby) {
        Write-Warning "Skipping Ruby installation"
        return $true
    }
    
    Write-Info "Checking Ruby installation..."
    
    if (Test-Command "ruby") {
        $rubyVersion = ruby --version
        Write-Success "Ruby already installed: $rubyVersion"
        return $true
    }
    
    Write-Info "Installing Ruby via Chocolatey..."
    try {
        choco install ruby -y
        Write-Success "Ruby installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Ruby: $_"
        return $false
    }
}

# Install Bundler
function Install-Bundler {
    Write-Info "Installing Bundler..."
    try {
        gem install bundler
        Write-Success "Bundler installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Bundler: $_"
        return $false
    }
}

# Install dependencies
function Install-Dependencies {
    Write-Info "Installing Ruby dependencies..."
    try {
        bundle install
        Write-Success "Dependencies installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install dependencies: $_"
        return $false
    }
}

# Setup database
function Setup-Database {
    Write-Info "Setting up database..."
    try {
        ruby lib/migrations.rb
        Write-Success "Database setup completed"
        return $true
    } catch {
        Write-Error "Failed to setup database: $_"
        return $false
    }
}

# Install Nginx
function Install-Nginx {
    if ($SkipNginx) {
        Write-Warning "Skipping Nginx installation"
        return $true
    }
    
    Write-Info "Installing Nginx..."
    
    if (Test-Command "nginx") {
        Write-Success "Nginx already installed"
        return $true
    }
    
    try {
        choco install nginx -y
        Write-Success "Nginx installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Nginx: $_"
        return $false
    }
}

# Create Nginx configuration
function Create-NginxConfig {
    if ($SkipNginx) {
        return $true
    }
    
    $nginxPath = "C:\nginx\conf"
    $nginxConfigPath = "$nginxPath\source-license.conf"
    
    # Ensure directory exists
    if (-not (Test-Path $nginxPath)) {
        New-Item -ItemType Directory -Path $nginxPath -Force
    }
    
    $nginxConfig = @"
upstream source_license {
    server 127.0.0.1:$Port fail_timeout=0;
}

server {
    listen 80;
    server_name $Domain;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files `$uri @source_license;
    }
    
    # Main application
    location / {
        proxy_pass http://source_license;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_redirect off;
        
        # Increase timeout for long-running requests
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://source_license;
    }
}
"@
    
    Write-Info "Creating Nginx configuration..."
    try {
        $nginxConfig | Out-File -FilePath $nginxConfigPath -Encoding UTF8
        
        # Update main nginx.conf to include our config
        $mainConfigPath = "$nginxPath\nginx.conf"
        if (Test-Path $mainConfigPath) {
            $mainConfig = Get-Content $mainConfigPath
            if (-not ($mainConfig | Select-String "include.*source-license.conf")) {
                $mainConfig = $mainConfig -replace "(http\s*{)", "`$1`n    include source-license.conf;"
                $mainConfig | Set-Content $mainConfigPath
                Write-Success "Updated main Nginx configuration"
            }
        }
        
        Write-Success "Nginx configuration created at $nginxConfigPath"
        return $true
    } catch {
        Write-Error "Failed to create Nginx configuration: $_"
        return $false
    }
}

# Create Windows service
function Create-WindowsService {
    if ($Environment -ne "production") {
        return $true
    }
    
    Write-Info "Creating Windows service..."
    try {
        # Install NSSM (Non-Sucking Service Manager) if not present
        if (-not (Test-Command "nssm")) {
            choco install nssm -y
        }
        
        $currentDir = Get-Location
        $rubyPath = (Get-Command ruby).Source
        
        # Remove existing service if it exists
        $existingService = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
        if ($existingService) {
            Write-Info "Removing existing service..."
            nssm remove SourceLicense confirm
        }
        
        # Create the service
        nssm install SourceLicense $rubyPath "$currentDir\launch.rb"
        nssm set SourceLicense AppDirectory $currentDir
        nssm set SourceLicense AppEnvironmentExtra "RACK_ENV=$Environment" "APP_ENV=$Environment" "PORT=$Port"
        nssm set SourceLicense DisplayName "Source License Management System"
        nssm set SourceLicense Description "Professional Software License Management System"
        nssm set SourceLicense Start SERVICE_AUTO_START
        
        # Set up logging
        $logsDir = "$currentDir\logs"
        if (-not (Test-Path $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force
        }
        nssm set SourceLicense AppStdout "$logsDir\app.log"
        nssm set SourceLicense AppStderr "$logsDir\error.log"
        
        Write-Success "Windows service created successfully"
        return $true
    } catch {
        Write-Error "Failed to create Windows service: $_"
        return $false
    }
}

# Create environment file
function Create-EnvironmentFile {
    Write-Info "Creating environment configuration..."
    
    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
        Write-Success "Created .env file from template"
    } else {
        Write-Info ".env file already exists"
    }
    
    # Update domain in .env if not localhost
    if ($Domain -ne "localhost") {
        $envContent = Get-Content ".env"
        $envContent = $envContent -replace "^APP_HOST=.*", "APP_HOST=$Domain"
        $envContent | Set-Content ".env"
        Write-Success "Updated APP_HOST in .env file"
    }
}

# Start services
function Start-Services {
    if ($Environment -ne "production") {
        return
    }
    
    Write-Info "Starting services..."
    
    # Start Nginx
    if (-not $SkipNginx) {
        try {
            Start-Service nginx -ErrorAction SilentlyContinue
            Write-Success "Nginx started successfully"
        } catch {
            Write-Warning "Failed to start Nginx: $_"
        }
    }
    
    # Start application service
    try {
        Start-Service SourceLicense
        Write-Success "Source License service started"
    } catch {
        Write-Warning "Failed to start Source License service: $_"
    }
}

# Run tests
function Run-Tests {
    Write-Info "Running tests to verify installation..."
    try {
        & ruby run_tests.rb
        return $?
    } catch {
        Write-Error "Tests failed: $_"
        return $false
    }
}

# Configure Windows Firewall
function Configure-Firewall {
    Write-Info "Configuring Windows Firewall..."
    try {
        # Allow Ruby through firewall
        New-NetFirewallRule -DisplayName "Source License - Ruby" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction SilentlyContinue
        
        # Allow Nginx through firewall if installed
        if (-not $SkipNginx) {
            New-NetFirewallRule -DisplayName "Source License - Nginx" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName "Source License - Nginx HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue
        }
        
        Write-Success "Firewall rules configured"
        return $true
    } catch {
        Write-Warning "Failed to configure firewall: $_"
        return $false
    }
}

# Main installation function
function Main {
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source License Management System                          ║
║                         Windows Installation Script                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Info "Detected OS: Windows"
    
    # Check admin rights for production installation
    if ($Environment -eq "production" -and -not (Test-AdminRights)) {
        Write-Error "Administrator privileges required for production installation"
        Write-Info "Please run PowerShell as Administrator and try again"
        exit 1
    }
    
    $success = $true
    
    # Install Chocolatey
    $success = $success -and (Install-Chocolatey)
    
    # Install Ruby
    if (-not $SkipRuby) {
        $success = $success -and (Install-Ruby)
        $success = $success -and (Install-Bundler)
    }
    
    # Install dependencies
    $success = $success -and (Install-Dependencies)
    
    # Setup database
    $success = $success -and (Setup-Database)
    
    # Install and configure Nginx
    if (-not $SkipNginx) {
        $success = $success -and (Install-Nginx)
        $success = $success -and (Create-NginxConfig)
    }
    
    # Create environment file
    Create-EnvironmentFile
    
    # Configure firewall
    if ($Environment -eq "production") {
        Configure-Firewall
    }
    
    # Create services for production
    if ($Environment -eq "production") {
        $success = $success -and (Create-WindowsService)
        
        # Start services
        Start-Services
    }
    
    # Run tests
    Write-Info "Running verification tests..."
    $testsSuccess = Run-Tests
    
    # Final status
    Write-Host "`n" + "="*80 -ForegroundColor Cyan
    if ($success -and $testsSuccess) {
        Write-Success "Installation completed successfully!"
        Write-Host @"

🎉 Source License Management System is now installed and running on Windows!

Access your application:
  URL: http://$Domain$(if ($Port -ne "80") { ":$Port" })
  Admin: http://$Domain$(if ($Port -ne "80") { ":$Port" })/admin

Next steps:
  1. Edit .env file with your configuration
  2. Setup payment gateways (Stripe/PayPal)
  3. Configure SMTP for email delivery
  4. Add your products via the admin interface
  5. Setup SSL certificate for production use

Windows Service management:
  Start:   Start-Service SourceLicense
  Stop:    Stop-Service SourceLicense
  Status:  Get-Service SourceLicense

Service Manager:
  ./service_manager.ps1 status    - Check service status
  ./service_manager.ps1 monitor   - Monitor continuously
  ./service_manager.ps1 logs      - View logs
  ./service_manager.ps1 restart   - Restart service

Logs are located in: .\logs\
"@
    } else {
        Write-Error "Installation failed! Please check the error messages above."
        exit 1
    }
}

# Run main function
Main

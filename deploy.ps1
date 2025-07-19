#!/usr/bin/env pwsh
# PowerShell Deployment Script for Source License Management System
# Handles updates and configuration changes without overwriting customizations

param(
    [string]$Action = "update",
    [string]$Domain = "",
    [string]$Port = "",
    [string]$Environment = "",
    [switch]$Force,
    [switch]$BackupFirst,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Source License Management System - Windows Deployment Script

USAGE:
    ./deploy.ps1 [ACTION] [OPTIONS]

ACTIONS:
    update                    Update application code and dependencies
    config                    Update configuration only
    restart                   Restart services
    backup                    Create backup of current installation
    restore                   Restore from backup
    migrate                   Run database migrations only
    status                    Show deployment status

OPTIONS:
    -Domain <domain>          Update domain configuration
    -Port <port>              Update port configuration  
    -Environment <env>        Update environment (development/production)
    -Force                    Force update even if changes detected
    -BackupFirst              Create backup before deployment
    -Help                     Show this help message

EXAMPLES:
    ./deploy.ps1 update -BackupFirst
    ./deploy.ps1 config -Domain "new-domain.com"
    ./deploy.ps1 restart
    ./deploy.ps1 backup
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

# Backup current installation
function New-Backup {
    param($BackupPath = "backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')")
    
    Write-Info "Creating backup at $BackupPath..."
    
    try {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        
        # Backup configuration files
        $configFiles = @(".env", "config\customizations.yml", "Gemfile.lock")
        foreach ($file in $configFiles) {
            if (Test-Path $file) {
                $destPath = Join-Path $BackupPath (Split-Path $file -Leaf)
                Copy-Item $file $destPath -Force
                Write-Info "Backed up $file"
            }
        }
        
        # Backup database if SQLite
        if (Test-Path "database.db") {
            Copy-Item "database.db" "$BackupPath\database.db" -Force
            Write-Info "Backed up database"
        }
        
        # Backup logs
        if (Test-Path "logs") {
            Copy-Item "logs" "$BackupPath\logs" -Recurse -Force
            Write-Info "Backed up logs"
        }
        
        # Create manifest
        $manifest = @{
            Timestamp = Get-Date
            Version = (git describe --tags --always 2>$null)
            Environment = $env:RACK_ENV
            Files = $configFiles
        }
        $manifest | ConvertTo-Json | Out-File "$BackupPath\manifest.json" -Encoding UTF8
        
        Write-Success "Backup created successfully at $BackupPath"
        return $BackupPath
    } catch {
        Write-Error "Failed to create backup: $_"
        return $null
    }
}

# Restore from backup
function Restore-Backup {
    param($BackupPath)
    
    if (-not (Test-Path $BackupPath)) {
        Write-Error "Backup path not found: $BackupPath"
        return $false
    }
    
    Write-Info "Restoring from backup: $BackupPath..."
    
    try {
        # Check manifest
        $manifestPath = Join-Path $BackupPath "manifest.json"
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            Write-Info "Backup created: $($manifest.Timestamp)"
            Write-Info "Backup version: $($manifest.Version)"
        }
        
        # Stop services before restore
        & .\service_manager.ps1 stop
        
        # Restore files
        $filesToRestore = Get-ChildItem $BackupPath -File | Where-Object { $_.Name -ne "manifest.json" }
        foreach ($file in $filesToRestore) {
            $destPath = ".\$($file.Name)"
            Copy-Item $file.FullName $destPath -Force
            Write-Info "Restored $($file.Name)"
        }
        
        # Restore directories
        $dirsToRestore = Get-ChildItem $BackupPath -Directory
        foreach ($dir in $dirsToRestore) {
            $destPath = ".\$($dir.Name)"
            if (Test-Path $destPath) {
                Remove-Item $destPath -Recurse -Force
            }
            Copy-Item $dir.FullName $destPath -Recurse -Force
            Write-Info "Restored $($dir.Name)\"
        }
        
        Write-Success "Backup restored successfully"
        return $true
    } catch {
        Write-Error "Failed to restore backup: $_"
        return $false
    }
}

# Check for uncommitted changes
function Test-LocalChanges {
    try {
        $status = git status --porcelain 2>$null
        return $status.Length -gt 0
    } catch {
        return $false
    }
}

# Update application code
function Update-Application {
    Write-Info "Updating application code..."
    
    # Check for local changes
    if ((Test-LocalChanges) -and -not $Force) {
        Write-Warning "Local changes detected. Use -Force to override or commit changes first."
        git status --short
        return $false
    }
    
    try {
        # Create backup if requested
        if ($BackupFirst) {
            $backupPath = New-Backup
            if (-not $backupPath) {
                Write-Error "Backup failed, aborting update"
                return $false
            }
        }
        
        # Stop services
        Write-Info "Stopping services..."
        & .\service_manager.ps1 stop
        
        # Pull latest changes
        Write-Info "Pulling latest changes..."
        git pull origin main
        
        # Update dependencies
        Write-Info "Updating dependencies..."
        bundle install
        
        # Run migrations
        Write-Info "Running database migrations..."
        ruby lib\migrations.rb
        
        # Restart services
        Write-Info "Starting services..."
        & .\service_manager.ps1 start
        
        Write-Success "Application updated successfully"
        return $true
    } catch {
        Write-Error "Update failed: $_"
        
        # Attempt to restore backup if available
        if ($BackupFirst -and $backupPath) {
            Write-Warning "Attempting to restore backup..."
            Restore-Backup $backupPath
        }
        
        return $false
    }
}

# Update configuration
function Update-Configuration {
    Write-Info "Updating configuration..."
    
    try {
        # Backup configuration
        if (Test-Path ".env") {
            Copy-Item ".env" ".env.backup" -Force
            Write-Info "Backed up current .env file"
        }
        
        # Update domain if provided
        if ($Domain) {
            if (Test-Path ".env") {
                $envContent = Get-Content ".env"
                $envContent = $envContent -replace "^APP_HOST=.*", "APP_HOST=$Domain"
                $envContent | Set-Content ".env"
                Write-Success "Updated APP_HOST to $Domain"
            }
            
            # Update Nginx config if exists
            $nginxConfig = "C:\nginx\conf\source-license.conf"
            if (Test-Path $nginxConfig) {
                $configContent = Get-Content $nginxConfig
                $configContent = $configContent -replace "server_name .*;", "server_name $Domain;"
                $configContent | Set-Content $nginxConfig
                Write-Success "Updated Nginx server_name to $Domain"
                
                # Restart Nginx
                Restart-Service nginx -ErrorAction SilentlyContinue
            }
        }
        
        # Update port if provided
        if ($Port) {
            if (Test-Path ".env") {
                $envContent = Get-Content ".env"
                $envContent = $envContent -replace "^PORT=.*", "PORT=$Port"
                $envContent | Set-Content ".env"
                Write-Success "Updated PORT to $Port"
            }
        }
        
        # Update environment if provided
        if ($Environment) {
            if (Test-Path ".env") {
                $envContent = Get-Content ".env"
                $envContent = $envContent -replace "^RACK_ENV=.*", "RACK_ENV=$Environment"
                $envContent = $envContent -replace "^APP_ENV=.*", "APP_ENV=$Environment"
                $envContent | Set-Content ".env"
                Write-Success "Updated environment to $Environment"
            }
        }
        
        Write-Success "Configuration updated successfully"
        return $true
    } catch {
        Write-Error "Configuration update failed: $_"
        
        # Restore backup
        if (Test-Path ".env.backup") {
            Copy-Item ".env.backup" ".env" -Force
            Write-Info "Restored previous configuration"
        }
        
        return $false
    }
}

# Restart services
function Restart-Services {
    Write-Info "Restarting services..."
    
    try {
        # Restart application
        & .\service_manager.ps1 restart
        
        # Restart Nginx if running
        $nginxService = Get-Service nginx -ErrorAction SilentlyContinue
        if ($nginxService -and $nginxService.Status -eq "Running") {
            Restart-Service nginx
            Write-Success "Nginx restarted"
        }
        
        Write-Success "Services restarted successfully"
        return $true
    } catch {
        Write-Error "Failed to restart services: $_"
        return $false
    }
}

# Run database migrations only
function Invoke-Migration {
    Write-Info "Running database migrations..."
    
    try {
        ruby lib\migrations.rb
        Write-Success "Database migrations completed"
        return $true
    } catch {
        Write-Error "Database migration failed: $_"
        return $false
    }
}

# Show deployment status
function Show-DeploymentStatus {
    Write-Host "Source License Management System - Deployment Status" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    # Git status
    try {
        $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $gitCommit = git rev-parse --short HEAD 2>$null
        $gitStatus = git status --porcelain 2>$null
        
        Write-Info "Git Branch: $gitBranch"
        Write-Info "Git Commit: $gitCommit"
        
        if ($gitStatus) {
            Write-Warning "Uncommitted changes present:"
            $gitStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        } else {
            Write-Success "Working directory clean"
        }
    } catch {
        Write-Warning "Not a git repository"
    }
    
    # Environment info
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $domain = ($envContent | Where-Object { $_ -match "^APP_HOST=" }) -replace "APP_HOST=", ""
        $port = ($envContent | Where-Object { $_ -match "^PORT=" }) -replace "PORT=", ""
        $env = ($envContent | Where-Object { $_ -match "^RACK_ENV=" }) -replace "RACK_ENV=", ""
        
        Write-Info "Domain: $domain"
        Write-Info "Port: $port"
        Write-Info "Environment: $env"
    }
    
    # Service status
    & .\service_manager.ps1 status
    
    # Recent backups
    if (Test-Path "backups") {
        $recentBackups = Get-ChildItem "backups" -Directory | Sort-Object Name -Descending | Select-Object -First 5
        if ($recentBackups) {
            Write-Info "Recent backups:"
            $recentBackups | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Gray }
        }
    }
    
    # Customizations status
    if (Test-Path "config\customizations.yml") {
        $customizationSize = (Get-Item "config\customizations.yml").Length
        Write-Info "Customizations file: $customizationSize bytes"
    } else {
        Write-Info "No customizations file found"
    }
}

# List available backups
function Get-AvailableBackups {
    if (-not (Test-Path "backups")) {
        Write-Warning "No backups directory found"
        return
    }
    
    $backups = Get-ChildItem "backups" -Directory | Sort-Object Name -Descending
    
    if ($backups.Count -eq 0) {
        Write-Warning "No backups found"
        return
    }
    
    Write-Info "Available backups:"
    $backups | ForEach-Object {
        $manifestPath = Join-Path $_.FullName "manifest.json"
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            Write-Host "  $($_.Name) - $($manifest.Timestamp) ($($manifest.Version))" -ForegroundColor Gray
        } else {
            Write-Host "  $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Main deployment function
function Main {
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source License Management System                          ║
║                         Deployment Script                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Check if we're in the right directory
    if (-not (Test-Path "app.rb") -or -not (Test-Path "Gemfile")) {
        Write-Error "Please run this script from the project root directory"
        exit 1
    }
    
    switch ($Action.ToLower()) {
        "update" {
            Update-Application
        }
        "config" {
            Update-Configuration
        }
        "restart" {
            Restart-Services
        }
        "backup" {
            New-Backup | Out-Null
        }
        "restore" {
            Get-AvailableBackups
            $backupName = Read-Host "Enter backup name to restore"
            if ($backupName) {
                $backupPath = "backups\$backupName"
                Restore-Backup $backupPath
            }
        }
        "migrate" {
            Invoke-Migration
        }
        "status" {
            Show-DeploymentStatus
        }
        default {
            Write-Error "Unknown action: $Action"
            Write-Info "Use -Help to see available actions"
            exit 1
        }
    }
}

# Run main function
Main

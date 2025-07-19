#!/usr/bin/env pwsh
# Source-License Unified Deploy Script
# Simplified deployment script for Windows systems

param(
    [string]$Action = "help",
    [string]$Environment = "production",
    [string]$Port = "4567",
    [switch]$Backup,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Source-License Deploy Script for Windows

USAGE:
    ./deploy.ps1 [ACTION] [OPTIONS]

ACTIONS:
    run                      Start the application
    stop                     Stop the application
    restart                  Restart the application
    status                   Show application status
    update                   Update code and restart
    migrate                  Run database migrations only

OPTIONS:
    -Environment <env>       Environment (development/production, default: production)
    -Port <port>             Port for the application (default: 4567)
    -Backup                  Create backup before update
    -Help                    Show this help message

EXAMPLES:
    ./deploy.ps1 run
    ./deploy.ps1 stop
    ./deploy.ps1 update -Backup
    ./deploy.ps1 run -Environment development -Port 3000
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

# Check if port is in use
function Test-Port {
    param($Port)
    try {
        $connection = New-Object System.Net.Sockets.TcpClient
        $connection.Connect("localhost", $Port)
        $connection.Close()
        return $true
    } catch {
        return $false
    }
}

# Get application process
function Get-AppProcess {
    try {
        return Get-Process | Where-Object { 
            $_.ProcessName -eq "ruby" -and 
            $_.CommandLine -like "*launch.rb*" 
        } | Select-Object -First 1
    } catch {
        return Get-Process -Name "ruby" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
}

# Health check
function Test-Health {
    param($Port)
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 5 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    } catch {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port/" -TimeoutSec 5 -ErrorAction SilentlyContinue
            return $response.StatusCode -eq 200
        } catch {
            return $false
        }
    }
}

# Start application
function Start-Application {
    Write-Info "Starting Source-License application..."
    
    if (Test-Port $Port) {
        Write-Warning "Port $Port is already in use"
        if (Test-Health $Port) {
            Write-Success "Application appears to be already running"
            return $true
        } else {
            Write-Warning "Port is in use but health check failed"
        }
    }
    
    # Set environment variables
    $env:RACK_ENV = $Environment
    $env:APP_ENV = $Environment
    $env:PORT = $Port
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Write-Info "Environment: $Environment"
    Write-Info "Port: $Port"
    
    try {
        if ($Environment -eq "development") {
            Write-Info "Starting in development mode (foreground)..."
            & ruby launch.rb
        } else {
            Write-Info "Starting in production mode (background)..."
            $job = Start-Job -ScriptBlock {
                param($WorkingDir, $Env, $Port)
                Set-Location $WorkingDir
                $env:RACK_ENV = $Env
                $env:APP_ENV = $Env
                $env:PORT = $Port
                & ruby launch.rb
            } -ArgumentList (Get-Location), $Environment, $Port
            
            # Give it a moment to start
            Start-Sleep 3
            
            if (Test-Health $Port) {
                Write-Success "Application started successfully"
                $process = Get-AppProcess
                if ($process) {
                    Write-Info "PID: $($process.Id)"
                }
                Write-Info "Job ID: $($job.Id)"
                Write-Info "Access: http://localhost:$Port"
                Write-Info "Admin: http://localhost:$Port/admin"
                Write-Info "Logs: Get-Content logs\app.log -Tail 20 -Wait"
                return $true
            } else {
                Write-Error "Application failed to start"
                Write-Info "Check logs: Get-Content logs\app.log"
                $job | Stop-Job -PassThru | Remove-Job
                return $false
            }
        }
    } catch {
        Write-Error "Failed to start application: $_"
        return $false
    }
}

# Stop application
function Stop-Application {
    Write-Info "Stopping Source-License application..."
    
    try {
        # Stop Ruby processes
        $processes = Get-AppProcess
        if ($processes) {
            $processes | Stop-Process -Force
            Write-Success "Ruby processes stopped"
            return $true
        }
        
        # Stop background jobs
        $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
        if ($jobs) {
            $jobs | Stop-Job -PassThru | Remove-Job
            Write-Success "Background jobs stopped"
            return $true
        }
        
        Write-Warning "No running application found"
        return $false
    } catch {
        Write-Error "Error stopping application: $_"
        return $false
    }
}

# Restart application
function Restart-Application {
    Write-Info "Restarting Source-License application..."
    
    Stop-Application | Out-Null
    Start-Sleep 2
    Start-Application
}

# Show status
function Show-Status {
    Write-Info "Source-License Application Status"
    Write-Host "=================================="
    
    $process = Get-AppProcess
    if ($process) {
        Write-Success "Application is running (PID: $($process.Id))"
        
        if (Test-Health $Port) {
            Write-Success "Health check passed"
        } else {
            Write-Warning "Health check failed"
        }
        
        Write-Info "Port: $Port"
        Write-Info "URLs:"
        Write-Info "  Main: http://localhost:$Port"
        Write-Info "  Admin: http://localhost:$Port/admin"
        
        # Show memory usage
        $memoryMB = [math]::Round($process.WorkingSet / 1MB, 2)
        Write-Info "Memory: $memoryMB MB"
        
        # Show start time
        Write-Info "Started: $($process.StartTime)"
    } else {
        Write-Error "Application is not running"
    }
    
    # Show background jobs
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    if ($jobs) {
        Write-Info "Background Jobs: $($jobs.Count) (IDs: $(($jobs.Id) -join ', '))"
    }
    
    # Show recent logs
    if (Test-Path "logs\app.log") {
        Write-Host ""
        Write-Info "Recent log entries:"
        try {
            Get-Content "logs\app.log" -Tail 5 -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not read log file"
        }
    }
}

# Update application
function Update-Application {
    Write-Info "Updating Source-License application..."
    
    try {
        # Create backup if requested
        if ($Backup) {
            $backupDir = "backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Info "Creating backup at $backupDir..."
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            
            # Backup important files
            $files = @(".env", "Gemfile.lock")
            foreach ($file in $files) {
                if (Test-Path $file) {
                    Copy-Item $file "$backupDir\" -Force
                }
            }
            
            # Backup database if SQLite
            if (Test-Path "database.db") {
                Copy-Item "database.db" "$backupDir\" -Force
            }
            
            Write-Success "Backup created"
        }
        
        # Stop application
        Stop-Application | Out-Null
        
        # Pull latest changes
        if (Test-Command "git" -and (Test-Path ".git")) {
            Write-Info "Pulling latest changes..."
            try {
                git pull origin main
            } catch {
                Write-Warning "Git pull failed, continuing anyway"
            }
        }
        
        # Update dependencies
        Write-Info "Updating dependencies..."
        bundle install
        
        # Run migrations
        Write-Info "Running database migrations..."
        try {
            ruby lib\migrations.rb
        } catch {
            Write-Warning "Database migration failed, continuing anyway"
        }
        
        # Start application
        Start-Application | Out-Null
        
        Write-Success "Update completed"
        return $true
    } catch {
        Write-Error "Update failed: $_"
        return $false
    }
}

# Run database migrations
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

# Preflight checks
function Test-Prerequisites {
    # Check if we're in the right directory
    if (-not (Test-Path "app.rb") -or -not (Test-Path "Gemfile") -or -not (Test-Path "launch.rb")) {
        Write-Error "Please run this script from the Source-License project root directory"
        exit 1
    }
    
    # Check Ruby
    if (-not (Test-Command "ruby")) {
        Write-Error "Ruby is not installed. Run .\install.ps1 first"
        exit 1
    }
    
    # Check Bundler
    if (-not (Test-Command "bundle")) {
        Write-Error "Bundler is not installed. Run .\install.ps1 first"
        exit 1
    }
    
    # Check if gems are installed
    try {
        $null = bundle check 2>$null
    } catch {
        Write-Warning "Dependencies not installed. Running bundle install..."
        bundle install
    }
}

# Main function
function Main {
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Deploy Script                              ║
║                         Windows Systems                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Run preflight checks
    Test-Prerequisites
    
    # Execute action
    switch ($Action.ToLower()) {
        { $_ -in @("run", "start") } {
            Start-Application | Out-Null
        }
        "stop" {
            Stop-Application | Out-Null
        }
        "restart" {
            Restart-Application | Out-Null
        }
        "status" {
            Show-Status
        }
        "update" {
            Update-Application | Out-Null
        }
        "migrate" {
            Invoke-Migration | Out-Null
        }
        "help" {
            Write-Host @"
Source-License Deploy Script for Windows

USAGE:
    ./deploy.ps1 [ACTION] [OPTIONS]

ACTIONS:
    run                      Start the application
    stop                     Stop the application
    restart                  Restart the application
    status                   Show application status
    update                   Update code and restart
    migrate                  Run database migrations only

OPTIONS:
    -Environment <env>       Environment (development/production, default: production)
    -Port <port>             Port for the application (default: 4567)
    -Backup                  Create backup before update
    -Help                    Show this help message

EXAMPLES:
    ./deploy.ps1 run
    ./deploy.ps1 stop
    ./deploy.ps1 update -Backup
    ./deploy.ps1 run -Environment development -Port 3000
"@
            exit 0
        }
        default {
            Write-Error "Unknown action: $Action"
            Write-Info "Use -Help to see available actions"
            exit 1
        }
    }
}

# Handle Ctrl+C gracefully
$null = Register-EngineEvent PowerShell.Exiting -Action {
    Write-Host "`nShutting down gracefully..." -ForegroundColor Yellow
    Stop-Application | Out-Null
}

# Run main function
Main

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

# Logging setup
$DEPLOYMENT_LOG_DIR = "./deployment-logs"
$DEPLOYMENT_LOG_FILE = "$DEPLOYMENT_LOG_DIR/deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Ensure log directory exists
if (-not (Test-Path $DEPLOYMENT_LOG_DIR)) {
    New-Item -ItemType Directory -Path $DEPLOYMENT_LOG_DIR -Force | Out-Null
}

# Initialize log file with session header
@"
Source-License Deployment Script Log
Started: $(Get-Date)
Action: $Action
Environment: $Environment
Port: $Port
User: $env:USERNAME
Working Directory: $(Get-Location)
System: $($PSVersionTable.PSVersion) on $($PSVersionTable.OS)

"@ | Out-File -FilePath $DEPLOYMENT_LOG_FILE -Encoding UTF8

# Enhanced logging function
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $DEPLOYMENT_LOG_FILE -Append -Encoding UTF8
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
    Write-FunctionCall "Start-Application" "START"
    Write-Log "INFO" "Starting Source-License application with environment=$Environment, port=$Port"
    
    Write-Info "Starting Source-License application..."
    
    if (Test-Port $Port) {
        Write-Log "WARNING" "Port $Port is already in use"
        Write-Warning "Port $Port is already in use"
        if (Test-Health $Port) {
            Write-Log "INFO" "Health check passed - application appears to be already running"
            Write-Success "Application appears to be already running"
            Write-FunctionCall "Start-Application" "COMPLETE - ALREADY_RUNNING"
            return $true
        } else {
            Write-Log "WARNING" "Port is in use but health check failed"
            Write-Warning "Port is in use but health check failed"
        }
    }
    
    # Set environment variables
    $env:RACK_ENV = $Environment
    $env:APP_ENV = $Environment
    $env:PORT = $Port
    Write-Log "INFO" "Environment variables set: RACK_ENV=$Environment, APP_ENV=$Environment, PORT=$Port"
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        Write-CommandLog "New-Item -ItemType Directory -Path logs"
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Write-Info "Environment: $Environment"
    Write-Info "Port: $Port"
    
    try {
        if ($Environment -eq "development") {
            Write-Log "INFO" "Development mode - starting in foreground"
            Write-Info "Starting in development mode (foreground)..."
            Write-CommandLog "ruby launch.rb"
            & ruby launch.rb
        } else {
            Write-Log "INFO" "Production mode - starting in background"
            Write-Info "Starting in production mode (background)..."
            
            Write-CommandLog "Start-Job with ruby launch.rb"
            $job = Start-Job -ScriptBlock {
                param($WorkingDir, $Env, $Port)
                Set-Location $WorkingDir
                $env:RACK_ENV = $Env
                $env:APP_ENV = $Env
                $env:PORT = $Port
                & ruby launch.rb
            } -ArgumentList (Get-Location), $Environment, $Port
            
            # Give it a moment to start
            Write-Log "INFO" "Waiting 3 seconds for application startup"
            Start-Sleep 3
            
            if (Test-Health $Port) {
                $process = Get-AppProcess
                $processId = if ($process) { $process.Id } else { "unknown" }
                Write-Log "SUCCESS" "Application started successfully with PID: $processId, Job ID: $($job.Id)"
                Write-Success "Application started successfully"
                if ($process) {
                    Write-Info "PID: $($process.Id)"
                }
                Write-Info "Job ID: $($job.Id)"
                Write-Info "Access: http://localhost:$Port"
                Write-Info "Admin: http://localhost:$Port/admin"
                Write-Info "Logs: Get-Content logs\app.log -Tail 20 -Wait"
                Write-FunctionCall "Start-Application" "COMPLETE - BACKGROUND"
                return $true
            } else {
                Write-ErrorLog "Application failed to start - health check failed"
                Write-Error "Application failed to start"
                Write-Info "Check logs: Get-Content logs\app.log"
                $job | Stop-Job -PassThru | Remove-Job
                Write-FunctionCall "Start-Application" "FAILED"
                return $false
            }
        }
    } catch {
        Write-ErrorLog "Failed to start application: $_"
        Write-Error "Failed to start application: $_"
        Write-FunctionCall "Start-Application" "FAILED - EXCEPTION"
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
    Write-FunctionCall "Main" "START"
    Write-Log "INFO" "Starting deployment script execution"
    
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Deploy Script                              ║
║                         Windows Systems                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Run preflight checks
    Write-Log "INFO" "Running preflight checks"
    Test-Prerequisites
    
    # Execute action
    Write-Log "INFO" "Executing action: $Action"
    switch ($Action.ToLower()) {
        { $_ -in @("run", "start") } {
            Start-Application | Out-Null
        }
        "stop" {
            Write-FunctionCall "Stop-Application" "START"
            Stop-Application | Out-Null
            Write-FunctionCall "Stop-Application" "COMPLETE"
        }
        "restart" {
            Write-FunctionCall "Restart-Application" "START"
            Restart-Application | Out-Null
            Write-FunctionCall "Restart-Application" "COMPLETE"
        }
        "status" {
            Write-FunctionCall "Show-Status" "START"
            Show-Status
            Write-FunctionCall "Show-Status" "COMPLETE"
        }
        "update" {
            Update-Application | Out-Null
        }
        "migrate" {
            Write-FunctionCall "Invoke-Migration" "START"
            Invoke-Migration | Out-Null
            Write-FunctionCall "Invoke-Migration" "COMPLETE"
        }
        "help" {
            Write-Log "INFO" "Showing help and exiting"
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
            Write-ErrorLog "Unknown action: $Action"
            Write-Error "Unknown action: $Action"
            Write-Info "Use -Help to see available actions"
            exit 1
        }
    }
    
    Write-Log "INFO" "Deployment script execution completed"
    Write-FunctionCall "Main" "COMPLETE"
    
    # Log session end
    @"

Session completed: $(Get-Date)
Final action: $Action
Exit status: $LASTEXITCODE
"@ | Out-File -FilePath $DEPLOYMENT_LOG_FILE -Append -Encoding UTF8
}

# Handle Ctrl+C gracefully
$null = Register-EngineEvent PowerShell.Exiting -Action {
    Write-Host "`nShutting down gracefully..." -ForegroundColor Yellow
    Stop-Application | Out-Null
}

# Additional signal handling for better shutdown behavior
try {
    # Register for console control events
    Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public static class ConsoleHelper {
            public delegate bool ConsoleCtrlDelegate(int dwCtrlType);
            [DllImport("kernel32.dll")]
            public static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate HandlerRoutine, bool Add);
        }
"@
    
    $shutdownHandler = {
        param($ctrlType)
        Write-Host "`nReceived shutdown signal. Shutting down gracefully..." -ForegroundColor Yellow
        Stop-Application | Out-Null
        return $false
    }
    
    [ConsoleHelper]::SetConsoleCtrlHandler($shutdownHandler, $true)
} catch {
    # Fallback if advanced signal handling fails
    Write-Warning "Advanced signal handling not available, using basic handler"
}

# Run main function
Main

#!/usr/bin/env pwsh
# PowerShell Service Manager for Source License Management System
# Windows-focused service management with cross-platform monitoring

param(
    [string]$Action = "status",
    [string]$Port = "4567",
    [string]$Environment = "production",
    [int]$RestartDelay = 5,
    [switch]$Verbose,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Source License Management System - Service Manager

USAGE:
    ./service_manager.ps1 [ACTION] [OPTIONS]

ACTIONS:
    start                     Start the application service
    stop                      Stop the application service
    restart                   Restart the application service
    status                    Show service status (default)
    monitor                   Continuously monitor and restart if needed
    logs                      Show application logs
    health                    Check application health
    install                   Install as Windows service
    uninstall                 Remove Windows service

OPTIONS:
    -Port <port>              Port for the application (default: 4567)
    -Environment <env>        Environment (development/production, default: production)
    -RestartDelay <seconds>   Delay between restart attempts (default: 5)
    -Verbose                  Show verbose output
    -Help                     Show this help message

EXAMPLES:
    ./service_manager.ps1 start
    ./service_manager.ps1 monitor -Verbose
    ./service_manager.ps1 status -Port "3000"
    ./service_manager.ps1 logs
"@
    exit 0
}

# Color functions
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Debug { param($Message) if ($Verbose) { Write-Host "🔍 $Message" -ForegroundColor Gray } }

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

# Get Ruby application process
function Get-AppProcess {
    try {
        # Look for ruby processes running launch.rb
        $processes = Get-Process | Where-Object { 
            $_.ProcessName -eq "ruby" -and 
            $_.CommandLine -like "*launch.rb*" 
        }
        return $processes
    } catch {
        # Fallback - just get ruby processes
        return Get-Process -Name "ruby" -ErrorAction SilentlyContinue
    }
}

# Start the application
function Start-Application {
    Write-Info "Starting Source License application..."
    
    # Check if already running
    if (Test-Port $Port) {
        Write-Warning "Application appears to be already running on port $Port"
        return $false
    }
    
    # Set environment variables
    $env:RACK_ENV = $Environment
    $env:APP_ENV = $Environment
    $env:PORT = $Port
    
    try {
        # Try Windows service first
        $service = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
        if ($service) {
            Start-Service "SourceLicense"
            Write-Success "Windows service started"
            return $true
        }
        
        # Fallback to background job
        $job = Start-Job -ScriptBlock {
            param($WorkingDir, $Environment, $Port)
            Set-Location $WorkingDir
            $env:RACK_ENV = $Environment
            $env:APP_ENV = $Environment
            $env:PORT = $Port
            & ruby launch.rb
        } -ArgumentList (Get-Location), $Environment, $Port
        
        # Give it a moment to start
        Start-Sleep 3
        
        if (Test-Port $Port) {
            Write-Success "Application started successfully on port $Port"
            Write-Info "Job ID: $($job.Id)"
            return $true
        } else {
            Write-Error "Failed to start application"
            $job | Stop-Job -PassThru | Remove-Job
            return $false
        }
    } catch {
        Write-Error "Error starting application: $_"
        return $false
    }
}

# Stop the application
function Stop-Application {
    Write-Info "Stopping Source License application..."
    
    try {
        # Stop Windows service if it exists
        $service = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Stop-Service "SourceLicense" -Force
            Write-Success "Windows service stopped"
            return $true
        }
        
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

# Restart the application
function Restart-Application {
    Write-Info "Restarting Source License application..."
    
    Stop-Application
    Start-Sleep $RestartDelay
    Start-Application
}

# Get application status
function Get-ApplicationStatus {
    $status = @{
        Running = $false
        Port = $Port
        ProcessInfo = $null
        HealthCheck = $false
        ServiceStatus = $null
        JobInfo = $null
    }
    
    # Check if port is in use
    $status.Running = Test-Port $Port
    
    # Get Windows service status
    $service = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
    if ($service) {
        $status.ServiceStatus = $service.Status
    }
    
    # Get process information
    $process = Get-AppProcess | Select-Object -First 1
    if ($process) {
        $status.ProcessInfo = @{
            Id = $process.Id
            Name = $process.ProcessName
            StartTime = $process.StartTime
            WorkingSet = [math]::Round($process.WorkingSet / 1MB, 2)
            CPU = $process.CPU
        }
    }
    
    # Get background job info
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    if ($jobs) {
        $status.JobInfo = @{
            Count = $jobs.Count
            Ids = $jobs.Id -join ", "
        }
    }
    
    # Health check
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 5 -ErrorAction SilentlyContinue
        $status.HealthCheck = $response.StatusCode -eq 200
    } catch {
        $status.HealthCheck = $false
    }
    
    return $status
}

# Show application status
function Show-Status {
    Write-Host "Source License Management System - Status" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    $status = Get-ApplicationStatus
    
    if ($status.Running) {
        Write-Success "Application is running on port $($status.Port)"
    } else {
        Write-Error "Application is not running"
    }
    
    if ($status.HealthCheck) {
        Write-Success "Health check passed"
    } else {
        Write-Warning "Health check failed"
    }
    
    if ($status.ServiceStatus) {
        Write-Info "Windows Service Status: $($status.ServiceStatus)"
    }
    
    if ($status.ProcessInfo) {
        Write-Info "Process ID: $($status.ProcessInfo.Id) ($($status.ProcessInfo.Name))"
        Write-Info "Start Time: $($status.ProcessInfo.StartTime)"
        Write-Info "Memory Usage: $($status.ProcessInfo.WorkingSet) MB"
        if ($status.ProcessInfo.CPU) {
            Write-Info "CPU Time: $($status.ProcessInfo.CPU) seconds"
        }
    }
    
    if ($status.JobInfo) {
        Write-Info "Background Jobs: $($status.JobInfo.Count) (IDs: $($status.JobInfo.Ids))"
    }
    
    Write-Host ""
    Write-Info "Application URL: http://localhost:$Port"
    Write-Info "Admin Panel: http://localhost:$Port/admin"
}

# Monitor application continuously
function Start-Monitor {
    Write-Info "Starting continuous monitoring of Source License application..."
    Write-Info "Press Ctrl+C to stop monitoring"
    
    $failureCount = 0
    $maxFailures = 3
    
    while ($true) {
        try {
            $status = Get-ApplicationStatus
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            if ($status.Running -and $status.HealthCheck) {
                if ($Verbose) {
                    Write-Success "[$timestamp] Application healthy on port $Port"
                }
                $failureCount = 0
            } elseif ($status.Running -and -not $status.HealthCheck) {
                Write-Warning "[$timestamp] Application running but health check failed"
                $failureCount++
            } else {
                Write-Error "[$timestamp] Application not running"
                $failureCount++
            }
            
            # Restart if we've had too many failures
            if ($failureCount -ge $maxFailures) {
                Write-Warning "[$timestamp] Too many failures, restarting application..."
                Restart-Application
                $failureCount = 0
                Start-Sleep 10  # Give it time to start
            }
            
            Start-Sleep 30  # Check every 30 seconds
        } catch {
            Write-Error "[$timestamp] Monitor error: $_"
            Start-Sleep 30
        }
    }
}

# Show application logs
function Show-Logs {
    Write-Info "Showing Source License application logs..."
    
    # Check Windows Event Log for service
    $service = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Info "Checking Windows Event Log..."
        try {
            Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='SourceLicense'} -MaxEvents 20 -ErrorAction SilentlyContinue | 
                Format-Table TimeCreated, LevelDisplayName, Message -Wrap
        } catch {
            Write-Warning "No Windows Event Log entries found"
        }
    }
    
    # Check for log files
    $logFiles = @("logs\app.log", "logs\error.log", "logs\access.log", "nohup.out")
    foreach ($logFile in $logFiles) {
        if (Test-Path $logFile) {
            Write-Info "Contents of $logFile (last 20 lines):"
            Get-Content $logFile -Tail 20
            Write-Host ""
        }
    }
    
    # Show recent PowerShell job output
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    if ($jobs) {
        Write-Info "Background job output:"
        foreach ($job in $jobs) {
            Write-Host "Job $($job.Id):" -ForegroundColor Yellow
            $output = Receive-Job $job -Keep | Select-Object -Last 10
            if ($output) {
                $output | ForEach-Object { Write-Host "  $_" }
            } else {
                Write-Host "  No recent output"
            }
            Write-Host ""
        }
    }
}

# Check application health
function Test-Health {
    Write-Info "Performing health check..."
    
    try {
        # Basic connectivity test
        if (-not (Test-Port $Port)) {
            Write-Error "Cannot connect to port $Port"
            return $false
        }
        
        # HTTP health check
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Success "HTTP health check passed"
        } else {
            Write-Warning "HTTP health check returned status $($response.StatusCode)"
        }
        
        # Test main page
        try {
            $mainResponse = Invoke-WebRequest -Uri "http://localhost:$Port/" -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($mainResponse.StatusCode -eq 200) {
                Write-Success "Main page accessible"
            }
        } catch {
            Write-Warning "Main page not accessible"
        }
        
        # Test admin page
        try {
            $adminResponse = Invoke-WebRequest -Uri "http://localhost:$Port/admin" -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($adminResponse.StatusCode -eq 200) {
                Write-Success "Admin page accessible"
            }
        } catch {
            Write-Warning "Admin page not accessible (may require authentication)"
        }
        
        return $true
    } catch {
        Write-Error "Health check failed: $_"
        return $false
    }
}

# Install Windows service
function Install-WindowsService {
    Write-Info "Installing Windows service..."
    
    try {
        # Check if NSSM is available
        if (-not (Test-Command "nssm")) {
            Write-Error "NSSM (Non-Sucking Service Manager) is required. Install with: choco install nssm"
            return $false
        }
        
        $currentDir = Get-Location
        $rubyPath = (Get-Command ruby).Source
        
        # Remove existing service if it exists
        $existingService = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
        if ($existingService) {
            Write-Info "Removing existing service..."
            if ($existingService.Status -eq "Running") {
                Stop-Service "SourceLicense" -Force
            }
            nssm remove SourceLicense confirm
        }
        
        # Install new service
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
        
        Write-Success "Windows service installed successfully"
        return $true
    } catch {
        Write-Error "Failed to install Windows service: $_"
        return $false
    }
}

# Uninstall Windows service
function Uninstall-WindowsService {
    Write-Info "Uninstalling Windows service..."
    
    try {
        $service = Get-Service "SourceLicense" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq "Running") {
                Stop-Service "SourceLicense" -Force
            }
            nssm remove SourceLicense confirm
            Write-Success "Windows service uninstalled successfully"
            return $true
        } else {
            Write-Warning "Windows service not found"
            return $false
        }
    } catch {
        Write-Error "Failed to uninstall Windows service: $_"
        return $false
    }
}

# Main function
function Main {
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source License Management System                          ║
║                         Service Manager                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Debug "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Debug "Platform: $($PSVersionTable.Platform)"
    
    # Check if we're in the right directory
    if (-not (Test-Path "app.rb") -or -not (Test-Path "launch.rb")) {
        Write-Error "Please run this script from the project root directory"
        exit 1
    }
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
        Write-Debug "Created logs directory"
    }
    
    switch ($Action.ToLower()) {
        "start" {
            Start-Application
        }
        "stop" {
            Stop-Application
        }
        "restart" {
            Restart-Application
        }
        "status" {
            Show-Status
        }
        "monitor" {
            Start-Monitor
        }
        "logs" {
            Show-Logs
        }
        "health" {
            Test-Health
        }
        "install" {
            Install-WindowsService
        }
        "uninstall" {
            Uninstall-WindowsService
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
}

# Run main function
Main

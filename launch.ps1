# Source-License PowerShell Launcher

Write-Host "Starting Source-License Application..." -ForegroundColor Green
Write-Host "Application will be available at: http://localhost:4567" -ForegroundColor Cyan
Write-Host "Admin panel will be available at: http://localhost:4567/admin" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

Set-Location "C:/Users/conno/Documents/Source-License"

try {
    bundle exec rackup config.ru -o 0.0.0.0 -p 4567
}
catch {
    Write-Host "Error starting application: $_" -ForegroundColor Red
    Write-Host "Please check your configuration and try again." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

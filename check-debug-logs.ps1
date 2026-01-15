# Check Debugging Logs
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CHECKING DEBUGGING LOGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$reportFile = "debugging-report.txt"
$logFile = "debug-client.log"

if (Test-Path $reportFile) {
    Write-Host "✓ Found debugging report: $reportFile" -ForegroundColor Green
    Write-Host "`n=== DEBUGGING REPORT (Last 100 lines) ===" -ForegroundColor Yellow
    Get-Content $reportFile -Tail 100
} else {
    Write-Host "✗ Debugging report not found: $reportFile" -ForegroundColor Red
    Write-Host "  (This file is created when debugging operations occur)" -ForegroundColor Yellow
}

Write-Host "`n"

if (Test-Path $logFile) {
    Write-Host "✓ Found client log: $logFile" -ForegroundColor Green
    Write-Host "`n=== CLIENT LOG (Last 50 lines) ===" -ForegroundColor Yellow
    Get-Content $logFile -Tail 50
} else {
    Write-Host "✗ Client log not found: $logFile" -ForegroundColor Red
    Write-Host "  (This file is created when the client starts)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Log files location: $(Get-Location)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

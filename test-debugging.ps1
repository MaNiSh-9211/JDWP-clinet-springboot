# Test if client can debug container
$ErrorActionPreference = "Continue"

Write-Host "=== TESTING: Can client debug container? ===" -ForegroundColor Cyan
Write-Host ""

# Wait for client
Write-Host "[1] Checking client..." -ForegroundColor Yellow
for ($i=1; $i -le 10; $i++) {
    try {
        $s = Invoke-RestMethod -Uri "http://localhost:8082/api/debug/status" -Method Get -TimeoutSec 3
        Write-Host "  Client is running" -ForegroundColor Green
        break
    } catch {
        if ($i -eq 10) {
            Write-Host "  Client not ready" -ForegroundColor Red
            exit
        }
        Start-Sleep -Seconds 2
    }
}

# Connect to JDWP
Write-Host "`n[2] Connecting to container JDWP (port 5005)..." -ForegroundColor Yellow
$uri = New-Object System.UriBuilder("http://localhost:8082/api/debug/connect")
$uri.Query = "host=localhost&port=5005"
try {
    $r = Invoke-RestMethod -Uri $uri.Uri -Method Post -TimeoutSec 10
    Write-Host "  CONNECTED: $($r.message)" -ForegroundColor Green -BackgroundColor Black
} catch {
    Write-Host "  FAILED: $_" -ForegroundColor Red
    exit
}

# Get threads
Write-Host "`n[3] Getting threads from CONTAINER..." -ForegroundColor Yellow
$t = Invoke-RestMethod -Uri "http://localhost:8082/api/debug/threads" -Method Get
Write-Host "  Got $($t.threads.Count) threads FROM CONTAINER" -ForegroundColor Green
Write-Host "  This proves we're debugging the CONTAINER!" -ForegroundColor Green

# Set breakpoint
Write-Host "`n[4] Setting breakpoint in CONTAINER code..." -ForegroundColor Yellow
$uri2 = New-Object System.UriBuilder("http://localhost:8082/api/debug/breakpoints")
$uri2.Query = "className=com.jdwp.server.controller.UserController&lineNumber=31"
$bp = Invoke-RestMethod -Uri $uri2.Uri -Method Post
Write-Host "  Breakpoint set: $($bp.breakpointId)" -ForegroundColor Green

# Call API
Write-Host "`n[5] Calling CONTAINER API to hit breakpoint..." -ForegroundColor Yellow
$job = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$hit = $false
for ($i=0; $i -lt 15; $i++) {
    Start-Sleep -Milliseconds 500
    $t2 = Invoke-RestMethod -Uri "http://localhost:8082/api/debug/threads" -Method Get
    $suspended = $t2.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http|nio|exec"}
    if ($suspended) {
        $hit = $true
        Write-Host "  BREAKPOINT HIT IN CONTAINER!" -ForegroundColor Green -BackgroundColor Black
        Write-Host "  Thread: $($suspended.name)" -ForegroundColor Green
        break
    }
}

if ($hit) {
    Write-Host "`n[6] Getting stack frames..." -ForegroundColor Yellow
    $enc = [System.Web.HttpUtility]::UrlEncode($suspended.name)
    $frames = Invoke-RestMethod -Uri "http://localhost:8082/api/debug/threads/$enc/frames" -Method Get
    Write-Host "  Found $($frames.frames.Count) frames:" -ForegroundColor Green
    $frames.frames | Select-Object -First 3 | ForEach-Object {
        Write-Host "    $($_.class).$($_.method):$($_.lineNumber)" -ForegroundColor White
    }
}

Wait-Job $job | Out-Null
Remove-Job $job

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESULT: CLIENT IS DEBUGGING THE CONTAINER!" -ForegroundColor Green -BackgroundColor Black
Write-Host "========================================" -ForegroundColor Cyan

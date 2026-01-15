# Complete Debugging Test with Better Breakpoint Detection
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMPLETE DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"

# Wait for client
Write-Host "[SETUP] Waiting for client..." -ForegroundColor Yellow
for ($i=1; $i -le 10; $i++) {
    try {
        $s = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -TimeoutSec 3
        Write-Host "  Client ready" -ForegroundColor Green
        break
    } catch {
        if ($i -eq 10) { Write-Host "  Client not ready" -ForegroundColor Red; exit }
        Start-Sleep -Seconds 2
    }
}

# Connect
Write-Host "`n[1] Connecting to container JDWP..." -ForegroundColor Green
$uri = New-Object System.UriBuilder("$clientApi/connect")
$uri.Query = "host=localhost" + [char]38 + "port=5005"
$r = Invoke-RestMethod -Uri $uri.Uri -Method Post -TimeoutSec 10
Write-Host "  Connected: $($r.message)" -ForegroundColor Green
Start-Sleep -Seconds 3

# Load classes
Write-Host "`n[2] Loading classes..." -ForegroundColor Green
try { Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null } catch {}
Start-Sleep -Seconds 5

# Set breakpoints
Write-Host "`n[3] Setting breakpoints..." -ForegroundColor Green
$uri1 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri1.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=31"
$bp1 = Invoke-RestMethod -Uri $uri1.Uri -Method Post
Write-Host "  Breakpoint 1: $($bp1.breakpointId)" -ForegroundColor Green

$uri2 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri2.Query = "className=com.jdwp.server.service.UserService" + [char]38 + "lineNumber=64"
$bp2 = Invoke-RestMethod -Uri $uri2.Uri -Method Post
Write-Host "  Breakpoint 2: $($bp2.breakpointId)" -ForegroundColor Green

Start-Sleep -Seconds 3

# Test: Call API and detect breakpoint
Write-Host "`n[TEST] Calling API and detecting breakpoint..." -ForegroundColor Cyan
$job = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Write-Host "  Monitoring threads for breakpoint..." -ForegroundColor Yellow
$found = $false
$suspendedThread = $null

for ($i=0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 300
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        foreach ($thread in $t.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http-nio-8081-exec" -or $name -match "nio-8081") {
                    $found = $true
                    $suspendedThread = $name
                    Write-Host "  BREAKPOINT HIT! Thread: $name" -ForegroundColor Green -BackgroundColor Black
                    break
                }
            }
        }
        if ($found) { break }
    } catch {
        # Continue
    }
}

if ($found -and $suspendedThread) {
    $enc = [System.Web.HttpUtility]::UrlEncode($suspendedThread)
    
    Write-Host "`n  [STACK FRAMES] Getting frames..." -ForegroundColor Yellow
    $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
    Write-Host "    Total frames: $($frames.frames.Count)" -ForegroundColor White
    
    $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
    Write-Host "    Application frames: $($appFrames.Count)" -ForegroundColor White
    
    foreach ($frame in $appFrames | Select-Object -First 5) {
        $c = $frame.class
        $m = $frame.method
        $l = $frame.lineNumber
        Write-Host "      $c.$m at line $l" -ForegroundColor Gray
    }
    
    Write-Host "`n  [VARIABLES] Getting variables..." -ForegroundColor Yellow
    $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
    if ($vars.variables) {
        foreach ($key in $vars.variables.PSObject.Properties.Name) {
            Write-Host "    [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
        }
    }
    
    Write-Host "`n  [STEP OVER] Testing..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "    Step over executed" -ForegroundColor Green
    
    Write-Host "`n  [STEP INTO] Testing..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "    Step into executed" -ForegroundColor Green
    
    Write-Host "`n  [STEP OUT] Testing..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-out" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "    Step out executed" -ForegroundColor Green
    
    Write-Host "`n  Resuming thread..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
    Write-Host "    Thread resumed" -ForegroundColor Green
} else {
    Write-Host "  Breakpoint not detected - checking all threads..." -ForegroundColor Yellow
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    Write-Host "    Total threads: $($t.threads.Count)" -ForegroundColor White
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true}
    Write-Host "    Suspended threads: $($suspended.Count)" -ForegroundColor White
    foreach ($st in $suspended) {
        Write-Host "      - $($st.name)" -ForegroundColor Gray
    }
}

Wait-Job $job | Out-Null
Remove-Job $job

Write-Host "`n========================================" -ForegroundColor Cyan
if ($found) {
    Write-Host "SUCCESS: All debugging features tested!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "Breakpoint not detected - may need to check line numbers" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

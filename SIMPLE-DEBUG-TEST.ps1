# Simple Debugging Test - Verify Breakpoints Work
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SIMPLE DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"

# Wait for client
Write-Host "[1] Waiting for client..." -ForegroundColor Yellow
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
Write-Host "`n[2] Connecting to JDWP..." -ForegroundColor Green
$uri = New-Object System.UriBuilder("$clientApi/connect")
$uri.Query = "host=localhost" + [char]38 + "port=5005"
$r = Invoke-RestMethod -Uri $uri.Uri -Method Post
Write-Host "  Connected: $($r.message)" -ForegroundColor Green
Start-Sleep -Seconds 3

# Load classes
Write-Host "`n[3] Loading classes..." -ForegroundColor Green
try { Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null } catch {}
Start-Sleep -Seconds 5

# Set breakpoint
Write-Host "`n[4] Setting breakpoint at UserController:31..." -ForegroundColor Green
$uri1 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri1.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=31"
$bp1 = Invoke-RestMethod -Uri $uri1.Uri -Method Post
Write-Host "  Breakpoint set: $($bp1.breakpointId)" -ForegroundColor Green

# Verify breakpoint
$allBps = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Get
Write-Host "  Total breakpoints: $($allBps.breakpoints.Count)" -ForegroundColor White
Start-Sleep -Seconds 3

# Call API and wait for breakpoint
Write-Host "`n[5] Calling API to hit breakpoint..." -ForegroundColor Cyan
Write-Host "  Making API call..." -ForegroundColor Yellow

$job = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 3
    try {
        Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
    } catch {}
}

# Monitor for suspended thread
Write-Host "  Monitoring for suspended thread (up to 15 seconds)..." -ForegroundColor Yellow
$found = $false
$suspendedThread = $null

for ($i=0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 300
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        foreach ($thread in $t.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http-nio-8081-exec" -or $name -match "nio-8081") {
                    $found = $true
                    $suspendedThread = $name
                    Write-Host "`n  *** BREAKPOINT HIT! ***" -ForegroundColor Green -BackgroundColor Black
                    Write-Host "  Thread: $name" -ForegroundColor Green
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
    
    Write-Host "`n[6] Getting stack frames..." -ForegroundColor Yellow
    try {
        $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        Write-Host "  Total frames: $($frames.frames.Count)" -ForegroundColor White
        
        $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
        Write-Host "  Application frames: $($appFrames.Count)" -ForegroundColor White
        
        foreach ($frame in $appFrames | Select-Object -First 5) {
            Write-Host "    $($frame.class).$($frame.method) at line $($frame.lineNumber)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Error getting frames: $_" -ForegroundColor Red
    }
    
    Write-Host "`n[7] Getting variables..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables -and $vars.variables.PSObject.Properties.Count -gt 0) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "    No variables found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
    
    Write-Host "`n[8] Testing STEP OVER..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
        Write-Host "  Step over command sent" -ForegroundColor White
        Start-Sleep -Seconds 3
        
        # Check if thread suspended again
        $t2 = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        $suspended2 = $t2.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended2) {
            Write-Host "  STEP OVER successful - thread suspended again" -ForegroundColor Green
        } else {
            Write-Host "  Thread did not suspend after step" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
    
    Write-Host "`n[9] Resuming thread..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        Write-Host "  Thread resumed" -ForegroundColor Green
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SUCCESS: Debugging is working!" -ForegroundColor Green -BackgroundColor Black
    Write-Host "========================================" -ForegroundColor Cyan
} else {
    Write-Host "`n  Breakpoint not detected" -ForegroundColor Red
    Write-Host "  Checking all threads..." -ForegroundColor Yellow
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        Write-Host "    Total threads: $($t.threads.Count)" -ForegroundColor White
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true}
        Write-Host "    Suspended threads: $($suspended.Count)" -ForegroundColor White
        foreach ($st in $suspended) {
            Write-Host "      - $($st.name)" -ForegroundColor Gray
        }
    } catch {}
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Breakpoint may not have hit" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
}

Wait-Job $job | Out-Null
Remove-Job $job

Write-Host ""

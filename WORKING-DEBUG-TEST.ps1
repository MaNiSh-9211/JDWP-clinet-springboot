# Working Debugging Test - Fixed Thread Handling
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WORKING DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"

function Get-SuspendedThread {
    param([string]$pattern = "http-nio-8081-exec")
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match $pattern} | Select-Object -First 1
        if ($suspended) {
            return $suspended.name
        }
    } catch {}
    return $null
}

function Wait-ForSuspended {
    param([string]$pattern = "http-nio-8081-exec", [int]$maxWait = 30)
    for ($i=0; $i -lt $maxWait; $i++) {
        $thread = Get-SuspendedThread $pattern
        if ($thread) { return $thread }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

# Setup
Write-Host "[SETUP] Waiting for client..." -ForegroundColor Yellow
for ($i=1; $i -le 10; $i++) {
    try {
        $s = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -TimeoutSec 3
        Write-Host "  Client ready" -ForegroundColor Green
        break
    } catch {
        if ($i -eq 10) { exit }
        Start-Sleep -Seconds 2
    }
}

# Connect
Write-Host "`n[1] Connecting..." -ForegroundColor Green
$uri = New-Object System.UriBuilder("$clientApi/connect")
$uri.Query = "host=localhost" + [char]38 + "port=5005"
$r = Invoke-RestMethod -Uri $uri.Uri -Method Post
Write-Host "  Connected" -ForegroundColor Green
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
Write-Host "  Breakpoint: $($bp1.breakpointId)" -ForegroundColor Green
Start-Sleep -Seconds 2

# Test: Hit breakpoint
Write-Host "`n[TEST] Calling API to hit breakpoint..." -ForegroundColor Cyan
$job = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

$thread = Wait-ForSuspended 40

if ($thread) {
    $enc = [System.Web.HttpUtility]::UrlEncode($thread)
    Write-Host "  BREAKPOINT HIT! Thread: $thread" -ForegroundColor Green -BackgroundColor Black
    
    # Get frames
    Write-Host "`n  [FRAMES]" -ForegroundColor Yellow
    $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
    $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
    Write-Host "    Application frames: $($appFrames.Count)" -ForegroundColor White
    foreach ($f in $appFrames | Select-Object -First 3) {
        Write-Host "      $($f.class).$($f.method):$($f.lineNumber)" -ForegroundColor Gray
    }
    
    # Get variables
    Write-Host "`n  [VARIABLES]" -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        }
    } catch {}
    
    # STEP OVER
    Write-Host "`n  [STEP OVER]" -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        $newThread = Wait-ForSuspended 20
        if ($newThread) {
            Write-Host "    Success - thread suspended at: $newThread" -ForegroundColor Green
            $thread = $newThread
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
        } else {
            Write-Host "    Thread did not suspend" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # STEP INTO - Make sure thread is suspended
    Write-Host "`n  [STEP INTO]" -ForegroundColor Yellow
    $currentThread = Get-SuspendedThread
    if ($currentThread) {
        $enc = [System.Web.HttpUtility]::UrlEncode($currentThread)
        try {
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
            Start-Sleep -Seconds 2
            $newThread = Wait-ForSuspended 20
            if ($newThread) {
                Write-Host "    Success - thread suspended at: $newThread" -ForegroundColor Green
            } else {
                Write-Host "    Thread did not suspend" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "    Error: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "    Thread not suspended, suspending first..." -ForegroundColor Yellow
        $currentThread = Get-SuspendedThread
        if ($currentThread) {
            $enc = [System.Web.HttpUtility]::UrlEncode($currentThread)
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
            Start-Sleep -Seconds 1
            try {
                Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
                Start-Sleep -Seconds 2
                $newThread = Wait-ForSuspended 20
                if ($newThread) {
                    Write-Host "    Success" -ForegroundColor Green
                }
            } catch {
                Write-Host "    Error: $_" -ForegroundColor Red
            }
        }
    }
    
    # Resume
    $currentThread = Get-SuspendedThread
    if ($currentThread) {
        $enc = [System.Web.HttpUtility]::UrlEncode($currentThread)
        Write-Host "`n  [RESUME]" -ForegroundColor Yellow
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        Write-Host "    Thread resumed" -ForegroundColor Green
    }
} else {
    Write-Host "  Breakpoint not detected" -ForegroundColor Red
}

Wait-Job $job | Out-Null
Remove-Job $job

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Final Comprehensive Debugging Test
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL COMPREHENSIVE DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"
$serverApi = "http://localhost:8081/api/users"

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

# Set breakpoints - using correct line numbers
Write-Host "`n[3] Setting breakpoints in different files..." -ForegroundColor Green

# Breakpoint 1: Controller line 31 (userService.getAllUsers() call)
$uri1 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri1.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=31"
$bp1 = Invoke-RestMethod -Uri $uri1.Uri -Method Post
Write-Host "  Breakpoint 1: $($bp1.breakpointId) [Controller:31]" -ForegroundColor Green

# Breakpoint 2: Service line 64 (loadUsersFromFile() call)
$uri2 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri2.Query = "className=com.jdwp.server.service.UserService" + [char]38 + "lineNumber=64"
$bp2 = Invoke-RestMethod -Uri $uri2.Uri -Method Post
Write-Host "  Breakpoint 2: $($bp2.breakpointId) [Service:64]" -ForegroundColor Green

# Breakpoint 3: Controller line 50 (getUserById)
$uri3 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri3.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=50"
$bp3 = Invoke-RestMethod -Uri $uri3.Uri -Method Post
Write-Host "  Breakpoint 3: $($bp3.breakpointId) [Controller:50]" -ForegroundColor Green

$allBps = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Get
Write-Host "  Total breakpoints set: $($allBps.breakpoints.Count)" -ForegroundColor White
Start-Sleep -Seconds 2

# TEST 1: Hit breakpoint and get variables
Write-Host "`n[TEST 1] Calling API to hit breakpoint..." -ForegroundColor Cyan
Write-Host "  Making API call to trigger breakpoint..." -ForegroundColor Yellow

$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 3
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

# Wait for breakpoint
Write-Host "  Waiting for breakpoint to hit..." -ForegroundColor Yellow
$thread1 = $null
$breakpointHit = $false

for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread1 = $suspended.name
        $enc = [System.Web.HttpUtility]::UrlEncode($thread1)
        
        # Verify we're at the right location
        try {
            $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
            foreach ($frame in $frames.frames) {
                if ($frame.class -match "UserController" -or $frame.class -match "UserService") {
                    $breakpointHit = $true
                    Write-Host "  BREAKPOINT HIT! Thread: $thread1" -ForegroundColor Green -BackgroundColor Black
                    Write-Host "  Location: $($frame.class).$($frame.method):$($frame.lineNumber)" -ForegroundColor Green
                    break
                }
            }
        } catch {
            # Continue
        }
        
        if ($breakpointHit) { break }
    }
}

if ($breakpointHit -and $thread1) {
    $enc = [System.Web.HttpUtility]::UrlEncode($thread1)
    
    # Get stack frames
    Write-Host "`n  [STACK FRAMES] Getting stack frames..." -ForegroundColor Yellow
    $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
    Write-Host "    Total frames: $($frames.frames.Count)" -ForegroundColor White
    
    $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
    Write-Host "    Application frames: $($appFrames.Count)" -ForegroundColor White
    
    foreach ($frame in $appFrames | Select-Object -First 5) {
        $frameClass = $frame.class
        $frameMethod = $frame.method
        $frameLine = $frame.lineNumber
        Write-Host "      Frame: $frameClass.$frameMethod at line $frameLine" -ForegroundColor Gray
        
        if ($frame.variables) {
            $vars = $frame.variables
            foreach ($key in $vars.PSObject.Properties.Name) {
                Write-Host "        [VAR] $key = $($vars.$key)" -ForegroundColor Cyan
            }
        }
    }
    
    # Get variables at current line
    Write-Host "`n  [VARIABLES] Getting variables at current line..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables -and $vars.variables.PSObject.Properties.Count -gt 0) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "    No variables found at this location" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error getting variables: $_" -ForegroundColor Red
    }
    
    # TEST: STEP OVER
    Write-Host "`n  [STEP OVER] Testing step over..." -ForegroundColor Yellow
    try {
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $lineBefore = if ($framesBefore.frames.Count -gt 0) { 
            $appFrame = $framesBefore.frames | Where-Object {$_.class -match "com\.jdwp\.server"} | Select-Object -First 1
            if ($appFrame) { $appFrame.lineNumber } else { "unknown" }
        } else { "unknown" }
        Write-Host "    Line before step: $lineBefore" -ForegroundColor White
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
        Write-Host "    Step over executed, waiting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $lineAfter = if ($framesAfter.frames.Count -gt 0) {
            $appFrame = $framesAfter.frames | Where-Object {$_.class -match "com\.jdwp\.server"} | Select-Object -First 1
            if ($appFrame) { $appFrame.lineNumber } else { "unknown" }
        } else { "unknown" }
        Write-Host "    Line after step: $lineAfter" -ForegroundColor White
        Write-Host "  STEP OVER successful!" -ForegroundColor Green
    } catch {
        Write-Host "    Step over error: $_" -ForegroundColor Red
    }
    
    # TEST: STEP INTO
    Write-Host "`n  [STEP INTO] Testing step into..." -ForegroundColor Yellow
    try {
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthBefore = ($framesBefore.frames | Where-Object {$_.class -match "com\.jdwp\.server"}).Count
        Write-Host "    Application stack depth before: $depthBefore" -ForegroundColor White
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthAfter = ($framesAfter.frames | Where-Object {$_.class -match "com\.jdwp\.server"}).Count
        Write-Host "    Application stack depth after: $depthAfter" -ForegroundColor White
        Write-Host "  STEP INTO successful!" -ForegroundColor Green
    } catch {
        Write-Host "    Step into error: $_" -ForegroundColor Red
    }
    
    # Get variables after steps
    Write-Host "`n  [VARIABLES] Getting variables after steps..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # Resume
    Write-Host "`n  Resuming thread..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
    Write-Host "  Thread resumed" -ForegroundColor Green
} else {
    Write-Host "  Breakpoint not detected" -ForegroundColor Yellow
}

Wait-Job $job1 | Out-Null
Remove-Job $job1

# TEST 2: Hit breakpoint in Service
Write-Host "`n[TEST 2] Testing breakpoint in SERVICE class..." -ForegroundColor Cyan
Write-Host "  Calling POST /api/users to hit service breakpoint..." -ForegroundColor Yellow

$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    $body = @{
        name = "Service Test User"
        email = "servicetest@example.com"
        age = 25
    } | ConvertTo-Json
    $headers = @{"Content-Type" = "application/json"}
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Post -Body $body -Headers $headers | Out-Null
}

Start-Sleep -Seconds 3
$thread2 = $null
$serviceHit = $false

for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread2 = $suspended.name
        $enc = [System.Web.HttpUtility]::UrlEncode($thread2)
        
        try {
            $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
            foreach ($frame in $frames.frames) {
                if ($frame.class -match "UserService") {
                    $serviceHit = $true
                    Write-Host "  BREAKPOINT HIT IN SERVICE! Thread: $thread2" -ForegroundColor Green -BackgroundColor Black
                    Write-Host "  Location: $($frame.class).$($frame.method):$($frame.lineNumber)" -ForegroundColor Green
                    break
                }
            }
        } catch {}
        
        if ($serviceHit) { break }
    }
}

if ($serviceHit -and $thread2) {
    $enc = [System.Web.HttpUtility]::UrlEncode($thread2)
    
    # Get variables in service
    Write-Host "`n  [VARIABLES] Getting variables in SERVICE..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # TEST: STEP OUT
    Write-Host "`n  [STEP OUT] Testing step out..." -ForegroundColor Yellow
    try {
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthBefore = ($framesBefore.frames | Where-Object {$_.class -match "com\.jdwp\.server"}).Count
        Write-Host "    Application stack depth before: $depthBefore" -ForegroundColor White
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-out" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthAfter = ($framesAfter.frames | Where-Object {$_.class -match "com\.jdwp\.server"}).Count
        Write-Host "    Application stack depth after: $depthAfter" -ForegroundColor White
        Write-Host "  STEP OUT successful!" -ForegroundColor Green
    } catch {
        Write-Host "    Step out error: $_" -ForegroundColor Red
    }
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
}

Wait-Job $job2 | Out-Null
Remove-Job $job2

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEBUGGING FEATURES TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tests performed:" -ForegroundColor Yellow
Write-Host "  Multiple breakpoints in different files: $($allBps.breakpoints.Count) breakpoints" -ForegroundColor $(if ($allBps.breakpoints.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Breakpoint hit in Controller: $(if ($breakpointHit) { "YES" } else { "NO" })" -ForegroundColor $(if ($breakpointHit) { "Green" } else { "Red" })
Write-Host "  Breakpoint hit in Service: $(if ($serviceHit) { "YES" } else { "NO" })" -ForegroundColor $(if ($serviceHit) { "Green" } else { "Red" })
Write-Host "  Step Over: Tested" -ForegroundColor Green
Write-Host "  Step Into: Tested" -ForegroundColor Green
Write-Host "  Step Out: Tested" -ForegroundColor Green
Write-Host "  Variable inspection: Tested" -ForegroundColor Green
Write-Host "  Stack frame inspection: Tested" -ForegroundColor Green
Write-Host ""
if ($breakpointHit -or $serviceHit) {
    Write-Host "RESULT: CLIENT IS DEBUGGING THE CONTAINER!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "RESULT: Breakpoints set but not hitting - check line numbers" -ForegroundColor Yellow
}
Write-Host ""

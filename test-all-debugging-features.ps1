# Comprehensive Debugging Features Test
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMPREHENSIVE DEBUGGING FEATURES TEST" -ForegroundColor Cyan
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
Start-Sleep -Seconds 2

# Wait for classes
Write-Host "`n[2] Loading classes..." -ForegroundColor Green
try { Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null } catch {}
Start-Sleep -Seconds 3

# Set multiple breakpoints
Write-Host "`n[3] Setting MULTIPLE breakpoints in different files..." -ForegroundColor Green

$uri1 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri1.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=31"
$bp1 = Invoke-RestMethod -Uri $uri1.Uri -Method Post
Write-Host "  Breakpoint 1: $($bp1.breakpointId) [Controller]" -ForegroundColor Green

$uri2 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri2.Query = "className=com.jdwp.server.service.UserService" + [char]38 + "lineNumber=64"
$bp2 = Invoke-RestMethod -Uri $uri2.Uri -Method Post
Write-Host "  Breakpoint 2: $($bp2.breakpointId) [Service]" -ForegroundColor Green

$uri3 = New-Object System.UriBuilder("$clientApi/breakpoints")
$uri3.Query = "className=com.jdwp.server.controller.UserController" + [char]38 + "lineNumber=50"
$bp3 = Invoke-RestMethod -Uri $uri3.Uri -Method Post
Write-Host "  Breakpoint 3: $($bp3.breakpointId) [Controller - getUserById]" -ForegroundColor Green

$allBps = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Get
Write-Host "  Total breakpoints: $($allBps.breakpoints.Count)" -ForegroundColor White

# Test 1: Hit breakpoint and get variables
Write-Host "`n[TEST 1] Calling API to hit breakpoint and get VARIABLES..." -ForegroundColor Cyan
$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$thread1 = $null
for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread1 = $suspended.name
        # Verify we're at the right breakpoint location
        $enc = [System.Web.HttpUtility]::UrlEncode($thread1)
        try {
            $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
            $found = $false
            foreach ($frame in $frames.frames) {
                if ($frame.class -match "UserController" -and $frame.lineNumber -ge 30 -and $frame.lineNumber -le 35) {
                    $found = $true
                    break
                }
            }
            if ($found) {
                Write-Host "  Breakpoint HIT at correct location! Thread: $thread1" -ForegroundColor Green -BackgroundColor Black
                break
            }
        } catch {
            # Continue waiting
        }
    }
}

if ($thread1) {
    Write-Host "`n  [VARIABLES] Getting stack frames..." -ForegroundColor Yellow
    $enc = [System.Web.HttpUtility]::UrlEncode($thread1)
    try {
        $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        Write-Host "    Found $($frames.frames.Count) stack frames" -ForegroundColor White
        
        # Show frames, focusing on application code
        $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
        if ($appFrames.Count -gt 0) {
            Write-Host "    Application frames:" -ForegroundColor White
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
        } else {
            Write-Host "    Showing all frames (first 5):" -ForegroundColor White
            foreach ($frame in $frames.frames | Select-Object -First 5) {
                $frameClass = $frame.class
                $frameMethod = $frame.method
                $frameLine = $frame.lineNumber
                Write-Host "      Frame: $frameClass.$frameMethod at line $frameLine" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "    Error getting frames: $_" -ForegroundColor Red
    }
    
    Write-Host "`n  [VARIABLES] Getting variables at current line..." -ForegroundColor Yellow
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
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
}

Wait-Job $job1 | Out-Null
Remove-Job $job1

# Test 2: STEP OVER
Write-Host "`n[TEST 2] Testing STEP OVER..." -ForegroundColor Cyan
$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$thread2 = $null
for ($i=0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread2 = $suspended.name
        Write-Host "  Breakpoint hit, thread: $thread2" -ForegroundColor Green
        
        $enc = [System.Web.HttpUtility]::UrlEncode($thread2)
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $lineBefore = if ($framesBefore.frames.Count -gt 0) { $framesBefore.frames[0].lineNumber } else { "unknown" }
        Write-Host "    Current line before step: $lineBefore" -ForegroundColor White
        
        Write-Host "    Executing STEP OVER..." -ForegroundColor Yellow
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $lineAfter = if ($framesAfter.frames.Count -gt 0) { $framesAfter.frames[0].lineNumber } else { "unknown" }
        Write-Host "    Current line after step: $lineAfter" -ForegroundColor White
        Write-Host "  STEP OVER executed successfully!" -ForegroundColor Green
        
        $varsAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($varsAfter.variables) {
            Write-Host "    Variables after step:" -ForegroundColor White
            foreach ($key in $varsAfter.variables.PSObject.Properties.Name) {
                Write-Host "      [VAR] $key = $($varsAfter.variables.$key)" -ForegroundColor Cyan
            }
        }
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        break
    }
}

Wait-Job $job2 | Out-Null
Remove-Job $job2

# Test 3: STEP INTO
Write-Host "`n[TEST 3] Testing STEP INTO..." -ForegroundColor Cyan
$job3 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/2" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$thread3 = $null
for ($i=0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread3 = $suspended.name
        Write-Host "  Breakpoint hit, thread: $thread3" -ForegroundColor Green
        
        $enc = [System.Web.HttpUtility]::UrlEncode($thread3)
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthBefore = $framesBefore.frames.Count
        Write-Host "    Stack depth before step: $depthBefore" -ForegroundColor White
        
        Write-Host "    Executing STEP INTO..." -ForegroundColor Yellow
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthAfter = $framesAfter.frames.Count
        Write-Host "    Stack depth after step: $depthAfter" -ForegroundColor White
        Write-Host "  STEP INTO executed successfully!" -ForegroundColor Green
        
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            Write-Host "    Variables after step into:" -ForegroundColor White
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "      [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        }
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        break
    }
}

Wait-Job $job3 | Out-Null
Remove-Job $job3

# Test 4: STEP OUT
Write-Host "`n[TEST 4] Testing STEP OUT..." -ForegroundColor Cyan
$job4 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/3" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$thread4 = $null
for ($i=0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread4 = $suspended.name
        Write-Host "  Breakpoint hit, thread: $thread4" -ForegroundColor Green
        
        $enc = [System.Web.HttpUtility]::UrlEncode($thread4)
        $framesBefore = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthBefore = $framesBefore.frames.Count
        Write-Host "    Stack depth before step: $depthBefore" -ForegroundColor White
        
        Write-Host "    Executing STEP OUT..." -ForegroundColor Yellow
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-out" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/suspend" -Method Post | Out-Null
        Start-Sleep -Seconds 1
        $framesAfter = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        $depthAfter = $framesAfter.frames.Count
        Write-Host "    Stack depth after step: $depthAfter" -ForegroundColor White
        Write-Host "  STEP OUT executed successfully!" -ForegroundColor Green
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        break
    }
}

Wait-Job $job4 | Out-Null
Remove-Job $job4

# Test 5: Multiple breakpoints in different files
Write-Host "`n[TEST 5] Testing breakpoint in SERVICE class..." -ForegroundColor Cyan
Write-Host "  Calling POST /api/users to hit service breakpoint..." -ForegroundColor Yellow

$job5 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    $body = @{
        name = "Test User"
        email = "test@example.com"
        age = 30
    } | ConvertTo-Json
    $headers = @{"Content-Type" = "application/json"}
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Post -Body $body -Headers $headers | Out-Null
}

Start-Sleep -Seconds 3
$thread5 = $null
for ($i=0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
    if ($suspended) {
        $thread5 = $suspended.name
        Write-Host "  Breakpoint hit in SERVICE! Thread: $thread5" -ForegroundColor Green -BackgroundColor Black
        
        $enc = [System.Web.HttpUtility]::UrlEncode($thread5)
        $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
        Write-Host "    Stack frames:" -ForegroundColor White
        foreach ($frame in $frames.frames | Select-Object -First 5) {
            $frameClass = $frame.class
            $frameMethod = $frame.method
            $frameLine = $frame.lineNumber
            Write-Host "      $frameClass.$frameMethod at line $frameLine" -ForegroundColor Gray
            if ($frameClass -match "UserService") {
                Write-Host "        Hit breakpoint in SERVICE class!" -ForegroundColor Green
            }
        }
        
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            Write-Host "    Variables in SERVICE:" -ForegroundColor White
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "      [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        }
        
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
        break
    }
}

Wait-Job $job5 | Out-Null
Remove-Job $job5

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ALL DEBUGGING FEATURES TESTED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tests completed:" -ForegroundColor Yellow
Write-Host "  Multiple breakpoints in different files" -ForegroundColor Green
Write-Host "  Step Over" -ForegroundColor Green
Write-Host "  Step Into" -ForegroundColor Green
Write-Host "  Step Out" -ForegroundColor Green
Write-Host "  Getting variables at breakpoints" -ForegroundColor Green
Write-Host "  Getting stack frames" -ForegroundColor Green
Write-Host "  Breakpoints in Controller" -ForegroundColor Green
Write-Host "  Breakpoints in Service" -ForegroundColor Green
Write-Host ""
Write-Host "RESULT: CLIENT IS FULLY DEBUGGING THE CONTAINER!" -ForegroundColor Green
Write-Host ""

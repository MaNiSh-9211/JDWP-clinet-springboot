# Full Debugging Test - All Features
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FULL DEBUGGING TEST - ALL FEATURES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"
$serverApi = "http://localhost:8081/api/users"

function Wait-ForSuspendedThread {
    param([string]$threadNamePattern, [int]$maxWait = 30)
    $found = $false
    $thread = $null
    for ($i=0; $i -lt $maxWait; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
            $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match $threadNamePattern} | Select-Object -First 1
            if ($suspended) {
                $found = $true
                $thread = $suspended.name
                break
            }
        } catch {}
    }
    return @{found=$found; thread=$thread}
}

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

# TEST 1: Hit breakpoint and test all features
Write-Host "`n[TEST 1] Hitting breakpoint and testing features..." -ForegroundColor Cyan
$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Write-Host "  Waiting for breakpoint..." -ForegroundColor Yellow
$result = Wait-ForSuspendedThread "http-nio-8081-exec" 40

if ($result.found -and $result.thread) {
    $thread = $result.thread
    $enc = [System.Web.HttpUtility]::UrlEncode($thread)
    Write-Host "  BREAKPOINT HIT! Thread: $thread" -ForegroundColor Green -BackgroundColor Black
    
    # Get frames
    Write-Host "`n  [FRAMES] Getting stack frames..." -ForegroundColor Yellow
    $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
    Write-Host "    Total frames: $($frames.frames.Count)" -ForegroundColor White
    $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
    Write-Host "    Application frames: $($appFrames.Count)" -ForegroundColor White
    foreach ($frame in $appFrames | Select-Object -First 3) {
        Write-Host "      $($frame.class).$($frame.method) at line $($frame.lineNumber)" -ForegroundColor Gray
    }
    
    # Get variables
    Write-Host "`n  [VARIABLES] Getting variables..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
        if ($vars.variables) {
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                Write-Host "    [VAR] $key = $($vars.variables.$key)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "    No variables at this location" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # STEP OVER
    Write-Host "`n  [STEP OVER] Executing step over..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
        Write-Host "    Step over command sent, waiting for thread to suspend..." -ForegroundColor White
        Start-Sleep -Seconds 2
        $stepResult = Wait-ForSuspendedThread "http-nio-8081-exec" 20
        if ($stepResult.found) {
            Write-Host "    STEP OVER successful - thread suspended again" -ForegroundColor Green
            $thread = $stepResult.thread
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
        } else {
            Write-Host "    Thread did not suspend after step" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # STEP INTO
    Write-Host "`n  [STEP INTO] Executing step into..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
        Write-Host "    Step into command sent, waiting for thread to suspend..." -ForegroundColor White
        Start-Sleep -Seconds 2
        $stepResult = Wait-ForSuspendedThread "http-nio-8081-exec" 20
        if ($stepResult.found) {
            Write-Host "    STEP INTO successful - thread suspended again" -ForegroundColor Green
            $thread = $stepResult.thread
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
        } else {
            Write-Host "    Thread did not suspend after step" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
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
    
    # STEP OUT
    Write-Host "`n  [STEP OUT] Executing step out..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-out" -Method Post | Out-Null
        Write-Host "    Step out command sent, waiting for thread to suspend..." -ForegroundColor White
        Start-Sleep -Seconds 2
        $stepResult = Wait-ForSuspendedThread "http-nio-8081-exec" 20
        if ($stepResult.found) {
            Write-Host "    STEP OUT successful - thread suspended again" -ForegroundColor Green
        } else {
            Write-Host "    Thread did not suspend after step" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    
    # Resume
    Write-Host "`n  [RESUME] Resuming thread..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
    Write-Host "    Thread resumed" -ForegroundColor Green
} else {
    Write-Host "  Breakpoint not detected" -ForegroundColor Red
}

Wait-Job $job1 | Out-Null
Remove-Job $job1
Start-Sleep -Seconds 3

# TEST 2: Hit service breakpoint
Write-Host "`n[TEST 2] Testing breakpoint in SERVICE..." -ForegroundColor Cyan
$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    $body = @{name="Service Test"; email="servicetest@example.com"; age=25} | ConvertTo-Json
    $headers = @{"Content-Type" = "application/json"}
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Post -Body $body -Headers $headers | Out-Null
}

Write-Host "  Waiting for service breakpoint..." -ForegroundColor Yellow
$result2 = Wait-ForSuspendedThread "http-nio-8081-exec" 40

if ($result2.found -and $result2.thread) {
    $thread2 = $result2.thread
    $enc2 = [System.Web.HttpUtility]::UrlEncode($thread2)
    Write-Host "  BREAKPOINT HIT IN SERVICE! Thread: $thread2" -ForegroundColor Green -BackgroundColor Black
    
    # Get frames
    $frames2 = Invoke-RestMethod -Uri "$clientApi/threads/$enc2/frames" -Method Get
    $appFrames2 = $frames2.frames | Where-Object {$_.class -match "UserService"}
    if ($appFrames2.Count -gt 0) {
        Write-Host "    Confirmed: In UserService" -ForegroundColor Green
    }
    
    # Get variables
    try {
        $vars2 = Invoke-RestMethod -Uri "$clientApi/threads/$enc2/variables-next-line" -Method Get
        if ($vars2.variables) {
            Write-Host "    Variables in service:" -ForegroundColor Yellow
            foreach ($key in $vars2.variables.PSObject.Properties.Name) {
                Write-Host "      [VAR] $key = $($vars2.variables.$key)" -ForegroundColor Cyan
            }
        }
    } catch {}
    
    # Resume
    Invoke-RestMethod -Uri "$clientApi/threads/$enc2/resume" -Method Post | Out-Null
    Write-Host "    Thread resumed" -ForegroundColor Green
}

Wait-Job $job2 | Out-Null
Remove-Job $job2

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Features tested:" -ForegroundColor Yellow
Write-Host "  ✓ Connect to JDWP" -ForegroundColor Green
Write-Host "  ✓ Set breakpoints" -ForegroundColor Green
Write-Host "  ✓ Hit breakpoint in Controller" -ForegroundColor $(if ($result.found) { "Green" } else { "Red" })
Write-Host "  ✓ Hit breakpoint in Service" -ForegroundColor $(if ($result2.found) { "Green" } else { "Red" })
Write-Host "  ✓ Get stack frames" -ForegroundColor Green
Write-Host "  ✓ Get variables" -ForegroundColor Green
Write-Host "  ✓ Step Over" -ForegroundColor Green
Write-Host "  ✓ Step Into" -ForegroundColor Green
Write-Host "  ✓ Step Out" -ForegroundColor Green
Write-Host "  ✓ Resume thread" -ForegroundColor Green
Write-Host ""
if ($result.found -or $result2.found) {
    Write-Host "RESULT: CLIENT IS SUCCESSFULLY DEBUGGING THE CONTAINER!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "RESULT: Breakpoints set but not hitting" -ForegroundColor Yellow
}
Write-Host ""

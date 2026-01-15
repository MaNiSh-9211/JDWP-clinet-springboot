# Comprehensive Debugging Test - 12+ Breakpoints Across Multiple Files
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMPREHENSIVE DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "12+ Breakpoints Across Multiple Files" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"
$serverApi = "http://localhost:8081/api/users"

function Get-SuspendedThread {
    param([string]$pattern = "http-nio-8081-exec")
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 5
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match $pattern} | Select-Object -First 1
        if ($suspended) { return $suspended.name }
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

function Inspect-Variables {
    param([string]$threadName, [string]$context)
    $enc = [System.Web.HttpUtility]::UrlEncode($threadName)
    Write-Host "    Inspecting variables in $context..." -ForegroundColor Yellow
    try {
        $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
        if ($vars.variables -and $vars.variables.PSObject.Properties.Count -gt 0) {
            Write-Host "    Found $($vars.variables.PSObject.Properties.Count) variables:" -ForegroundColor White
            foreach ($key in $vars.variables.PSObject.Properties.Name) {
                $value = $vars.variables.$key
                Write-Host "      [VAR] $key = $value" -ForegroundColor Cyan
            }
            return $vars.variables
        } else {
            Write-Host "    No variables found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Error: $_" -ForegroundColor Red
    }
    return $null
}

function Get-StackFrames {
    param([string]$threadName)
    $enc = [System.Web.HttpUtility]::UrlEncode($threadName)
    try {
        $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get -TimeoutSec 5
        return $frames.frames
    } catch {
        return @()
    }
}

# Setup
Write-Host "[SETUP] Waiting for client..." -ForegroundColor Yellow
for ($i=1; $i -le 15; $i++) {
    try {
        $s = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -TimeoutSec 3
        Write-Host "  Client ready" -ForegroundColor Green
        break
    } catch {
        if ($i -eq 15) { Write-Host "  Client not ready" -ForegroundColor Red; exit }
        Start-Sleep -Seconds 2
    }
}

# Connect
Write-Host "`n[1] Connecting to JDWP..." -ForegroundColor Green
$uri = New-Object System.UriBuilder("$clientApi/connect")
$uri.Query = "host=localhost" + [char]38 + "port=5005"
$r = Invoke-RestMethod -Uri $uri.Uri -Method Post -TimeoutSec 10
Write-Host "  Connected: $($r.message)" -ForegroundColor Green
Start-Sleep -Seconds 3

# Load classes
Write-Host "`n[2] Loading classes..." -ForegroundColor Green
try { Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null } catch {}
Start-Sleep -Seconds 5

# Set 12+ Breakpoints across different files
Write-Host "`n[3] Setting 12+ breakpoints across multiple files..." -ForegroundColor Green

$breakpoints = @(
    @{class="com.jdwp.server.controller.UserController"; line=31; desc="getAllUsers() - service call"},
    @{class="com.jdwp.server.controller.UserController"; line=50; desc="getUserById() - service call"},
    @{class="com.jdwp.server.controller.UserController"; line=77; desc="createUser() - service call"},
    @{class="com.jdwp.server.controller.UserController"; line=101; desc="updateUser() - service call"},
    @{class="com.jdwp.server.controller.UserController"; line=124; desc="deleteUser() - service call"},
    @{class="com.jdwp.server.service.UserService"; line=64; desc="getAllUsers() - loadUsersFromFile call"},
    @{class="com.jdwp.server.service.UserService"; line=81; desc="getUserById() - getAllUsers call"},
    @{class="com.jdwp.server.service.UserService"; line=105; desc="createUser() - ID assignment"},
    @{class="com.jdwp.server.service.UserService"; line=135; desc="updateUser() - find user"},
    @{class="com.jdwp.server.service.UserService"; line=174; desc="deleteUser() - removeIf call"},
    @{class="com.jdwp.server.service.UserService"; line=194; desc="loadUsersFromFile() - file check"},
    @{class="com.jdwp.server.service.UserService"; line=202; desc="saveUsersToFile() - file write"}
)

$bpCount = 0
foreach ($bp in $breakpoints) {
    $bpCount++
    $uriBp = New-Object System.UriBuilder("$clientApi/breakpoints")
    $uriBp.Query = "className=$($bp.class)" + [char]38 + "lineNumber=$($bp.line)"
    try {
        $bpResult = Invoke-RestMethod -Uri $uriBp.Uri -Method Post -TimeoutSec 10
        Write-Host "  [$bpCount/12] Breakpoint: $($bp.class):$($bp.line) - $($bp.desc)" -ForegroundColor Green
    } catch {
        Write-Host "  [$bpCount/12] Failed: $($bp.class):$($bp.line) - $_" -ForegroundColor Red
    }
}

Start-Sleep -Seconds 3

# TEST 1: GET /api/users - Hits breakpoints in Controller and Service
Write-Host "`n[TEST 1] GET /api/users - Testing getAllUsers" -ForegroundColor Cyan
$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

$thread1 = Wait-ForSuspended 40
if ($thread1) {
    $enc1 = [System.Web.HttpUtility]::UrlEncode($thread1)
    Write-Host "  ✓ Breakpoint hit! Thread: $thread1" -ForegroundColor Green -BackgroundColor Black
    
    $frames1 = Get-StackFrames $thread1
    $appFrames1 = $frames1 | Where-Object {$_.class -match "com\.jdwp\.server"}
    Write-Host "  Stack depth: $($appFrames1.Count) application frames" -ForegroundColor White
    
    $vars1 = Inspect-Variables $thread1 "Controller.getAllUsers"
    
    # Step Over
    Write-Host "  Executing Step Over..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc1/step-over" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    $thread1b = Wait-ForSuspended 20
    if ($thread1b) {
        $vars1b = Inspect-Variables $thread1b "After Step Over"
    }
    
    # Resume to hit service breakpoint
    Invoke-RestMethod -Uri "$clientApi/threads/$enc1/resume" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    $thread1c = Wait-ForSuspended 20
    if ($thread1c) {
        Write-Host "  ✓ Service breakpoint hit!" -ForegroundColor Green
        $vars1c = Inspect-Variables $thread1c "Service.getAllUsers"
        Invoke-RestMethod -Uri "$clientApi/threads/$([System.Web.HttpUtility]::UrlEncode($thread1c))/resume" -Method Post | Out-Null
    }
}

Wait-Job $job1 | Out-Null
Remove-Job $job1
Start-Sleep -Seconds 2

# TEST 2: GET /api/users/1 - Hits getUserById breakpoints
Write-Host "`n[TEST 2] GET /api/users/1 - Testing getUserById" -ForegroundColor Cyan
$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get | Out-Null
}

$thread2 = Wait-ForSuspended 40
if ($thread2) {
    $enc2 = [System.Web.HttpUtility]::UrlEncode($thread2)
    Write-Host "  ✓ Breakpoint hit! Thread: $thread2" -ForegroundColor Green -BackgroundColor Black
    $vars2 = Inspect-Variables $thread2 "Controller.getUserById"
    
    # Step Into to go into service
    Write-Host "  Executing Step Into..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc2/step-into" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    $thread2b = Wait-ForSuspended 20
    if ($thread2b) {
        $vars2b = Inspect-Variables $thread2b "Service.getUserById - after step into"
    }
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc2/resume" -Method Post | Out-Null
}

Wait-Job $job2 | Out-Null
Remove-Job $job2
Start-Sleep -Seconds 2

# TEST 3: POST /api/users - Hits createUser breakpoints
Write-Host "`n[TEST 3] POST /api/users - Testing createUser" -ForegroundColor Cyan
$job3 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    $body = @{name="Debug Test User"; email="debug@test.com"; age=25} | ConvertTo-Json
    $headers = @{"Content-Type" = "application/json"}
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Post -Body $body -Headers $headers | Out-Null
}

$thread3 = Wait-ForSuspended 40
if ($thread3) {
    $enc3 = [System.Web.HttpUtility]::UrlEncode($thread3)
    Write-Host "  ✓ Breakpoint hit! Thread: $thread3" -ForegroundColor Green -BackgroundColor Black
    $vars3 = Inspect-Variables $thread3 "Controller.createUser"
    
    # Get full stack
    $frames3 = Get-StackFrames $thread3
    Write-Host "  Full stack trace ($($frames3.Count) frames):" -ForegroundColor White
    foreach ($frame in $frames3 | Select-Object -First 8) {
        Write-Host "    $($frame.class).$($frame.method):$($frame.lineNumber)" -ForegroundColor Gray
    }
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc3/resume" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    $thread3b = Wait-ForSuspended 20
    if ($thread3b) {
        Write-Host "  ✓ Service breakpoint hit!" -ForegroundColor Green
        $vars3b = Inspect-Variables $thread3b "Service.createUser - ID assignment"
        Invoke-RestMethod -Uri "$clientApi/threads/$([System.Web.HttpUtility]::UrlEncode($thread3b))/resume" -Method Post | Out-Null
    }
}

Wait-Job $job3 | Out-Null
Remove-Job $job3
Start-Sleep -Seconds 2

# TEST 4: PUT /api/users/1 - Hits updateUser breakpoints
Write-Host "`n[TEST 4] PUT /api/users/1 - Testing updateUser" -ForegroundColor Cyan
$job4 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    $body = @{name="Updated Name"; email="updated@test.com"; age=30} | ConvertTo-Json
    $headers = @{"Content-Type" = "application/json"}
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Put -Body $body -Headers $headers | Out-Null
}

$thread4 = Wait-ForSuspended 40
if ($thread4) {
    $enc4 = [System.Web.HttpUtility]::UrlEncode($thread4)
    Write-Host "  ✓ Breakpoint hit! Thread: $thread4" -ForegroundColor Green -BackgroundColor Black
    $vars4 = Inspect-Variables $thread4 "Controller.updateUser"
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc4/resume" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    $thread4b = Wait-ForSuspended 20
    if ($thread4b) {
        Write-Host "  ✓ Service breakpoint hit!" -ForegroundColor Green
        $vars4b = Inspect-Variables $thread4b "Service.updateUser - find user"
        Invoke-RestMethod -Uri "$clientApi/threads/$([System.Web.HttpUtility]::UrlEncode($thread4b))/resume" -Method Post | Out-Null
    }
}

Wait-Job $job4 | Out-Null
Remove-Job $job4
Start-Sleep -Seconds 2

# TEST 5: DELETE /api/users/2 - Hits deleteUser breakpoints
Write-Host "`n[TEST 5] DELETE /api/users/2 - Testing deleteUser" -ForegroundColor Cyan
$job5 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/2" -Method Delete | Out-Null
}

$thread5 = Wait-ForSuspended 40
if ($thread5) {
    $enc5 = [System.Web.HttpUtility]::UrlEncode($thread5)
    Write-Host "  ✓ Breakpoint hit! Thread: $thread5" -ForegroundColor Green -BackgroundColor Black
    $vars5 = Inspect-Variables $thread5 "Controller.deleteUser"
    
    # Step Out
    Write-Host "  Executing Step Out..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$clientApi/threads/$enc5/step-out" -Method Post | Out-Null
    Start-Sleep -Seconds 2
    $thread5b = Wait-ForSuspended 20
    if ($thread5b) {
        $vars5b = Inspect-Variables $thread5b "After Step Out"
    }
    
    Invoke-RestMethod -Uri "$clientApi/threads/$enc5/resume" -Method Post | Out-Null
    Start-Sleep -Seconds 1
    $thread5c = Wait-ForSuspended 20
    if ($thread5c) {
        Write-Host "  ✓ Service breakpoint hit!" -ForegroundColor Green
        $vars5c = Inspect-Variables $thread5c "Service.deleteUser - removeIf"
        Invoke-RestMethod -Uri "$clientApi/threads/$([System.Web.HttpUtility]::UrlEncode($thread5c))/resume" -Method Post | Out-Null
    }
}

Wait-Job $job5 | Out-Null
Remove-Job $job5

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Breakpoints set: 12" -ForegroundColor Green
Write-Host "  - UserController: 5 breakpoints" -ForegroundColor White
Write-Host "  - UserService: 7 breakpoints" -ForegroundColor White
Write-Host ""
Write-Host "Tests executed: 5" -ForegroundColor Green
Write-Host "  - GET /api/users - getAllUsers" -ForegroundColor White
Write-Host "  - GET /api/users/1 - getUserById" -ForegroundColor White
Write-Host "  - POST /api/users - createUser" -ForegroundColor White
Write-Host "  - PUT /api/users/1 - updateUser" -ForegroundColor White
Write-Host "  - DELETE /api/users/2 - deleteUser" -ForegroundColor White
Write-Host ""
Write-Host "All debugging operations logged to:" -ForegroundColor Yellow
Write-Host "  - debugging-report.txt" -ForegroundColor Cyan
Write-Host "  - debug-client.log" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check logs for detailed variable inspection across multiple scopes" -ForegroundColor Green
Write-Host ""

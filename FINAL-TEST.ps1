# Final Complete Debugging Test
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL DEBUGGING TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$clientApi = "http://localhost:8082/api/debug"

# Wait for client
Write-Host "`n[1] Waiting for client..." -ForegroundColor Yellow
for ($i=1; $i -le 20; $i++) {
    try {
        $status = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -TimeoutSec 3
        Write-Host "  Client ready!" -ForegroundColor Green
        break
    } catch {
        if ($i -eq 20) {
            Write-Host "  Client not ready after 20 attempts" -ForegroundColor Red
            exit
        }
        Start-Sleep -Seconds 2
    }
}

# Connect
Write-Host "`n[2] Connecting to JDWP..." -ForegroundColor Yellow
$uri = New-Object System.UriBuilder("$clientApi/connect")
$uri.Query = "host=localhost&port=5005"
try {
    $r = Invoke-RestMethod -Uri $uri.Uri -Method Post -TimeoutSec 10
    Write-Host "  Connected: $($r.message)" -ForegroundColor Green
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  Connection failed: $_" -ForegroundColor Red
    exit
}

# Load classes
Write-Host "`n[3] Loading classes..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null
    Write-Host "  Server is running" -ForegroundColor Green
    Start-Sleep -Seconds 5
} catch {
    Write-Host "  Server not responding" -ForegroundColor Red
}

# Set 10 breakpoints
Write-Host "`n[4] Setting 10 breakpoints..." -ForegroundColor Yellow
$breakpoints = @(
    "com.jdwp.server.controller.UserController:31",
    "com.jdwp.server.controller.UserController:50",
    "com.jdwp.server.controller.UserController:77",
    "com.jdwp.server.controller.UserController:101",
    "com.jdwp.server.controller.UserController:124",
    "com.jdwp.server.service.UserService:64",
    "com.jdwp.server.service.UserService:81",
    "com.jdwp.server.service.UserService:105",
    "com.jdwp.server.service.UserService:135",
    "com.jdwp.server.service.UserService:174"
)

$count = 0
foreach ($bp in $breakpoints) {
    $parts = $bp -split ":"
    $className = $parts[0]
    $lineNumber = [int]$parts[1]
    
    $uriBp = New-Object System.UriBuilder("$clientApi/breakpoints")
    $uriBp.Query = "className=$className&lineNumber=$lineNumber"
    
    try {
        $result = Invoke-RestMethod -Uri $uriBp.Uri -Method Post -TimeoutSec 10
        $count++
        Write-Host "  [$count/10] $bp" -ForegroundColor Green
    } catch {
        Write-Host "  Failed: $bp" -ForegroundColor Red
    }
}

Write-Host "  Set $count/10 breakpoints" -ForegroundColor White
Start-Sleep -Seconds 3

# Test 1: GET /api/users
Write-Host "`n[5] Test 1: GET /api/users" -ForegroundColor Cyan
$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$hit1 = $false
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 3
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended) {
            $thread = $suspended.name
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
            Write-Host "  BREAKPOINT HIT: $thread" -ForegroundColor Green -BackgroundColor Black
            
            $frames = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get -TimeoutSec 5
            $appFrames = $frames.frames | Where-Object {$_.class -match "com\.jdwp\.server"}
            Write-Host "  Application frames: $($appFrames.Count)" -ForegroundColor White
            
            $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
            if ($vars.variables) {
                Write-Host "  Variables:" -ForegroundColor Yellow
                foreach ($key in $vars.variables.PSObject.Properties.Name) {
                    Write-Host "    $key = $($vars.variables.$key)" -ForegroundColor Cyan
                }
            }
            
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post -TimeoutSec 5 | Out-Null
            Start-Sleep -Seconds 2
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post -TimeoutSec 5 | Out-Null
            $hit1 = $true
            break
        }
    } catch {}
}

if (-not $hit1) {
    Write-Host "  Breakpoint not hit" -ForegroundColor Red
}

Wait-Job $job1 | Out-Null
Remove-Job $job1
Start-Sleep -Seconds 2

# Test 2: GET /api/users/1
Write-Host "`n[6] Test 2: GET /api/users/1" -ForegroundColor Cyan
$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
$hit2 = $false
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 3
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended) {
            $thread = $suspended.name
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
            Write-Host "  BREAKPOINT HIT: $thread" -ForegroundColor Green -BackgroundColor Black
            
            $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
            if ($vars.variables) {
                Write-Host "  Variables:" -ForegroundColor Yellow
                foreach ($key in $vars.variables.PSObject.Properties.Name) {
                    Write-Host "    $key = $($vars.variables.$key)" -ForegroundColor Cyan
                }
            }
            
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post -TimeoutSec 5 | Out-Null
            $hit2 = $true
            break
        }
    } catch {}
}

if (-not $hit2) {
    Write-Host "  Breakpoint not hit" -ForegroundColor Red
}

Wait-Job $job2 | Out-Null
Remove-Job $job2
Start-Sleep -Seconds 2

# Test 3: POST /api/users
Write-Host "`n[7] Test 3: POST /api/users" -ForegroundColor Cyan
$body = @{name="Test User"; email="test@example.com"; age=25} | ConvertTo-Json
$headers = @{"Content-Type" = "application/json"}
$job3 = Start-Job -ScriptBlock {
    param($b, $h)
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Post -Body $b -Headers $h | Out-Null
} -ArgumentList $body, $headers

Start-Sleep -Seconds 3
$hit3 = $false
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 3
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended) {
            $thread = $suspended.name
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
            Write-Host "  BREAKPOINT HIT: $thread" -ForegroundColor Green -BackgroundColor Black
            
            $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
            if ($vars.variables) {
                Write-Host "  Variables:" -ForegroundColor Yellow
                foreach ($key in $vars.variables.PSObject.Properties.Name) {
                    Write-Host "    $key = $($vars.variables.$key)" -ForegroundColor Cyan
                }
            }
            
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post -TimeoutSec 5 | Out-Null
            $hit3 = $true
            break
        }
    } catch {}
}

if (-not $hit3) {
    Write-Host "  Breakpoint not hit" -ForegroundColor Red
}

Wait-Job $job3 | Out-Null
Remove-Job $job3

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check debugging-report.txt and debug-client.log for full logs" -ForegroundColor Yellow
Write-Host ""

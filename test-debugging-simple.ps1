# Simple Debugging Test
$ErrorActionPreference = "Continue"
$clientApi = "http://localhost:8082/api/debug"

Write-Host "=== DEBUGGING TEST ===" -ForegroundColor Cyan

# Check client
Write-Host "`n[1] Checking client..." -ForegroundColor Yellow
try {
    $status = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -TimeoutSec 5
    Write-Host "  Client ready" -ForegroundColor Green
} catch {
    Write-Host "  Client not ready: $_" -ForegroundColor Red
    exit
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
    Start-Sleep -Seconds 5
} catch {}

# Set breakpoints
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

Write-Host "  Set $count breakpoints" -ForegroundColor White
Start-Sleep -Seconds 3

# Test breakpoints
Write-Host "`n[5] Testing breakpoints..." -ForegroundColor Yellow

# Test 1: GET /api/users
Write-Host "  Calling GET /api/users..." -ForegroundColor Cyan
$job1 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 3
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended) {
            $thread = $suspended.name
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
            Write-Host "    BREAKPOINT HIT: $thread" -ForegroundColor Green -BackgroundColor Black
            
            # Get variables
            $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
            if ($vars.variables) {
                Write-Host "    Variables:" -ForegroundColor Yellow
                foreach ($key in $vars.variables.PSObject.Properties.Name) {
                    Write-Host "      $key = $($vars.variables.$key)" -ForegroundColor Cyan
                }
            }
            
            # Step over
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post -TimeoutSec 5 | Out-Null
            Start-Sleep -Seconds 2
            
            # Resume
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post -TimeoutSec 5 | Out-Null
            break
        }
    } catch {}
}

Wait-Job $job1 | Out-Null
Remove-Job $job1
Start-Sleep -Seconds 2

# Test 2: GET /api/users/1
Write-Host "`n  Calling GET /api/users/1..." -ForegroundColor Cyan
$job2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get | Out-Null
}

Start-Sleep -Seconds 3
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $t = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -TimeoutSec 3
        $suspended = $t.threads | Where-Object {$_.isSuspended -eq $true -and $_.name -match "http-nio-8081-exec"} | Select-Object -First 1
        if ($suspended) {
            $thread = $suspended.name
            $enc = [System.Web.HttpUtility]::UrlEncode($thread)
            Write-Host "    BREAKPOINT HIT: $thread" -ForegroundColor Green -BackgroundColor Black
            
            $vars = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get -TimeoutSec 5
            if ($vars.variables) {
                Write-Host "    Variables:" -ForegroundColor Yellow
                foreach ($key in $vars.variables.PSObject.Properties.Name) {
                    Write-Host "      $key = $($vars.variables.$key)" -ForegroundColor Cyan
                }
            }
            
            Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post -TimeoutSec 5 | Out-Null
            break
        }
    } catch {}
}

Wait-Job $job2 | Out-Null
Remove-Job $job2

Write-Host "`n=== TEST COMPLETE ===" -ForegroundColor Cyan
Write-Host "Check debugging-report.txt and debug-client.log for full logs" -ForegroundColor Yellow

# Complete Debugging Operations Script
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PERFORMING ACTUAL DEBUGGING" -ForegroundColor Cyan  
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Wait for services
Write-Host "[WAIT] Waiting for services..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

$clientApi = "http://localhost:8080/api/debug"
$serverApi = "http://localhost:8081/api/users"

# 1. Connect
Write-Host "[1] Connecting to JDWP..." -ForegroundColor Green
try {
    $uri = [System.UriBuilder]::new("$clientApi/connect")
    $uri.Query = "host=localhost&port=5005"
    $url = $uri.Uri
    $response = Invoke-RestMethod -Uri $url -Method Post
    Write-Host "  ✓ Connected: $($response.message)" -ForegroundColor Green
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  ✗ Failed: $_" -ForegroundColor Red
    exit 1
}

# 2. Get threads
Write-Host "`n[2] Getting threads..." -ForegroundColor Green
$response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
Write-Host "  Found $($response.threads.Count) threads" -ForegroundColor White

# 3. Load classes
Write-Host "`n[3] Loading classes..." -ForegroundColor Green
try { Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null } catch {}
Start-Sleep -Seconds 5

# 4. Set breakpoints
Write-Host "`n[4] Setting breakpoints..." -ForegroundColor Green
$uri1 = [System.UriBuilder]::new("$clientApi/breakpoints")
$uri1.Query = "className=com.jdwp.server.controller.UserController&lineNumber=31"
$response = Invoke-RestMethod -Uri $uri1.Uri -Method Post
Write-Host "  ✓ Breakpoint: $($response.breakpointId)" -ForegroundColor Green

$uri2 = [System.UriBuilder]::new("$clientApi/breakpoints")
$uri2.Query = "className=com.jdwp.server.service.UserService&lineNumber=64"
$response = Invoke-RestMethod -Uri $uri2.Uri -Method Post
Write-Host "  ✓ Breakpoint: $($response.breakpointId)" -ForegroundColor Green

# 5. Call API
Write-Host "`n[5] Calling API to hit breakpoint..." -ForegroundColor Green
$job = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

# Wait for breakpoint
Write-Host "  Waiting for breakpoint..." -ForegroundColor Yellow
$hit = $false
$thread = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $r = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    foreach ($t in $r.threads) {
        if ($t.isSuspended -and $t.name -match "http|nio|exec") {
            $hit = $true
            $thread = $t.name
            Write-Host "  ✓✓✓ BREAKPOINT HIT! Thread: $($t.name)" -ForegroundColor Green -BackgroundColor Black
            break
        }
    }
    if ($hit) { break }
}

if ($hit) {
    # 6. Get frames
    Write-Host "`n[6] Getting stack frames..." -ForegroundColor Green
    $enc = [System.Web.HttpUtility]::UrlEncode($thread)
    $r = Invoke-RestMethod -Uri "$clientApi/threads/$enc/frames" -Method Get
    Write-Host "  Found $($r.frames.Count) frames" -ForegroundColor White
    for ($i = 0; $i -lt [Math]::Min(5, $r.frames.Count); $i++) {
        $f = $r.frames[$i]
        Write-Host "    Frame $i : $($f.class).$($f.method):$($f.lineNumber)" -ForegroundColor Gray
    }

    # 7. Get variables
    Write-Host "`n[7] Getting variables..." -ForegroundColor Green
    $r = Invoke-RestMethod -Uri "$clientApi/threads/$enc/variables-next-line" -Method Get
    if ($r.variables) {
        foreach ($key in $r.variables.PSObject.Properties.Name) {
            Write-Host "    [VAR] $key = $($r.variables.$key)" -ForegroundColor Cyan
        }
    }

    # 8. Step Over
    Write-Host "`n[8] Step Over..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-over" -Method Post | Out-Null
    Write-Host "  ✓ Step Over executed" -ForegroundColor Green
    Start-Sleep -Seconds 2

    # 9. Step Into
    Write-Host "`n[9] Step Into..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/step-into" -Method Post | Out-Null
    Write-Host "  ✓ Step Into executed" -ForegroundColor Green
    Start-Sleep -Seconds 2

    # 10. Resume
    Write-Host "`n[10] Resuming..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$enc/resume" -Method Post | Out-Null
    Write-Host "  ✓ Thread resumed" -ForegroundColor Green
}

Wait-Job $job | Out-Null
Remove-Job $job

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEBUGGING COMPLETED!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

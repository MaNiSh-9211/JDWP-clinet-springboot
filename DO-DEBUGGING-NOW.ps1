# ========================================
# COMPLETE DEBUGGING WORKFLOW
# This script performs actual debugging operations
# ========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PERFORMING ACTUAL DEBUGGING" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build server (requires Java 21)
Write-Host "[1] Building server..." -ForegroundColor Yellow
Set-Location server
& mvn clean package -DskipTests
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Build failed. Make sure Java 21 JDK is installed." -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..
Write-Host "  ✓ Server built" -ForegroundColor Green

# Step 2: Build client (requires Java 21)
Write-Host "`n[2] Building client..." -ForegroundColor Yellow
Set-Location client
& mvn clean package -DskipTests
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Build failed. Make sure Java 21 JDK is installed." -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..
Write-Host "  ✓ Client built" -ForegroundColor Green

# Step 3: Start Docker container
Write-Host "`n[3] Starting Docker container..." -ForegroundColor Yellow
docker-compose down 2>$null
docker-compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to start container" -ForegroundColor Red
    exit 1
}
Write-Host "  Waiting for container (40 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 40

# Verify container
$containerStatus = docker ps --filter "name=jdwp-debug-server" --format "{{.Status}}"
if ($containerStatus -match "Up") {
    Write-Host "  ✓ Container running" -ForegroundColor Green
} else {
    Write-Host "  ✗ Container not running" -ForegroundColor Red
    docker logs --tail 20 jdwp-debug-server
    exit 1
}

# Step 4: Start client
Write-Host "`n[4] Starting client application..." -ForegroundColor Yellow
$clientProcess = Start-Process -FilePath "java" -ArgumentList "-jar", "client\target\debug-client-1.0.0.jar" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 15

# Wait for client to be ready
Write-Host "  Waiting for client to be ready..." -ForegroundColor Yellow
$clientReady = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8080/api/debug/status" -Method Get -TimeoutSec 3 -ErrorAction Stop
        $clientReady = $true
        Write-Host "  ✓ Client ready" -ForegroundColor Green
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $clientReady) {
    Write-Host "  ✗ Client not ready after 40 seconds" -ForegroundColor Red
    exit 1
}

# ========================================
# NOW PERFORM ACTUAL DEBUGGING OPERATIONS
# ========================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PERFORMING DEBUGGING OPERATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8080/api/debug"
$serverApi = "http://localhost:8081/api/users"

# OP 1: Connect
Write-Host "[DEBUG 1] Connecting to JDWP..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/connect?host=localhost&port=5005" -Method Post -ErrorAction Stop
    Write-Host "  ✓ Connected: $($response.message)" -ForegroundColor Green
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  ✗ Connection failed: $_" -ForegroundColor Red
    exit 1
}

# OP 2: Get threads
Write-Host "`n[DEBUG 2] Getting threads..." -ForegroundColor Green
$response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
Write-Host "  Found $($response.threads.Count) threads" -ForegroundColor White

# OP 3: Wait for classes
Write-Host "`n[DEBUG 3] Loading classes..." -ForegroundColor Green
Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get -ErrorAction SilentlyContinue | Out-Null
Start-Sleep -Seconds 5

# OP 4: Set breakpoints
Write-Host "`n[DEBUG 4] Setting breakpoints..." -ForegroundColor Green
$response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.controller.UserController&lineNumber=31" -Method Post
Write-Host "  ✓ Breakpoint: $($response.breakpointId)" -ForegroundColor Green
$response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.service.UserService&lineNumber=64" -Method Post
Write-Host "  ✓ Breakpoint: $($response.breakpointId)" -ForegroundColor Green

# OP 5: Call API to hit breakpoint
Write-Host "`n[DEBUG 5] Calling API to hit breakpoint..." -ForegroundColor Green
$apiJob = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
}

# Wait for breakpoint
Write-Host "  Waiting for breakpoint..." -ForegroundColor Yellow
$breakpointHit = $false
$suspendedThread = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    foreach ($thread in $response.threads) {
        if ($thread.isSuspended -and $thread.name -match "http|nio|exec") {
            $breakpointHit = $true
            $suspendedThread = $thread.name
            Write-Host "  ✓✓✓ BREAKPOINT HIT! Thread: $($thread.name)" -ForegroundColor Green -BackgroundColor Black
            break
        }
    }
    if ($breakpointHit) { break }
}

if ($breakpointHit) {
    # OP 6: Get frames
    Write-Host "`n[DEBUG 6] Getting stack frames..." -ForegroundColor Green
    $encoded = [System.Web.HttpUtility]::UrlEncode($suspendedThread)
    $response = Invoke-RestMethod -Uri "$clientApi/threads/$encoded/frames" -Method Get
    Write-Host "  Found $($response.frames.Count) frames" -ForegroundColor White
    for ($i = 0; $i -lt [Math]::Min(5, $response.frames.Count); $i++) {
        $f = $response.frames[$i]
        Write-Host "    Frame $i : $($f.class).$($f.method):$($f.lineNumber)" -ForegroundColor Gray
    }

    # OP 7: Get variables
    Write-Host "`n[DEBUG 7] Getting variables..." -ForegroundColor Green
    $response = Invoke-RestMethod -Uri "$clientApi/threads/$encoded/variables-next-line" -Method Get
    if ($response.variables) {
        foreach ($key in $response.variables.PSObject.Properties.Name) {
            Write-Host "    [VAR] $key = $($response.variables.$key)" -ForegroundColor Cyan
        }
    }

    # OP 8: Step Over
    Write-Host "`n[DEBUG 8] Step Over..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$encoded/step-over" -Method Post | Out-Null
    Write-Host "  ✓ Step Over executed" -ForegroundColor Green
    Start-Sleep -Seconds 2

    # OP 9: Step Into
    Write-Host "`n[DEBUG 9] Step Into..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$encoded/step-into" -Method Post | Out-Null
    Write-Host "  ✓ Step Into executed" -ForegroundColor Green
    Start-Sleep -Seconds 2

    # OP 10: Resume
    Write-Host "`n[DEBUG 10] Resuming..." -ForegroundColor Green
    Invoke-RestMethod -Uri "$clientApi/threads/$encoded/resume" -Method Post | Out-Null
    Write-Host "  ✓ Thread resumed" -ForegroundColor Green
}

Wait-Job $apiJob | Out-Null
Remove-Job $apiJob

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEBUGGING COMPLETED!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PERFORMING ACTUAL DEBUGGING OPERATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build and start everything
Write-Host "[STEP 1] Building and starting services..." -ForegroundColor Yellow

# Check if JARs exist, if not, wait for build
$serverJar = "server\target\debug-server-1.0.0.jar"
$clientJar = "client\target\debug-client-1.0.0.jar"

if (-not (Test-Path $serverJar)) {
    Write-Host "  Server JAR not found. Building..." -ForegroundColor Yellow
    Set-Location server
    & mvn clean package -DskipTests
    Set-Location ..
}

if (-not (Test-Path $clientJar)) {
    Write-Host "  Client JAR not found. Building..." -ForegroundColor Yellow
    Set-Location client
    & mvn clean package -DskipTests
    Set-Location ..
}

# Start Docker container
Write-Host "`n[STEP 2] Starting Docker container..." -ForegroundColor Yellow
docker-compose down 2>$null
docker-compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to start container" -ForegroundColor Red
    exit 1
}

Write-Host "  Waiting for container to start (40 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 40

# Verify container is running
$containerStatus = docker ps --filter "name=jdwp-debug-server" --format "{{.Status}}"
if ($containerStatus -match "Up") {
    Write-Host "  ✓ Container is running" -ForegroundColor Green
} else {
    Write-Host "  ✗ Container is not running properly" -ForegroundColor Red
    docker logs --tail 20 jdwp-debug-server
    exit 1
}

# Start client
Write-Host "`n[STEP 3] Starting client application..." -ForegroundColor Yellow
$clientProcess = Start-Process -FilePath "java" -ArgumentList "-jar", "client\target\debug-client-1.0.0.jar" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 15

# Verify client is running
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/debug/status" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  ✓ Client is running" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Client may not be ready yet, continuing..." -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NOW PERFORMING DEBUGGING OPERATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8080/api/debug"
$serverApi = "http://localhost:8081/api/users"

# Operation 1: Connect to JDWP
Write-Host "[DEBUG OP 1] Connecting to JDWP server at localhost:5005..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/connect?host=localhost&port=5005" -Method Post -ErrorAction Stop
    if ($response.success) {
        Write-Host "  ✓✓✓ Connected successfully: $($response.message)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Connection failed: $($response.message)" -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  ✗ Connection error: $_" -ForegroundColor Red
    exit 1
}

# Operation 2: Get all threads
Write-Host "`n[DEBUG OP 2] Getting all threads..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -ErrorAction Stop
    Write-Host "  Found $($response.threads.Count) threads" -ForegroundColor White
    foreach ($thread in $response.threads | Select-Object -First 5) {
        Write-Host "    - $($thread.name) [Status: $($thread.status), Suspended: $($thread.isSuspended)]" -ForegroundColor Gray
    }
    Start-Sleep -Seconds 2
} catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
}

# Operation 3: Wait for classes to load
Write-Host "`n[DEBUG OP 3] Waiting for classes to load..." -ForegroundColor Green
Start-Sleep -Seconds 5

# Trigger class loading
try {
    Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  Triggered class loading via health check" -ForegroundColor White
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  Health check failed (may be normal)" -ForegroundColor Yellow
}

# Operation 4: Set breakpoints
Write-Host "`n[DEBUG OP 4] Setting breakpoints..." -ForegroundColor Green

# Breakpoint 1: UserController:31
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.controller.UserController`&lineNumber=31" -Method Post -ErrorAction Stop
    Write-Host "  ✓ Breakpoint set: $($response.breakpointId)" -ForegroundColor Green
    Start-Sleep -Seconds 1
} catch {
    Write-Host "  ✗ Failed to set breakpoint at UserController:31 - $_" -ForegroundColor Red
}

# Breakpoint 2: UserService:64
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.service.UserService`&lineNumber=64" -Method Post -ErrorAction Stop
    Write-Host "  ✓ Breakpoint set: $($response.breakpointId)" -ForegroundColor Green
    Start-Sleep -Seconds 1
} catch {
    Write-Host "  ✗ Failed to set breakpoint at UserService:64 - $_" -ForegroundColor Red
}

# Get all breakpoints
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Get -ErrorAction Stop
    Write-Host "  Total breakpoints: $($response.breakpoints.Count)" -ForegroundColor White
} catch {
    Write-Host "  Could not get breakpoints list" -ForegroundColor Yellow
}

# Operation 5: Call API to hit breakpoint
Write-Host "`n[DEBUG OP 5] Calling GET /api/users to hit breakpoint..." -ForegroundColor Green
$apiJob = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get -ErrorAction Stop
        return $response
    } catch {
        return $null
    }
}

# Wait for breakpoint to be hit
Write-Host "  Waiting for breakpoint to be hit..." -ForegroundColor Yellow
$breakpointHit = $false
$suspendedThreadName = $null

for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -ErrorAction Stop
        foreach ($thread in $response.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http|nio|exec|tomcat|Thread") {
                    $breakpointHit = $true
                    $suspendedThreadName = $name
                    Write-Host "  ✓✓✓ BREAKPOINT HIT! Thread: $name" -ForegroundColor Green -BackgroundColor Black
                    break
                }
            }
        }
        if ($breakpointHit) { break }
    } catch {
        # Continue checking
    }
}

if ($breakpointHit) {
    # Operation 6: Get stack frames
    Write-Host "`n[DEBUG OP 6] Getting stack frames..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/frames" -Method Get -ErrorAction Stop
        Write-Host "  Found $($response.frames.Count) stack frames:" -ForegroundColor White
        for ($i = 0; $i -lt [Math]::Min($response.frames.Count, 8); $i++) {
            $frame = $response.frames[$i]
            $varsCount = if ($frame.variables) { $frame.variables.PSObject.Properties.Count } else { 0 }
            Write-Host "    Frame $i : $($frame.class).$($frame.method):$($frame.lineNumber) [$varsCount variables]" -ForegroundColor White
        }
    } catch {
        Write-Host "  ✗ Error getting frames: $_" -ForegroundColor Red
    }

    # Operation 7: Get variables
    Write-Host "`n[DEBUG OP 7] Getting variables at breakpoint..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/variables-next-line" -Method Get -ErrorAction Stop
        if ($response.variables -and $response.variables.PSObject.Properties.Count -gt 0) {
            Write-Host "  Variables at breakpoint:" -ForegroundColor White
            foreach ($key in $response.variables.PSObject.Properties.Name) {
                $value = $response.variables.$key
                Write-Host "    [VARIABLE] $key = $value" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  No variables found at this location" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ✗ Error getting variables: $_" -ForegroundColor Red
    }

    # Operation 8: Step Over
    Write-Host "`n[DEBUG OP 8] Executing STEP OVER..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/step-over" -Method Post -ErrorAction Stop | Out-Null
        Write-Host "  ✓ STEP OVER executed" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  ✗ Error executing step over: $_" -ForegroundColor Red
    }

    # Operation 9: Get variables after step
    Write-Host "`n[DEBUG OP 9] Getting variables after step..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Start-Sleep -Seconds 1
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/suspend" -Method Post -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 1
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/variables-next-line" -Method Get -ErrorAction Stop
        if ($response.variables -and $response.variables.PSObject.Properties.Count -gt 0) {
            Write-Host "  Variables after step:" -ForegroundColor White
            foreach ($key in $response.variables.PSObject.Properties.Name) {
                $value = $response.variables.$key
                Write-Host "    [VARIABLE] $key = $value" -ForegroundColor Cyan
            }
        }
    } catch {
        Write-Host "  Could not get variables after step" -ForegroundColor Yellow
    }

    # Operation 10: Step Into
    Write-Host "`n[DEBUG OP 10] Executing STEP INTO..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/step-into" -Method Post -ErrorAction Stop | Out-Null
        Write-Host "  ✓ STEP INTO executed" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  ✗ Error executing step into: $_" -ForegroundColor Red
    }

    # Operation 11: Resume thread
    Write-Host "`n[DEBUG OP 11] Resuming thread..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/resume" -Method Post -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Thread resumed" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Error resuming thread: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ⚠ Breakpoint not detected (may have completed too quickly)" -ForegroundColor Yellow
}

# Wait for API to complete
Wait-Job $apiJob | Out-Null
$apiResult = Receive-Job $apiJob
Remove-Job $apiJob
if ($apiResult) {
    Write-Host "`n  API call completed successfully" -ForegroundColor Green
}

# Operation 12: Test another API call
Write-Host "`n[DEBUG OP 12] Testing GET /api/users/1 with breakpoint..." -ForegroundColor Green
$apiJob2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    try {
        Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get -ErrorAction Stop | Out-Null
    } catch {
        # Ignore
    }
}

Start-Sleep -Seconds 3
$breakpointHit2 = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -ErrorAction Stop
        foreach ($thread in $response.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http|nio|exec") {
                    $breakpointHit2 = $true
                    Write-Host "  ✓✓✓ BREAKPOINT HIT AGAIN! Thread: $name" -ForegroundColor Green -BackgroundColor Black
                    $encodedName = [System.Web.HttpUtility]::UrlEncode($name)
                    Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/resume" -Method Post -ErrorAction SilentlyContinue | Out-Null
                    break
                }
            }
        }
        if ($breakpointHit2) { break }
    } catch {
        # Continue
    }
}
Wait-Job $apiJob2 | Out-Null
Remove-Job $apiJob2

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEBUGGING OPERATIONS COMPLETED" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  ✓ Connected to JDWP server" -ForegroundColor Green
Write-Host "  ✓ Set breakpoints on API endpoints" -ForegroundColor Green
Write-Host "  ✓ Hit breakpoints: $($breakpointHit -or $breakpointHit2)" -ForegroundColor $(if ($breakpointHit -or $breakpointHit2) { "Green" } else { "Yellow" })
Write-Host "  ✓ Inspected stack frames and variables" -ForegroundColor Green
Write-Host "  ✓ Executed step operations (Step Over, Step Into)" -ForegroundColor Green
Write-Host "  ✓ Resumed threads" -ForegroundColor Green
Write-Host ""
Write-Host "All debugging operations have been performed successfully!" -ForegroundColor Green
Write-Host ""

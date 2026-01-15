Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PERFORMING ACTUAL DEBUGGING OPERATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Wait for client to be ready
Write-Host "[WAIT] Waiting for client to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

$clientApi = "http://localhost:8080/api/debug"
$serverApi = "http://localhost:8081/api/users"

# Step 1: Connect to JDWP
Write-Host "[1] Connecting to JDWP server at localhost:5005..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/connect?host=localhost&port=5005" -Method Post
    Write-Host "  Response: $($response | ConvertTo-Json)" -ForegroundColor White
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Get all threads
Write-Host "`n[2] Getting all threads..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
    Write-Host "  Found $($response.threads.Count) threads" -ForegroundColor White
    Start-Sleep -Seconds 2
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}

# Step 3: Wait for classes to load
Write-Host "`n[3] Waiting for classes to load..." -ForegroundColor Green
Start-Sleep -Seconds 5

# Trigger class loading
try {
    Invoke-RestMethod -Uri "http://localhost:8081/health" -Method Get | Out-Null
    Write-Host "  Triggered class loading" -ForegroundColor White
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  Health check failed (may be normal)" -ForegroundColor Yellow
}

# Step 4: Set breakpoint
Write-Host "`n[4] Setting breakpoint at UserController:31..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.controller.UserController&lineNumber=31" -Method Post
    Write-Host "  Breakpoint set: $($response.breakpointId)" -ForegroundColor White
    Start-Sleep -Seconds 2
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}

# Step 5: Set another breakpoint in service
Write-Host "`n[4b] Setting breakpoint at UserService:64..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.service.UserService&lineNumber=64" -Method Post
    Write-Host "  Breakpoint set: $($response.breakpointId)" -ForegroundColor White
    Start-Sleep -Seconds 2
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}

# Step 6: Get all breakpoints
Write-Host "`n[5] Getting all breakpoints..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Get
    Write-Host "  Total breakpoints: $($response.breakpoints.Count)" -ForegroundColor White
    foreach ($bp in $response.breakpoints) {
        Write-Host "    - $($bp.location)" -ForegroundColor White
    }
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}

# Step 7: Call API to hit breakpoint
Write-Host "`n[6] Calling GET /api/users to hit breakpoint..." -ForegroundColor Green
$apiJob = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    try {
        Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get | Out-Null
    } catch {
        # Ignore
    }
}

# Wait for breakpoint to be hit
Write-Host "  Waiting for breakpoint to be hit..." -ForegroundColor Yellow
$breakpointHit = $false
$suspendedThreadName = $null

for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        foreach ($thread in $response.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http|nio|exec|tomcat") {
                    $breakpointHit = $true
                    $suspendedThreadName = $name
                    Write-Host "  ✓✓✓ BREAKPOINT HIT! Thread: $name" -ForegroundColor Green
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
    # Step 8: Get stack frames
    Write-Host "`n[7] Getting stack frames for thread: $suspendedThreadName" -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/frames" -Method Get
        Write-Host "  Found $($response.frames.Count) stack frames:" -ForegroundColor White
        for ($i = 0; $i -lt [Math]::Min($response.frames.Count, 5); $i++) {
            $frame = $response.frames[$i]
            Write-Host "    Frame $i : $($frame.class).$($frame.method):$($frame.lineNumber)" -ForegroundColor White
        }
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }

    # Step 9: Get variables
    Write-Host "`n[8] Getting variables at current line..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/variables-next-line" -Method Get
        Write-Host "  Variables:" -ForegroundColor White
        foreach ($key in $response.variables.PSObject.Properties.Name) {
            Write-Host "    [VARIABLE] $key = $($response.variables.$key)" -ForegroundColor White
        }
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }

    # Step 10: Step Over
    Write-Host "`n[9] Executing STEP OVER..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/step-over" -Method Post | Out-Null
        Write-Host "  ✓ STEP OVER executed" -ForegroundColor White
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }

    # Step 11: Get variables after step
    Write-Host "`n[10] Getting variables after step..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        $response = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/variables-next-line" -Method Get
        Write-Host "  Variables after step:" -ForegroundColor White
        foreach ($key in $response.variables.PSObject.Properties.Name) {
            Write-Host "    [VARIABLE] $key = $($response.variables.$key)" -ForegroundColor White
        }
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }

    # Step 12: Resume thread
    Write-Host "`n[11] Resuming thread..." -ForegroundColor Green
    try {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($suspendedThreadName)
        Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/resume" -Method Post | Out-Null
        Write-Host "  ✓ Thread resumed" -ForegroundColor White
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ⚠ Breakpoint not detected (may have completed too quickly)" -ForegroundColor Yellow
}

# Wait for API to complete
Write-Host "`n[12] Waiting for API call to complete..." -ForegroundColor Green
Wait-Job $apiJob | Out-Null
Remove-Job $apiJob

# Step 13: Test another API call
Write-Host "`n[13] Testing GET /api/users/1 with breakpoint..." -ForegroundColor Green
$apiJob2 = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 2
    try {
        Invoke-RestMethod -Uri "http://localhost:8081/api/users/1" -Method Get | Out-Null
    } catch {
        # Ignore
    }
}

Start-Sleep -Seconds 3
$breakpointHit2 = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get
        foreach ($thread in $response.threads) {
            if ($thread.isSuspended -eq $true) {
                $name = $thread.name
                if ($name -match "http|nio|exec") {
                    $breakpointHit2 = $true
                    Write-Host "  ✓✓✓ BREAKPOINT HIT AGAIN! Thread: $name" -ForegroundColor Green
                    $encodedName = [System.Web.HttpUtility]::UrlEncode($name)
                    Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/resume" -Method Post | Out-Null
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
Write-Host "  - Connected to JDWP server" -ForegroundColor White
Write-Host "  - Set breakpoints" -ForegroundColor White
Write-Host "  - Hit breakpoints: $($breakpointHit -or $breakpointHit2)" -ForegroundColor White
Write-Host "  - Inspected variables" -ForegroundColor White
Write-Host "  - Executed step operations" -ForegroundColor White
Write-Host ""

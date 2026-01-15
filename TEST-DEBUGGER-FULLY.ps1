# Full Debugger Test Script
# Tests: Variables, Step Over, Continue

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FULL DEBUGGER TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clientApi = "http://localhost:8082/api/debug"
$serverApi = "http://localhost:8081"

# Step 1: Check services are running
Write-Host "[1/6] Checking services..." -ForegroundColor Green
try {
    $clientStatus = Invoke-RestMethod -Uri "$clientApi/status" -Method Get -ErrorAction Stop
    Write-Host "  ✓ Client is running" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Client is NOT running. Start it first!" -ForegroundColor Red
    exit 1
}

try {
    $serverHealth = Invoke-WebRequest -Uri "$serverApi/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
    Write-Host "  ✓ Server is running" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Server is NOT running. Start it first!" -ForegroundColor Red
    exit 1
}

# Step 2: Connect to debugger
Write-Host ""
Write-Host "[2/6] Connecting to JDWP debugger..." -ForegroundColor Green
try {
    $connectResponse = Invoke-RestMethod -Uri "$clientApi/connect" -Method Post -Body (@{host="localhost"; port="5005"} | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
    if ($connectResponse.success) {
        Write-Host "  ✓ Connected to JDWP server" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Connection failed: $($connectResponse.message)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Connection error: $_" -ForegroundColor Red
    exit 1
}
Start-Sleep -Seconds 2

# Step 3: Set breakpoints
Write-Host ""
Write-Host "[3/6] Setting breakpoints..." -ForegroundColor Green
$breakpoints = @(
    @{className="com.jdwp.server.controller.UserController"; lineNumber=31},
    @{className="com.jdwp.server.service.UserService"; lineNumber=64}
)

foreach ($bp in $breakpoints) {
    try {
        $bpResponse = Invoke-RestMethod -Uri "$clientApi/breakpoints" -Method Post -Body ($bp | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
        if ($bpResponse.success) {
            Write-Host "  ✓ Breakpoint set: $($bp.className):$($bp.lineNumber)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ✗ Failed to set breakpoint: $($bp.className):$($bp.lineNumber)" -ForegroundColor Red
    }
}
Start-Sleep -Seconds 2

# Step 4: Trigger breakpoint
Write-Host ""
Write-Host "[4/6] Triggering breakpoint (calling API)..." -ForegroundColor Green
$apiJob = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 1
    try {
        Invoke-RestMethod -Uri "http://localhost:8081/api/users" -Method Get -ErrorAction Stop | Out-Null
    } catch {
        # Ignore - we're just triggering the breakpoint
    }
}

# Wait for breakpoint to hit
Write-Host "  Waiting for breakpoint to hit..." -ForegroundColor Yellow
$breakpointHit = $false
$suspendedThread = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $threadsResponse = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -ErrorAction Stop
        $suspendedThread = $threadsResponse.threads | Where-Object { $_.isSuspended -eq $true -and $_.name -like "*http-nio*" } | Select-Object -First 1
        if ($suspendedThread) {
            $breakpointHit = $true
            Write-Host "  ✓✓✓ BREAKPOINT HIT! Thread: $($suspendedThread.name)" -ForegroundColor Green -BackgroundColor Black
            break
        }
    } catch {
        # Continue waiting
    }
}

if (-not $breakpointHit) {
    Write-Host "  ✗ Breakpoint did not hit. Check server logs." -ForegroundColor Red
    Wait-Job $apiJob | Out-Null
    Remove-Job $apiJob
    exit 1
}

$threadName = $suspendedThread.name
$encodedName = [System.Web.HttpUtility]::UrlEncode($threadName)

# Step 5: Test Variables
Write-Host ""
Write-Host "[5/6] Testing Variables..." -ForegroundColor Green
try {
    $varsResponse = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/variables-next-line" -Method Get -ErrorAction Stop
    if ($varsResponse.success) {
        $vars = $varsResponse.variables
        if ($vars -and ($vars.PSObject.Properties.Count -gt 0)) {
            Write-Host "  ✓ Variables found: $($vars.PSObject.Properties.Count)" -ForegroundColor Green
            foreach ($varName in $vars.PSObject.Properties.Name) {
                Write-Host "    - $varName = $($vars.$varName)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  ✗✗✗ NO VARIABLES FOUND!" -ForegroundColor Red
            Write-Host "     Server needs to be rebuilt with debug info!" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ✗ Error getting variables: $_" -ForegroundColor Red
}

# Step 6: Test Step Over vs Continue
Write-Host ""
Write-Host "[6/6] Testing Step Over and Continue..." -ForegroundColor Green

# Get location before step
try {
    $beforeLoc = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/source-location" -Method Get -ErrorAction Stop
    if ($beforeLoc.success) {
        Write-Host "  Current location: $($beforeLoc.location.className):$($beforeLoc.location.lineNumber)" -ForegroundColor White
    }
} catch {}

Write-Host ""
Write-Host "  Testing STEP OVER (should step ONE line)..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/step-over" -Method Post -ErrorAction Stop | Out-Null
    Start-Sleep -Seconds 2
    
    # Check new location
    $afterLoc = Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/source-location" -Method Get -ErrorAction Stop
    if ($afterLoc.success -and $beforeLoc.success) {
        $beforeLine = $beforeLoc.location.lineNumber
        $afterLine = $afterLoc.location.lineNumber
        if ($afterLine -eq ($beforeLine + 1)) {
            Write-Host "  ✓✓✓ STEP OVER WORKING: Stepped from line $beforeLine to $afterLine (ONE line)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ STEP OVER FAILED: Expected line $($beforeLine + 1), got line $afterLine" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ✗ Step Over error: $_" -ForegroundColor Red
}

# Resume thread for continue test
Write-Host ""
Write-Host "  Resuming thread for Continue test..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$clientApi/threads/$encodedName/resume" -Method Post -ErrorAction Stop | Out-Null
    Start-Sleep -Seconds 1
} catch {}

# Wait for next breakpoint
Write-Host "  Waiting for thread to hit next breakpoint..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# Test Continue
Write-Host ""
Write-Host "  Testing CONTINUE (should continue until breakpoint)..." -ForegroundColor Yellow
try {
    $continueResponse = Invoke-RestMethod -Uri "$clientApi/continue" -Method Post -ErrorAction Stop
    Write-Host "  ✓ Continue command executed" -ForegroundColor Green
    Write-Host "  Waiting to see if it continues to next breakpoint..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    
    # Check if we hit the next breakpoint (line 64 in UserService)
    $threadsAfter = Invoke-RestMethod -Uri "$clientApi/threads" -Method Get -ErrorAction Stop
    $suspendedAfter = $threadsAfter.threads | Where-Object { $_.isSuspended -eq $true -and $_.name -like "*http-nio*" } | Select-Object -First 1
    if ($suspendedAfter) {
        $finalLoc = Invoke-RestMethod -Uri "$clientApi/threads/$([System.Web.HttpUtility]::UrlEncode($suspendedAfter.name))/source-location" -Method Get -ErrorAction Stop
        if ($finalLoc.success) {
            $finalLine = $finalLoc.location.lineNumber
            $finalClass = $finalLoc.location.className
            if ($finalClass -like "*UserService*" -and $finalLine -eq 64) {
                Write-Host "  ✓✓✓ CONTINUE WORKING: Continued to breakpoint at $finalClass:$finalLine" -ForegroundColor Green
            } else {
                Write-Host "  ⚠ Continue hit breakpoint at $finalClass:$finalLine (expected UserService:64)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  ⚠ Thread not suspended - may have completed execution" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ Continue error: $_" -ForegroundColor Red
}

Wait-Job $apiJob | Out-Null
Remove-Job $apiJob

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $clientApi = "http://localhost:8082/api/debug"
    $serverApi = "http://localhost:8081/api/users"
    
    # ... connection and setup same as before ...
    Write-Host "1. Connecting..."
    Invoke-RestMethod -Uri "$clientApi/connect?host=localhost&port=5005" -Method Post | Out-Null
    
    Write-Host "2. Setting Breakpoint at LINE 31..."
    Invoke-RestMethod -Uri "$clientApi/breakpoints?className=com.jdwp.server.controller.UserController&lineNumber=31" -Method Post | Out-Null
    
    Write-Host "3. Triggering Request..."
    $job = Start-Job -ScriptBlock { param($url); Invoke-RestMethod -Uri $url -Method Get } -ArgumentList $serverApi
    
    Write-Host "4. Waiting for Breakpoint..."
    $threadName = $null
    for ($i=0; $i -lt 15; $i++) {
        $threads = Invoke-RestMethod -Uri "$clientApi/threads"
        $hit = $threads.threads | Where-Object { $_.isSuspended -and ($_.name -like "*exec*") }
        if ($hit) { $threadName = $hit[0].name; break }
        Start-Sleep -Seconds 1
    }

    if (!$threadName) { throw "Breakpoint not hit" }
    $encName = [Uri]::EscapeDataString($threadName)
    
    Write-Host "5. Evaluating 'a'..."
    $evalA = Invoke-RestMethod -Uri "$clientApi/threads/$encName/evaluate?expression=a" -Method Post
    Write-Host "a = $($evalA.result)"
    
    Write-Host "6. Cleaning up..."
    Invoke-RestMethod -Uri "$clientApi/continue" -Method Post | Out-Null
} catch {
    Write-Error $_
    exit 1
} finally {
    if ($job) { Remove-Job $job -Force }
}

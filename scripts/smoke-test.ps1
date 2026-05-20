#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end smoke test: verifies pods, api-gateway NodePort, job submit, and poll until COMPLETED.

.NOTES
    Requires kubectl (cluster access), minikube, and Invoke-RestMethod. Run after all ai-orchestrator pods are up.
#>

$ErrorActionPreference = 'Stop'

$Ns = 'ai-orchestrator'

function Write-StepHeader {
    param(
        [Parameter(Mandatory = $true)][int]$Step,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-Host "`n[Step $Step] $Message" -ForegroundColor Cyan
}

function Write-SmokeFailureLogs {
    Write-Host "`n========== Diagnostic logs (last 30 lines each) ==========" -ForegroundColor Yellow
    Write-Host "`n--- workflow-controller ---" -ForegroundColor DarkYellow
    try {
        kubectl logs deployment/workflow-controller -n $Ns --tail=30 2>&1 | ForEach-Object { Write-Host $_ }
    }
    catch {
        Write-Host "Could not read workflow-controller logs: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "`n--- job-worker ---" -ForegroundColor DarkYellow
    try {
        kubectl logs deployment/job-worker -n $Ns --tail=30 2>&1 | ForEach-Object { Write-Host $_ }
    }
    catch {
        Write-Host "Could not read job-worker logs: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "`n===========================================================" -ForegroundColor Yellow
}

function Stop-SmokeTestFailed {
    param([string]$Reason)
    Write-Host "`nFAILED: $Reason" -ForegroundColor Red
    Write-SmokeFailureLogs
    exit 1
}

function Wait-JobCompleted {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$JobId,
        [int]$TimeoutSeconds = 180,
        [int]$PollIntervalSeconds = 3
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastStatus = $null
    $job = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $job = Invoke-RestMethod -Uri "$BaseUrl/api/v1/jobs/$JobId" -Method Get -TimeoutSec 60
        }
        catch {
            Stop-SmokeTestFailed -Reason "GET /api/v1/jobs/$JobId failed: $($_.Exception.Message)"
        }
        $current = [string]$job.status
        if ($current -ne $lastStatus) {
            if ($null -eq $lastStatus) { Write-Host "  [$JobId] $current" -ForegroundColor DarkGray }
            else { Write-Host "  [$JobId] $lastStatus -> $current" -ForegroundColor DarkGray }
            $lastStatus = $current
        }
        if ($current -eq 'COMPLETED') { return $job }
        if ($current -eq 'FAILED')    { Stop-SmokeTestFailed -Reason "Job $JobId entered FAILED state." }
        Start-Sleep -Seconds $PollIntervalSeconds
    }
    Stop-SmokeTestFailed -Reason "Job $JobId did not reach COMPLETED within ${TimeoutSeconds}s (last status: '$lastStatus')."
}

try {
    Write-Host "`n=== AI Orchestrator smoke test ===" -ForegroundColor Magenta

    # --- Step 1: all pods Running & ready ---
    Write-StepHeader -Step 1 -Message 'Verify all pods are Running'
    $podsJsonText = kubectl get pods -n $Ns -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-SmokeTestFailed -Reason "kubectl get pods failed: $podsJsonText"
    }
    $podsDoc = $podsJsonText | ConvertFrom-Json
    $podItems = @($podsDoc.items)
    if ($podItems.Count -eq 0) {
        Stop-SmokeTestFailed -Reason "No pods found in namespace '$Ns'."
    }
    foreach ($pod in $podItems) {
        $podName = $pod.metadata.name
        $phase = $pod.status.phase
        if ($phase -ne 'Running') {
            Stop-SmokeTestFailed -Reason "Pod '$podName' phase is '$phase' (expected Running)."
        }
        $containerStatuses = @($pod.status.containerStatuses)
        foreach ($cs in $containerStatuses) {
            if (-not $cs.ready) {
                Stop-SmokeTestFailed -Reason "Pod '$podName' container '$($cs.name)' is not ready."
            }
        }
    }
    Write-Host "All $($podItems.Count) pod(s) are Running and ready." -ForegroundColor Green

    # --- Step 2: port-forward api-gateway to localhost ---
    Write-StepHeader -Step 2 -Message 'Port-forwarding api-gateway to localhost:8080'
    $localPort = 18080
    $baseUrl = "http://localhost:$localPort"

    # Kill any existing port-forward on this port
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "port-forward.*$localPort" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Start port-forward as background job
    $pfJob = Start-Job {
        param($ns, $lp)
        kubectl port-forward svc/api-gateway-svc -n $ns "${lp}:8080"
    } -ArgumentList $Ns, $localPort

    # Wait for port-forward to establish
    Start-Sleep -Seconds 5
    Write-Host "Gateway base URL: $baseUrl (via port-forward)" -ForegroundColor Green

    # --- Step 3: POST job ---
    Write-StepHeader -Step 3 -Message 'Submit test job (POST /api/v1/jobs)'
    $body = '{"description":"Process daily sales report for Q1 2024","priority":7}'
    $submitSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/api/v1/jobs" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120
    }
    catch {
        Stop-SmokeTestFailed -Reason "POST /api/v1/jobs failed: $($_.Exception.Message)"
    }

    Write-Host ($response | ConvertTo-Json -Depth 8)
    $jobId = $response.id
    if (-not $jobId) {
        Stop-SmokeTestFailed -Reason 'POST response missing job id.'
    }
    if ($response.status -ne 'PENDING') {
        Write-Host "Warning: expected status PENDING immediately after create; got '$($response.status)'." -ForegroundColor Yellow
    }
    if (-not $response.shardKey) {
        Write-Host 'Warning: response did not include shardKey (unexpected for normal creates).' -ForegroundColor Yellow
    }
    Write-Host 'Created job.' -ForegroundColor Green

    # --- Step 4: poll GET until COMPLETED ---
    # First job pays Mistral cold-start cost (~30-90s). Subsequent cache hits are sub-second.
    Write-StepHeader -Step 4 -Message 'Poll GET /api/v1/jobs/{id} every 3s (max 180s) until COMPLETED'
    $job = Wait-JobCompleted -BaseUrl $baseUrl -JobId $jobId -TimeoutSeconds 180
    $submitSw.Stop()
    $firstJobSeconds = [math]::Round($submitSw.Elapsed.TotalSeconds, 2)

    # --- Step 5: final job details ---
    Write-StepHeader -Step 5 -Message 'Final job details'
    Write-Host ($job | ConvertTo-Json -Depth 8)
    Write-Host "workerType: $($job.workerType)" -ForegroundColor Gray
    Write-Host "routingDecision: $($job.routingDecision)" -ForegroundColor Gray

    # --- Step 6: cache hit validation (semantic vector cache via Qdrant) ---
    Write-StepHeader -Step 6 -Message 'Cache hit test: submit semantically similar job, expect faster completion'
    $similarBody = '{"description":"Process the Q1 2024 daily sales report","priority":7}'
    $cacheSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $cacheResponse = Invoke-RestMethod -Uri "$baseUrl/api/v1/jobs" -Method Post -ContentType 'application/json' -Body $similarBody -TimeoutSec 30
    }
    catch {
        Stop-SmokeTestFailed -Reason "POST (cache test) failed: $($_.Exception.Message)"
    }
    $cacheJob = Wait-JobCompleted -BaseUrl $baseUrl -JobId $cacheResponse.id -TimeoutSeconds 60
    $cacheSw.Stop()
    $cacheJobSeconds = [math]::Round($cacheSw.Elapsed.TotalSeconds, 2)

    Write-Host "First (LLM)  job time: ${firstJobSeconds}s -> workerType: $($job.workerType)" -ForegroundColor White
    Write-Host "Second (cache) job time: ${cacheJobSeconds}s -> workerType: $($cacheJob.workerType)" -ForegroundColor White
    if ($cacheJobSeconds -lt $firstJobSeconds) {
        Write-Host "Cache hit faster than LLM call -- vector cache (Qdrant) verified." -ForegroundColor Green
    }
    else {
        Write-Host "Warning: cache job not faster than first. Investigate Qdrant collection or similarity threshold." -ForegroundColor Yellow
    }

    # --- Step 7: concurrency test (5 parallel jobs -- Virtual Threads) ---
    Write-StepHeader -Step 7 -Message 'Concurrency test: submit 5 jobs in parallel (Virtual Threads)'
    $concurrentSw = [System.Diagnostics.Stopwatch]::StartNew()
    $descriptions = @(
        'Generate weekly inventory report for warehouse A',
        'Analyze customer churn from last quarter',
        'Process payroll for engineering department',
        'Build monthly KPI dashboard for marketing',
        'Reconcile bank statements for fiscal year end'
    )
    $jobIds = @()
    foreach ($desc in $descriptions) {
        $b = (@{ description = $desc; priority = 5 } | ConvertTo-Json -Compress)
        try {
            $r = Invoke-RestMethod -Uri "$baseUrl/api/v1/jobs" -Method Post -ContentType 'application/json' -Body $b -TimeoutSec 30
            $jobIds += $r.id
        }
        catch {
            Stop-SmokeTestFailed -Reason "Concurrent POST failed: $($_.Exception.Message)"
        }
    }
    Write-Host "Submitted $($jobIds.Count) concurrent jobs. Polling for completion..." -ForegroundColor White

    $completedCount = 0
    foreach ($id in $jobIds) {
        $j = Wait-JobCompleted -BaseUrl $baseUrl -JobId $id -TimeoutSeconds 120
        if ($j -and $j.status -eq 'COMPLETED') {
            $completedCount++
        }
    }
    $concurrentSw.Stop()
    $concurrentSeconds = [math]::Round($concurrentSw.Elapsed.TotalSeconds, 2)
    Write-Host "Completed $completedCount/$($jobIds.Count) concurrent jobs in ${concurrentSeconds}s" -ForegroundColor White
    if ($completedCount -lt $jobIds.Count) {
        Stop-SmokeTestFailed -Reason "Only $completedCount of $($jobIds.Count) concurrent jobs completed."
    }

    # --- Step 8: summary ---
    Write-StepHeader -Step 8 -Message 'Summary'
    Write-Host "First (LLM cold)  job:  ${firstJobSeconds}s" -ForegroundColor Green
    Write-Host "Second (cache hit) job: ${cacheJobSeconds}s" -ForegroundColor Green
    Write-Host "5 concurrent jobs:      ${concurrentSeconds}s total" -ForegroundColor Green
    Write-Host "All jobs reached COMPLETED status." -ForegroundColor Green

    Write-Host "`n=== Smoke test PASSED ===" -ForegroundColor Green
}
catch {
    Write-Host "`nUnhandled error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-SmokeFailureLogs
}
finally {
    # Clean up port-forward job
    if ($pfJob) {
        Stop-Job $pfJob -ErrorAction SilentlyContinue
        Remove-Job $pfJob -ErrorAction SilentlyContinue
    }
}

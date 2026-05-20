#Requires -Version 5.1
<#
.SYNOPSIS
    Full teardown -- deletes namespace (DATA LOSS) and stops Minikube.

.DESCRIPTION
    WARNING: This deletes the ai-orchestrator namespace including ALL PVCs.
    PostgreSQL data, Kafka messages, Qdrant vectors, Ollama model -- all gone.

    For safe shutdown use instead:
      .\scripts\stop.ps1              -- stops Minikube, data preserved
      .\scripts\safe-shutdown.ps1     -- backup + graceful stop
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "WARNING: This will DELETE the ai-orchestrator namespace." -ForegroundColor Red
Write-Host "All PVCs (PostgreSQL, Kafka, Qdrant, Ollama model) will be PERMANENTLY LOST." -ForegroundColor Red
Write-Host ""
Write-Host "For safe shutdown run instead:" -ForegroundColor Yellow
Write-Host "  .\scripts\stop.ps1             -- stops Minikube, data preserved" -ForegroundColor Yellow
Write-Host "  .\scripts\safe-shutdown.ps1    -- backup + graceful stop" -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Type YES to confirm full teardown (data loss)"
if ($confirm -ne 'YES') {
    Write-Host "Teardown cancelled." -ForegroundColor Green
    exit 0
}

Write-Host "`nDeleting namespace 'ai-orchestrator'..." -ForegroundColor Cyan
kubectl delete namespace ai-orchestrator --ignore-not-found=true

Write-Host "Stopping Minikube..." -ForegroundColor Cyan
minikube stop

Write-Host "Teardown complete." -ForegroundColor Green

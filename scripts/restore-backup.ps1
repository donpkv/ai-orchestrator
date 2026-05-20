#Requires -Version 5.1
<#
.SYNOPSIS
    Restores the latest PostgreSQL backup into running pods after start.ps1.

.DESCRIPTION
    Use this only when PVC data is lost (after minikube delete or full teardown).
    Under normal stop/start, PVC data survives and restore is NOT needed.

    Picks the most recent backup folder under backups\postgres\ automatically.
    Run AFTER .\scripts\start.ps1 so pods are already running.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ns         = 'ai-orchestrator'
$backupRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "backups\postgres"

if (-not (Test-Path $backupRoot)) {
    Write-Host "No backups found at $backupRoot" -ForegroundColor Red
    Write-Host "Run .\scripts\safe-shutdown.ps1 before shutting down to create backups." -ForegroundColor Yellow
    exit 1
}

# Pick latest backup folder (sorted by name — timestamp format sorts correctly)
$latestBackup = Get-ChildItem -Path $backupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $latestBackup) {
    Write-Host "No backup folders found inside $backupRoot" -ForegroundColor Red
    exit 1
}

Write-Host "Restoring from backup: $($latestBackup.Name)" -ForegroundColor Cyan

foreach ($shard in @('shard-a', 'shard-b')) {
    $sqlFile = Join-Path $latestBackup.FullName "$shard.sql"
    if (-not (Test-Path $sqlFile)) {
        Write-Host "  No backup file for $shard — skipping." -ForegroundColor Yellow
        continue
    }

    # Get running pod
    $pod = kubectl get pod -n $ns -l "app=postgres-$shard" -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $pod) {
        Write-Host "  postgres-$shard pod not found. Is the cluster running?" -ForegroundColor Red
        continue
    }

    Write-Host "  Restoring $shard from $shard.sql..." -ForegroundColor Gray
    Get-Content $sqlFile | kubectl exec -i $pod -n $ns -- psql -U admin -d orchestrator
    Write-Host "  postgres-$shard restored." -ForegroundColor Green
}

Write-Host "`nRestore complete." -ForegroundColor Green
Write-Host "Note: Qdrant vectors are on PVC — restore from snapshot manually if needed." -ForegroundColor Yellow

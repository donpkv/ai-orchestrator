#Requires -Version 5.1
<#
.SYNOPSIS
    Scales all infra pods to 0 replicas — stops containers but keeps PVCs and data intact.
    Minikube keeps running.

.DESCRIPTION
    Use this when you want to free pod memory inside the cluster without stopping Minikube.
    All PersistentVolumeClaims (PostgreSQL, Kafka, Qdrant, Ollama data) are fully preserved.

    To bring pods back up: .\scripts\deploy-infra.ps1

.NOTES
    Redis has no PVC so its cache is lost — expected and harmless.
    StatefulSets (Kafka) are scaled the same way as Deployments here.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ns = 'ai-orchestrator'

Write-Host "Scaling down all infra pods (data preserved)..." -ForegroundColor Cyan

$deployments = kubectl get deployments -n $ns -o name 2>$null
foreach ($d in $deployments) {
    Write-Host "  Scaling down $d..." -ForegroundColor Gray
    kubectl scale $d -n $ns --replicas=0
}

$statefulsets = kubectl get statefulsets -n $ns -o name 2>$null
foreach ($s in $statefulsets) {
    Write-Host "  Scaling down $s..." -ForegroundColor Gray
    kubectl scale $s -n $ns --replicas=0
}

Write-Host "`nAll pods scaled to 0. PVC data is intact." -ForegroundColor Green
Write-Host "Minikube is still running." -ForegroundColor Yellow
Write-Host "Bring pods back with: .\scripts\deploy-infra.ps1" -ForegroundColor Yellow

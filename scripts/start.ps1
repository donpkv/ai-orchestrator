#Requires -Version 5.1
<#
.SYNOPSIS
    Full startup -- starts Minikube cluster then deploys all infra pods.

.DESCRIPTION
    Single entry point for daily use. Runs setup-cluster.ps1 first (idempotent --
    safe to run even if Minikube is already running), then runs deploy-infra.ps1
    to apply all Kubernetes manifests and wait for pods to be Ready.

    Usage:
        .\scripts\start.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptsDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptsDir

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Local AI Orchestrator -- Full Startup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

# ===========================================================================
# Step 1: Start Minikube cluster
# ===========================================================================
Write-Host "`nStep 1: Starting cluster..." -ForegroundColor Cyan
& "$ScriptsDir\setup-cluster.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cluster setup failed. Fix the error above and re-run." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ===========================================================================
# Step 2: Deploy infrastructure pods
# ===========================================================================
Write-Host "`nStep 2: Deploying infrastructure..." -ForegroundColor Cyan
Set-Location $ProjectRoot
& "$ScriptsDir\deploy-infra.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed. Fix the error above and re-run." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ===========================================================================
Write-Host "`n=======================================" -ForegroundColor Green
Write-Host "  All systems up. Current pod status:" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
kubectl get pods -n ai-orchestrator
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods -n ai-orchestrator"
Write-Host "  kubectl logs <pod-name> -n ai-orchestrator"
Write-Host "  minikube dashboard"
Write-Host "  .\scripts\safe-shutdown.ps1"

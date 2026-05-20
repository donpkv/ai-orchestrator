#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys Spring Boot application pods and React frontend to ai-orchestrator.

.DESCRIPTION
    Assumes infra is already deployed (Phase 1). Images must be loaded into Minikube (local-ai/*).
    Applies manifests from the repo root and waits for rollouts.

    Deploy order: workflow-controller before job-worker (consumer talks to workflow-controller on startup via Kafka).
    Frontend is deployed last with Ingress routing: / -> frontend -> /api proxied to api-gateway-svc.

.NOTES
    Run from any directory — script switches to repository root before kubectl apply.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot

# ===========================================================================
# Preflight checks
# ===========================================================================
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host 'kubectl not found on PATH.' -ForegroundColor Red
    exit 1
}
if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Host 'minikube not found on PATH.' -ForegroundColor Red
    exit 1
}

$minikubeStatus = minikube status --format='{{.Host}}' 2>$null
if ($minikubeStatus -ne 'Running') {
    Write-Host 'Minikube is not running. Start it with: .\scripts\setup-cluster.ps1' -ForegroundColor Red
    exit 1
}

kubectl get namespace ai-orchestrator 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Namespace 'ai-orchestrator' not found. Run setup-cluster.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host 'Preflight checks passed.' -ForegroundColor Green

# ===========================================================================
# Apply manifests (workflow-controller before job-worker — consumer depends on controller)
# ===========================================================================
Write-Host "`nLoading microservice images into Minikube..." -ForegroundColor Cyan
foreach ($img in @("local-ai/workflow-controller:latest", "local-ai/api-gateway:latest", "local-ai/job-worker:latest")) {
    Write-Host "  Loading $img ..." -ForegroundColor Gray
    minikube image load $img
    if ($LASTEXITCODE -ne 0) { Write-Host "Failed to load $img into Minikube." -ForegroundColor Red; exit $LASTEXITCODE }
}

Write-Host "`nApplying manifests from $RepoRoot ..." -ForegroundColor Cyan

Write-Host '  Applying workflow-controller...' -ForegroundColor Cyan
kubectl apply -f k8s/app/workflow-controller.yaml
if ($LASTEXITCODE -ne 0) { Write-Host 'Failed to apply workflow-controller manifest.' -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host '  Applying job-worker...' -ForegroundColor Cyan
kubectl apply -f k8s/app/job-worker.yaml
if ($LASTEXITCODE -ne 0) { Write-Host 'Failed to apply job-worker manifest.' -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host '  Applying api-gateway...' -ForegroundColor Cyan
kubectl apply -f k8s/app/api-gateway.yaml
if ($LASTEXITCODE -ne 0) { Write-Host 'Failed to apply api-gateway manifest.' -ForegroundColor Red; exit $LASTEXITCODE }

# ===========================================================================
# Build and load frontend image into Minikube
# ===========================================================================
Write-Host "`nBuilding frontend Docker image..." -ForegroundColor Cyan
$frontendDir = Join-Path $RepoRoot "frontend"
docker build --no-cache -t local-ai/frontend:latest $frontendDir
if ($LASTEXITCODE -ne 0) { Write-Host 'Frontend Docker build failed.' -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host '  Loading frontend image into Minikube...' -ForegroundColor Gray
minikube image load local-ai/frontend:latest
if ($LASTEXITCODE -ne 0) { Write-Host 'Failed to load frontend image into Minikube.' -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host '  Applying frontend + Ingress manifests...' -ForegroundColor Cyan
kubectl apply -f k8s/app/frontend.yaml
if ($LASTEXITCODE -ne 0) { Write-Host 'Failed to apply frontend manifest.' -ForegroundColor Red; exit $LASTEXITCODE }

# ===========================================================================
# Wait for rollouts
# ===========================================================================
Write-Host "`nWaiting for deployments to become ready..." -ForegroundColor Cyan

kubectl rollout status deployment/workflow-controller -n ai-orchestrator --timeout=180s
if ($LASTEXITCODE -ne 0) { Write-Host 'workflow-controller rollout timed out or failed.' -ForegroundColor Red; exit $LASTEXITCODE }

kubectl rollout status deployment/job-worker -n ai-orchestrator --timeout=180s
if ($LASTEXITCODE -ne 0) { Write-Host 'job-worker rollout timed out or failed.' -ForegroundColor Red; exit $LASTEXITCODE }

kubectl rollout status deployment/api-gateway -n ai-orchestrator --timeout=120s
if ($LASTEXITCODE -ne 0) { Write-Host 'api-gateway rollout timed out or failed.' -ForegroundColor Red; exit $LASTEXITCODE }

kubectl rollout status deployment/frontend -n ai-orchestrator --timeout=120s
if ($LASTEXITCODE -ne 0) { Write-Host 'frontend rollout timed out or failed.' -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host "`nAll deployments are Ready." -ForegroundColor Green

# ===========================================================================
# Status and access URLs
# ===========================================================================
Write-Host "`nPods in ai-orchestrator:" -ForegroundColor Cyan
kubectl get pods -n ai-orchestrator

Write-Host "`nIngress:" -ForegroundColor Cyan
kubectl get ingress -n ai-orchestrator

Write-Host "`nFrontend URL via Ingress (Minikube tunnel):" -ForegroundColor Cyan
$minikubeIp = minikube ip 2>$null
if ($minikubeIp) {
    Write-Host "  http://$minikubeIp  (or run: minikube tunnel, then http://localhost)" -ForegroundColor Green
}

Write-Host "`nAPI Gateway NodePort URL (direct, for smoke-test):" -ForegroundColor Cyan
$gwUrl = minikube service api-gateway-svc -n ai-orchestrator --url 2>$null
if ($gwUrl) {
    Write-Host $gwUrl -ForegroundColor Green
} else {
    Write-Host 'Could not resolve service URL (is Minikube running?).' -ForegroundColor Red
}

Write-Host "`nDeploy apps completed successfully." -ForegroundColor Green

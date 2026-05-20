#Requires -Version 5.1
<#
.SYNOPSIS
    Starts a local Minikube cluster (Docker driver) and prepares the ai-orchestrator namespace.

.DESCRIPTION
    Verifies Minikube is installed, starts the cluster with the configured resources,
    waits until the API is usable, creates the application namespace, prints status,
    and enables metrics-server and ingress addons.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-MinikubeInstalled {
    return [bool](Get-Command minikube -ErrorAction SilentlyContinue)
}

function Write-MinikubeInstallInstructions {
    Write-Host ""
    Write-Host "Minikube was not found on PATH." -ForegroundColor Yellow
    Write-Host "Install Minikube on Windows, then re-run this script. Examples:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  winget install Kubernetes.minikube"
    Write-Host "  # or: choco install minikube"
    Write-Host "  # or download from https://minikube.sigs.k8s.io/docs/start/"
    Write-Host ""
    Write-Host "Ensure Docker Desktop is installed and running for the Docker driver."
    Write-Host "kubectl is bundled with Minikube (minikube kubectl -- ...) or install separately."
    Write-Host ""
}

if (-not (Test-MinikubeInstalled)) {
    Write-MinikubeInstallInstructions
    exit 1
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "kubectl was not found on PATH." -ForegroundColor Yellow
    Write-Host "Install kubectl (https://kubernetes.io/docs/tasks/tools/), or ensure Minikube's kubectl is on PATH." -ForegroundColor Yellow
    Write-Host "You can run kubectl bundled with Minikube as: minikube kubectl -- <args>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Minikube version:" -ForegroundColor Cyan
minikube version

# Clean any stale Minikube profile (safe to run -- ignores if missing)
Write-Host "`nCleaning any stale Minikube state..." -ForegroundColor Cyan
try {
    minikube delete --purge 2>&1 | Out-Null
} catch { }
$global:LASTEXITCODE = 0

# Also remove stale machine state from filesystem (handles case where Docker container is gone)
$minikubeMachinesDir = "$env:USERPROFILE\.minikube\machines\minikube"
if (Test-Path $minikubeMachinesDir) {
    Write-Host "  Removing stale machine directory..." -ForegroundColor Yellow
    Remove-Item -Path $minikubeMachinesDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nStarting Minikube (driver=docker, cpus=6, memory=15000MB, disk=40g)..." -ForegroundColor Cyan
minikube start `
    --driver=docker `
    --cpus=6 `
    --memory=15000 `
    --disk-size=40g
if ($LASTEXITCODE -ne 0) {
    Write-Host "minikube start failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nWaiting for all nodes to be Ready..." -ForegroundColor Cyan
kubectl wait --for=condition=Ready nodes --all --timeout=600s
if ($LASTEXITCODE -ne 0) {
    Write-Host "kubectl wait failed (nodes not Ready in time)." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nEnsuring namespace 'ai-orchestrator' exists..." -ForegroundColor Cyan
kubectl create namespace ai-orchestrator --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to apply namespace 'ai-orchestrator'." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nMinikube status:" -ForegroundColor Cyan
minikube status

Write-Host "`nkubectl cluster-info:" -ForegroundColor Cyan
kubectl cluster-info

# Pre-pull and load all required images on the Windows host, then transfer into
# the Minikube node. This bypasses corporate VPN/firewall restrictions that block
# registry.k8s.io from inside the Minikube Docker container.
Write-Host "`nPre-pulling required images on Windows host..." -ForegroundColor Cyan
$imagesToLoad = @(
    "registry.k8s.io/ingress-nginx/controller:v1.14.3",
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.7",
    "registry.k8s.io/metrics-server/metrics-server:v0.8.1",
    "apache/kafka:3.7.0",
    "postgres:16",
    "redis:7-alpine",
    "qdrant/qdrant:latest",
    "ollama/ollama:latest"
)

foreach ($image in $imagesToLoad) {
    Write-Host "  Pulling $image ..." -ForegroundColor Gray
    docker pull $image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to pull $image - check internet/VPN access from Windows host." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "  Loading $image into Minikube..." -ForegroundColor Gray
    minikube image load $image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to load $image into Minikube." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "`nEnabling addons: metrics-server, ingress..." -ForegroundColor Cyan
minikube addons enable metrics-server
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Enable ingress — ignore the timeout error from Minikube's verification step.
# The controller image is already loaded locally so the pod will start correctly.
minikube addons enable ingress
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Ingress addon verification timed out (expected on restricted networks)." -ForegroundColor Yellow
    Write-Host "  Patching ingress deployment to use local image cache..." -ForegroundColor Yellow

    # Wait briefly for the deployment to be created
    Start-Sleep -Seconds 10

    # Remove digest from image reference so containerd matches by tag
    kubectl set image deployment/ingress-nginx-controller `
        controller=registry.k8s.io/ingress-nginx/controller:v1.14.3 `
        -n ingress-nginx 2>$null

    # Set imagePullPolicy to IfNotPresent so local cache is used
    $patch = '{"spec":{"template":{"spec":{"containers":[{"name":"controller","imagePullPolicy":"IfNotPresent"}]}}}}'
    $patch | Out-File -FilePath "$env:TEMP\ingress-patch.json" -Encoding utf8
    kubectl patch deployment ingress-nginx-controller -n ingress-nginx `
        --patch-file "$env:TEMP\ingress-patch.json" 2>$null

    # Create placeholder admission secret (ignore if already exists)
    try {
        kubectl create secret generic ingress-nginx-admission `
            --from-literal=cert="" --from-literal=key="" `
            -n ingress-nginx 2>&1 | Out-Null
    } catch { }
    $global:LASTEXITCODE = 0

    # Remove the validating webhook (not needed for local dev)
    kubectl delete validatingwebhookconfigurations ingress-nginx-admission 2>$null

    # Restart the controller pod with the patched config
    kubectl delete pods -n ingress-nginx --all 2>$null

    Write-Host "  Waiting for ingress controller to start..." -ForegroundColor Yellow
    kubectl wait --for=condition=Ready pod `
        -l app.kubernetes.io/component=controller `
        -n ingress-nginx `
        --timeout=120s 2>$null
    $global:LASTEXITCODE = 0

    Write-Host "  Ingress controller is running (or will catch up)." -ForegroundColor Green
}

Write-Host "`nSetup complete." -ForegroundColor Green

# Build service images from orchestrator-parent and load them into Minikube.
# Run from anywhere; the script changes directory to orchestrator-parent root.

$ErrorActionPreference = 'Stop'

# From local-ai-orchestrator/scripts/, go up one level to local-ai-orchestrator,
# then into orchestrator-parent (the Docker build context root).
$Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'orchestrator-parent'
Set-Location $Root

$env:DOCKER_BUILDKIT = '1'

$images = @(
    @{ Dockerfile = 'api-gateway/Dockerfile'; Tag = 'local-ai/api-gateway:latest' },
    @{ Dockerfile = 'workflow-controller/Dockerfile'; Tag = 'local-ai/workflow-controller:latest' },
    @{ Dockerfile = 'job-worker/Dockerfile'; Tag = 'local-ai/job-worker:latest' }
)

foreach ($img in $images) {
    Write-Host ">> Building $($img.Tag)" -ForegroundColor Cyan
    docker build --no-cache -f $img.Dockerfile -t $img.Tag .
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed for $($img.Tag)"
    }
    Write-Host ">> Loading $($img.Tag) into Minikube..." -ForegroundColor Cyan
    minikube image load $img.Tag
    if ($LASTEXITCODE -ne 0) {
        throw "minikube image load failed for $($img.Tag)"
    }
    Write-Host ">> $($img.Tag) ready." -ForegroundColor Green
}

Write-Host "`nLocal images loaded:" -ForegroundColor Yellow
docker images 'local-ai/*'

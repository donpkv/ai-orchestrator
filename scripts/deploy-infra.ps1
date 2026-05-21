#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys all infrastructure pods to the ai-orchestrator namespace in order.

.DESCRIPTION
    Pre-pulls every required image on the Windows host and loads it into Minikube
    BEFORE applying any manifest. This bypasses corporate VPN/firewall restrictions.

    Safe to re-run -- kubectl apply is idempotent (already-running pods are unchanged).

    Phases:
      1.2  PostgreSQL 16       postgres:16
      1.3  Redis 7             redis:7-alpine
      1.4  Kafka 3.7.0         apache/kafka:3.7.0
      1.5  Qdrant              qdrant/qdrant:latest
      1.6  Ollama              ollama/ollama:latest    -- uncomment after subtask 1.6
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===========================================================================
# Preflight checks
# ===========================================================================
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "kubectl not found on PATH. Run setup-cluster.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Host "minikube not found on PATH. Run setup-cluster.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "docker not found on PATH. Ensure Docker Desktop is running." -ForegroundColor Red
    exit 1
}

$minikubeStatus = minikube status --format='{{.Host}}' 2>$null
if ($minikubeStatus -ne 'Running') {
    Write-Host "Minikube is not running. Start it with: .\scripts\setup-cluster.ps1" -ForegroundColor Red
    exit 1
}

kubectl get namespace ai-orchestrator 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Namespace 'ai-orchestrator' not found. Run setup-cluster.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Preflight checks passed." -ForegroundColor Green

# ===========================================================================
# Helper: pull image on Windows host + load into Minikube
# ===========================================================================
function Load-Image {
    param([string]$Image)
    Write-Host "  Pulling $Image on Windows host..." -ForegroundColor Gray
    docker pull $Image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to pull $Image - check internet/VPN on Windows host." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "  Loading $Image into Minikube..." -ForegroundColor Gray
    minikube image load $Image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to load $Image into Minikube." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "  $Image ready in Minikube." -ForegroundColor Green
}

# ===========================================================================
# Helper: wait for pods by label
# ===========================================================================
function Wait-Pods {
    param(
        [string]$Label,
        [string]$Namespace = 'ai-orchestrator',
        [int]$TimeoutSeconds = 120
    )
    Write-Host "  Waiting for pods with label '$Label'..." -ForegroundColor Gray
    kubectl wait --for=condition=Ready pod `
        -l $Label `
        -n $Namespace `
        --timeout="${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Pod did not become Ready in time. Run: kubectl get pods -n $Namespace" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ===========================================================================
# 1.2  PostgreSQL Shards
# ===========================================================================
Write-Host "`n[1.2] PostgreSQL Shards - pre-pulling image..." -ForegroundColor Cyan
Load-Image "postgres:16"
kubectl apply -f k8s/infra/postgres/postgres-shard-a.yaml
kubectl apply -f k8s/infra/postgres/postgres-shard-b.yaml
Wait-Pods -Label "app=postgres-shard-a"
Wait-Pods -Label "app=postgres-shard-b"
Write-Host "  PostgreSQL shards are Ready." -ForegroundColor Green

# Create jobs table on both shards
$createTableSql = @"
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY,
    description TEXT,
    priority INTEGER,
    status VARCHAR(50),
    shard_key INTEGER,
    worker_type VARCHAR(100),
    routing_decision TEXT,
    submitted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
"@
Write-Host "  Creating 'jobs' table on shard-a..." -ForegroundColor Gray
$shardAPod = kubectl get pod -n ai-orchestrator -l app=postgres-shard-a -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n ai-orchestrator $shardAPod -- psql -U admin -d orchestrator -c $createTableSql | Out-Null
Write-Host "  Creating 'jobs' table on shard-b..." -ForegroundColor Gray
$shardBPod = kubectl get pod -n ai-orchestrator -l app=postgres-shard-b -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n ai-orchestrator $shardBPod -- psql -U admin -d orchestrator -c $createTableSql | Out-Null
Write-Host "  Schema created on both shards." -ForegroundColor Green

# ===========================================================================
# 1.3  Redis
# ===========================================================================
Write-Host "`n[1.3] Redis - pre-pulling image..." -ForegroundColor Cyan
Load-Image "redis:7-alpine"
kubectl apply -f k8s/infra/redis/redis.yaml
Wait-Pods -Label "app=redis"
Write-Host "  Redis is Ready." -ForegroundColor Green

# ===========================================================================
# 1.4  Kafka (KRaft - no Zookeeper)
# ===========================================================================
Write-Host "`n[1.4] Kafka - pre-pulling image..." -ForegroundColor Cyan
Load-Image "apache/kafka:3.7.0"
kubectl apply -f k8s/infra/kafka/kafka.yaml
Wait-Pods -Label "app=kafka" -TimeoutSeconds 180
kubectl apply -f k8s/infra/kafka/create-topics.yaml
Write-Host "  Kafka is Ready." -ForegroundColor Green

# ===========================================================================
# 1.5  Qdrant (Vector DB)
# ===========================================================================
Write-Host "`n[1.5] Qdrant - pre-pulling image..." -ForegroundColor Cyan
Load-Image "qdrant/qdrant:latest"
kubectl apply -f k8s/infra/qdrant/qdrant.yaml
Wait-Pods -Label "app=qdrant" -TimeoutSeconds 120
Write-Host "  Qdrant is Ready." -ForegroundColor Green

# ===========================================================================
# 1.6  Ollama (Local LLM runtime)
# ===========================================================================
Write-Host "`n[1.6] Ollama - pre-pulling image..." -ForegroundColor Cyan
Load-Image "ollama/ollama:latest"
kubectl apply -f k8s/infra/ollama/ollama.yaml
Wait-Pods -Label "app=ollama" -TimeoutSeconds 300
Write-Host "  Ollama is Ready." -ForegroundColor Green

# Check and pull required Ollama models
$ollamaPod = kubectl get pod -n ai-orchestrator -l app=ollama -o jsonpath='{.items[0].metadata.name}' 2>$null
$modelList = kubectl exec -n ai-orchestrator $ollamaPod -- ollama list 2>$null

# --- mistral:7b ---
Write-Host "  Checking if mistral:7b is loaded..." -ForegroundColor Gray
if ($modelList -match "mistral") {
    Write-Host "  mistral:7b is loaded and ready." -ForegroundColor Green
} else {
    Write-Host "  mistral:7b not found on PVC. Copying from Windows Ollama cache..." -ForegroundColor Yellow
    $ollamaModelsPath = "$env:USERPROFILE\.ollama\models"
    if (Test-Path $ollamaModelsPath) {
        Write-Host "  Copying model files to pod (this takes 2-5 minutes)..." -ForegroundColor Gray
        Set-Location $ollamaModelsPath\..
        kubectl cp .\models "${ollamaPod}:/root/.ollama/models" -n ai-orchestrator
        kubectl exec -n ai-orchestrator $ollamaPod -- sh -c "[ -d /root/.ollama/models/models ] && mv /root/.ollama/models/models/* /root/.ollama/models/ && rmdir /root/.ollama/models/models || true" 2>$null
        $modelList2 = kubectl exec -n ai-orchestrator $ollamaPod -- ollama list 2>$null
        if ($modelList2 -match "mistral") {
            Write-Host "  mistral:7b copied and ready." -ForegroundColor Green
        } else {
            Write-Host "  Copy done but model not detected. Run manually: kubectl exec -n ai-orchestrator $ollamaPod -- ollama list" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Windows Ollama cache not found at $ollamaModelsPath" -ForegroundColor Red
        Write-Host "  Run: ollama pull mistral:7b  then re-run deploy-infra.ps1" -ForegroundColor Yellow
    }
}

# --- nomic-embed-text (required for Qdrant vector embeddings) ---
Write-Host "  Checking if nomic-embed-text is loaded..." -ForegroundColor Gray
$modelList3 = kubectl exec -n ai-orchestrator $ollamaPod -- ollama list 2>$null
if ($modelList3 -match "nomic-embed-text") {
    Write-Host "  nomic-embed-text is loaded and ready." -ForegroundColor Green
} else {
    Write-Host "  nomic-embed-text not found. Copying from Windows Ollama cache..." -ForegroundColor Yellow
    Write-Host "  (Direct pull blocked by corporate TLS inspection — pull on Windows host first)" -ForegroundColor Gray
    $ollamaModelsPath = "$env:USERPROFILE\.ollama\models"
    if (Test-Path $ollamaModelsPath) {
        Set-Location "$env:USERPROFILE\.ollama"
        kubectl cp .\models "${ollamaPod}:/root/.ollama/models" -n ai-orchestrator
        $modelList4 = kubectl exec -n ai-orchestrator $ollamaPod -- ollama list 2>$null
        if ($modelList4 -match "nomic-embed-text") {
            Write-Host "  nomic-embed-text copied and ready." -ForegroundColor Green
        } else {
            Write-Host "  Copy done but model not detected. Run manually on Windows host:" -ForegroundColor Yellow
            Write-Host "    ollama pull nomic-embed-text" -ForegroundColor Yellow
            Write-Host "  Then re-run this script." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Windows Ollama cache not found. Run on Windows host first:" -ForegroundColor Red
        Write-Host "    ollama pull nomic-embed-text" -ForegroundColor Yellow
        Write-Host "  Then re-run this script." -ForegroundColor Yellow
    }
}

# ===========================================================================
Write-Host "`nAll infrastructure deployed and Ready." -ForegroundColor Green
kubectl get pods -n ai-orchestrator
Write-Host 'Next: run scripts/deploy-apps.ps1 to deploy Spring Boot application pods.' -ForegroundColor Yellow

#Requires -Version 5.1
<#
.SYNOPSIS
    Pauses Minikube -- all pods stop but ALL DATA on PVCs is preserved.

.DESCRIPTION
    Runs minikube stop. Safe daily shutdown command.
    All PVC data (PostgreSQL, Kafka, Qdrant, Ollama model) survives.
    Redis cache is lost -- expected, it rebuilds from PostgreSQL on next start.

    To resume: .\scripts\start.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Stopping Minikube (data preserved)..." -ForegroundColor Cyan
minikube stop

Write-Host "Minikube stopped. All PVC data is safe." -ForegroundColor Green
Write-Host "Resume anytime with: .\scripts\start.ps1" -ForegroundColor Yellow

# Phase 4: End-to-end smoke test

This document describes the automated smoke test in `scripts/smoke-test.ps1`, which you run after Kubernetes pods in `ai-orchestrator` are up (typically via `scripts/deploy-apps.ps1` and stable rollouts).

## What the smoke test validates

The script exercises the **full pipeline** that a single job follows in this stack:

1. **HTTP** — POST creates a job through **api-gateway**, which forwards to **workflow-controller** (database persistence, shard assignment).
2. **Kafka** — Job events flow between components (routing and completion paths depend on messaging).
3. **Ollama** — **job-worker** asks the local LLM for a **worker type / routing decision** when cache misses occur (embedding + similarity against past routes).
4. **Qdrant** — Embeddings and routing payloads are stored or matched for similarity-based reuse.
5. **PostgreSQL (sharded)** — Job rows are updated through **workflow-controller** as status moves **PENDING → ROUTED → COMPLETED**.

Passing the script means the cluster wiring (services, ConfigMaps, DB/Kafka/Qdrant/Ollama endpoints) is coherent enough for one realistic job to complete end-to-end.

## Expected timing

These are rough local Minikube timings; hardware and cold caches change them:

| Phase | Typical duration |
|--------|------------------|
| **PENDING → ROUTED** | About **5–10 seconds**, dominated by embedding + LLM inference and similarity work |
| **ROUTED → COMPLETED** | Often about **2 seconds** more as the worker patches routing then marks completion |

The script polls **every 3 seconds** for up to **60 seconds**, so transient slowdowns usually still pass.

## Running the smoke test

From the repository root (with `kubectl` pointed at your cluster and Minikube driving the NodePort):

```powershell
.\scripts\smoke-test.ps1
```

Prerequisites:

- Namespace `ai-orchestrator` exists and pods are **Running** and **Ready**.
- `minikube` can resolve `api-gateway-svc` URL on your machine.

## How to read logs when something fails

On **any failure**, `smoke-test.ps1` prints the **last 30 lines** of:

- `deployment/workflow-controller`
- `deployment/job-worker`

For deeper investigation, tail logs manually:

```powershell
kubectl logs deployment/workflow-controller -n ai-orchestrator -f
kubectl logs deployment/job-worker -n ai-orchestrator -f
kubectl logs deployment/api-gateway -n ai-orchestrator -f
```

Correlate timestamps with the failing step (pod verification, POST submit, polling timeouts).

## Common failure modes and fixes

### Pods not Ready / not Running

**Symptoms:** Step 1 fails, or intermittent connection errors during HTTP calls.

**Checks:**

```powershell
kubectl get pods -n ai-orchestrator
kubectl describe pod <pod-name> -n ai-orchestrator
```

**Fixes:**

- Ensure infra (Kafka, Postgres shards, Redis, Qdrant, Ollama) is healthy before app pods.
- Redeploy apps in order (`workflow-controller` before `job-worker`) per `scripts/deploy-apps.ps1`.
- Inspect image pull errors and resource limits (`kubectl describe pod`).

### Kafka not connected

**Symptoms:** Jobs stuck PENDING or ROUTED; worker/controller logs show consumer/producer errors or timeouts.

**Fixes:**

- Confirm Kafka Service DNS and ports match app ConfigMaps.
- Verify Zookeeper/Kafka pods are Running and brokers reachable from app pods.

### Ollama model not loaded / inference errors

**Symptoms:** Long stalls before ROUTED, HTTP errors from worker toward Ollama, or explicit model-not-found messages in **job-worker** logs.

**Fixes:**

- Ensure the Ollama Deployment is Running and the expected model is pulled inside the cluster (`kubectl exec` into Ollama if needed).
- Align model name env vars with what Phase 1/3 docs prescribe.

### Qdrant unreachable or schema mismatch

**Symptoms:** Errors mentioning Qdrant in **job-worker** or **workflow-controller** logs; routing never completes.

**Fixes:**

- Confirm Qdrant pod/service URL and collection setup match deployment docs.
- Check network policies (if any) and DNS inside the cluster.

### Database / Redis connectivity

**Symptoms:** POST fails or workflow-controller CrashLoop with JDBC/connection errors.

**Fixes:**

- Verify Postgres shard Services and credentials in ConfigMaps vs manifest secrets.
- Confirm Redis host/port for caching layers.

---

After fixing the underlying issue, rerun `.\scripts\smoke-test.ps1` to confirm the full path **HTTP → Kafka → Ollama → Qdrant → DB** succeeds again.

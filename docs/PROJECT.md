# Local AI Orchestrator — Project Documentation

## Overview

A Kubernetes-native **Intelligent Workflow Orchestrator** running entirely on a local machine.
Users submit natural-language job descriptions. The system uses a local LLM (Ollama + Mistral 7B)
to decompose each job into sub-tasks and route them to worker pods. A Vector DB (Qdrant) stores
job embeddings so similar past jobs are reused for routing instead of calling the LLM every time.

This is a learning project built one subtask at a time — each phase introduces one new concept,
tested and understood before proceeding.

---

## Project Scope

### What the system does

1. User submits a job: `POST /api/v1/jobs` with a natural-language description
2. Spring Boot embeds the description and queries Qdrant for similar past jobs
3. If similarity > 0.9 — reuse previous routing decision (skip LLM call)
4. If no match — call Ollama (Mistral 7B) to decompose into sub-tasks
5. Kafka publishes each sub-task to worker pods
6. Workers execute and update job status in PostgreSQL
7. Results cached in Redis, visible in React dashboard

### Architecture

```
React Frontend
  → API Gateway (Spring Cloud Gateway)
  → Workflow Controller (Spring Boot)
       → Redis (cache)
       → Qdrant (vector DB — semantic job matching)
       → Ollama (local LLM — task decomposition)
       → Kafka (event bus)
       → PostgreSQL Shard A + Shard B
  ← Job Worker Pods (Kafka consumers)
```

All components run as Kubernetes pods inside a Minikube cluster on the developer's local machine.

---

## Technology Stack

### Infrastructure
| Tool | Version | Purpose |
|---|---|---|
| Minikube | v1.38.1 | Local single-node Kubernetes cluster |
| Docker Desktop | v4.73.1 | Container engine (Minikube driver) |
| kubectl | v1.34.1 | Kubernetes CLI |
| WSL 2 | Latest | Linux kernel for Docker on Windows |

### Application
| Technology | Version | Purpose |
|---|---|---|
| Java | 21 | Spring Boot runtime (Virtual Threads) |
| Spring Boot | 3.x | Workflow controller + API Gateway + Workers |
| Spring WebFlux | 3.x | Reactive non-blocking HTTP |
| Spring Kafka | 3.x | Kafka producer/consumer |
| Spring Cache + Redis | 3.x | Job status caching |
| Spring Data JPA | 3.x | Database access with sharding |
| Flyway | Latest | Database migrations |
| Maven | Multi-module | Build system |

### Data + Messaging
| Component | Version | Purpose |
|---|---|---|
| PostgreSQL | 16 | Persistent job storage (2 shards) |
| Redis | 7 | Job status cache, rate limiting |
| Apache Kafka | 3.7 (KRaft) | Event bus between controller and workers |
| Qdrant | Latest | Vector DB for job embeddings |

### AI
| Component | Purpose |
|---|---|
| Ollama | Local LLM runtime |
| Mistral 7B | Model for task decomposition and routing |
| nomic-embed-text | Embedding model (384-dim vectors) |

### Frontend (Phase 5)
| Technology | Purpose |
|---|---|
| React 18 + TypeScript | UI framework |
| Vite | Build tool |
| Tailwind CSS | Styling |

### Observability (Phase 6)
| Technology | Purpose |
|---|---|
| Istio | Service mesh, mTLS, traffic management |
| OpenTelemetry | Distributed tracing (Trace ID across all pods) |
| Jaeger | Trace collector and UI |
| Prometheus + Grafana | Metrics and dashboards |
| Fluent Bit + Loki | Centralized log collection |

---

## Machine Requirements

| Resource | Minimum | Recommended (this machine) |
|---|---|---|
| RAM | 16 GB | 32 GB — 16 GB allocated to Minikube |
| CPU | 4 cores | 8 cores — 6 allocated to Minikube |
| Disk | 40 GB free | 84 GB free on C: |
| OS | Windows 10 | Windows 11 Enterprise |

### WSL 2 Configuration (`C:\Users\piyushvi\.wslconfig`)
```ini
[wsl2]
memory=20GB
processors=6
swap=4GB
```

---

## Project Folder Structure

```
local-ai-orchestrator/
├── docs/                          # Project documentation
│   ├── PROJECT.md                 # This file — full project reference
│   └── phase1-setup.md            # Phase 1 Minikube setup guide
├── k8s/                           # Kubernetes manifests (created in phases 1.2–1.6)
│   ├── infra/
│   │   ├── postgres/              # PostgreSQL shard-a and shard-b
│   │   ├── redis/                 # Redis deployment
│   │   ├── kafka/                 # Kafka KRaft deployment
│   │   ├── qdrant/                # Qdrant vector DB
│   │   └── ollama/                # Ollama LLM runtime
│   └── app/                       # Spring Boot app deployments
│       ├── gateway.yaml
│       ├── workflow-controller.yaml
│       └── job-worker.yaml
├── orchestrator-parent/           # Maven multi-module Java project (Phase 2)
│   ├── pom.xml
│   ├── common/                    # Shared DTOs and utilities
│   ├── api-gateway/               # Spring Cloud Gateway
│   ├── workflow-controller/       # Core orchestration engine
│   └── job-worker/                # Kafka consumer + job executor
├── frontend/                      # React dashboard (Phase 5)
├── scripts/                       # Automation scripts
│   ├── setup-cluster.ps1          # Start Minikube + configure everything
│   ├── teardown-cluster.ps1       # Stop Minikube + clean up
│   ├── run-subtask.ts             # Cursor SDK agent runner
│   ├── list-agents.ts             # Show all subtask statuses
│   └── resume-agent.ts            # Resume a previous agent by ID
├── subtasks.json                  # Subtask registry (id, prompt, status, agentId)
├── package.json                   # Node.js dependencies for orchestrator scripts
├── tsconfig.json                  # TypeScript config
├── .env                           # Local secrets (never committed)
├── .env.example                   # Template for .env
└── .gitignore                     # Excludes node_modules, .env, target/, dist/
```

---

## The Two-Layer Execution Model

This project uses a unique control architecture: a **planning chat** (this document's context) never
writes code. All code generation happens via a TypeScript orchestrator script that spawns isolated
Cursor AI agents.

```
Planning Chat (control node)
  → defines subtask prompts in subtasks.json
  → reviews output, explains concepts, approves next step
  → NEVER runs code

Terminal (PowerShell)
  → npx ts-node scripts/run-subtask.ts 1.2
  → reads prompt from subtasks.json
  → Cursor SDK: Agent.create() + agent.send()
  → Cursor Agent executes on local machine
  → writes files to local-ai-orchestrator/
  → streams output to terminal
  → saves agentId to subtasks.json on completion
```

### How to run a subtask
```powershell
cd c:\Users\piyushvi\Downloads\project\local-ai-orchestrator
npx ts-node scripts/run-subtask.ts 1.2
```

### How to check all subtask statuses
```powershell
npx ts-node scripts/list-agents.ts
```

### How to resume a previous agent for follow-up
```powershell
npx ts-node scripts/resume-agent.ts agent-b28bcecd-65e2-4f69-affb-cad0aefc7e31
```

---

## Phase Progress

### Phase 0 — Cursor SDK Orchestrator (COMPLETE)

Built the meta-layer that connects the planning chat to all execution agents.

**Files created:**
- `scripts/run-subtask.ts` — main SDK runner
- `scripts/list-agents.ts` — subtask registry viewer
- `scripts/resume-agent.ts` — agent resume utility
- `subtasks.json` — 13 subtasks registered, all prompts defined for Phase 1
- `package.json` — dependencies: `@cursor/sdk`, `dotenv`, `typescript`, `ts-node`
- `tsconfig.json` — TypeScript config with Node types
- `.env.example` — API key template
- `.gitignore` — excludes secrets and build artifacts

**Issues resolved:**
- `tsconfig.json` missing `"node"` in types — added `"types": ["node"]` and `"dom"` to lib
- `dotenv` missing from `package.json` — added and ran `npm install`
- `await using` syntax incompatible with TypeScript target — replaced with `const agent = await Agent.create()` + `try/finally` dispose pattern

---

### Phase 1.1 — Minikube + Docker Setup (COMPLETE)

Set up the local Kubernetes cluster on Windows with Docker Desktop as the driver.

**Files created:**
- `scripts/setup-cluster.ps1` — full cluster setup with VPN-aware image loading
- `scripts/teardown-cluster.ps1` — clean shutdown
- `docs/phase1-setup.md` — Minikube and namespace explanation

**Cluster configuration:**
```powershell
minikube start --driver=docker --cpus=6 --memory=16384 --disk-size=40g
```

**Running components:**
| Component | Status | Namespace |
|---|---|---|
| Minikube node | Ready | — |
| ai-orchestrator namespace | Created | ai-orchestrator |
| metrics-server | Running | kube-system |
| ingress-nginx controller | 1/1 Running | ingress-nginx |

**Issues resolved during Phase 1.1:**

| Issue | Root Cause | Fix |
|---|---|---|
| Docker Engine stopped after WSL shutdown | `wsl --shutdown` killed Docker | Restarted Docker Desktop |
| `DOCKER_HOST` pointing to TCP port 2375 | Old environment variable override | Cleared `DOCKER_HOST`, ran `docker context use desktop-linux` |
| Minikube memory limit 7942MB | WSL 2 default memory cap | Created `~/.wslconfig` with `memory=20GB` |
| `ImagePullBackOff` on ingress pods | Corporate VPN blocks `registry.k8s.io` inside containers | Pre-pulled on Windows host, loaded with `minikube image load` |
| Images loaded but pods still failing | `imagePullPolicy: Always` contacts registry to verify digest | Patched to `imagePullPolicy: IfNotPresent` via `kubectl patch` |
| `ContainerCreating` stuck | Secret `ingress-nginx-admission` missing (admission Jobs deleted) | Created placeholder secret manually |
| Duplicate `-ForegroundColor` parameter in script | Code bug in generated script | Fixed line 59 of `setup-cluster.ps1` |
| `kubectl patch` JSON error in PowerShell | PowerShell mangles single-quoted JSON | Used `Out-File` temp file + `--patch-file` flag |
| Pod reverted to old ReplicaSet | Image referenced by digest not matching local tag | Used `kubectl set image` to remove digest, reference by tag only |

**VPN fix baked into `setup-cluster.ps1`:**
The script pre-pulls all images on the Windows host before enabling addons or applying manifests.
Images pre-loaded: `ingress-nginx/controller`, `kube-webhook-certgen`, `metrics-server`,
`bitnami/kafka:3.7`, `postgres:16`, `redis:7-alpine`.
As new components are added (Qdrant, Ollama), their images are added to this list.
A full `minikube delete` + `.\scripts\setup-cluster.ps1` is self-contained on corporate VPN.

---

### Phase 1.2 — PostgreSQL Sharded Deployment (COMPLETE)
Files: `k8s/infra/postgres/postgres-shard-a.yaml`, `postgres-shard-b.yaml`, `init-jobs-table.sql`
Both shards running at `postgres-shard-a-svc:5432` and `postgres-shard-b-svc:5432`.

### Phase 1.3 — Redis Deployment (COMPLETE)
Files: `k8s/infra/redis/redis.yaml`
Redis running at `redis-svc:6379`, capped at 256MB, persistence disabled (cache only).

### Phase 1.4 — Kafka Deployment KRaft mode (COMPLETE)
Files: `k8s/infra/kafka/kafka.yaml`, `create-topics.yaml`
Kafka StatefulSet running at `kafka-svc:9092`. Topics: `job-submitted`, `job-routed`, `job-completed` (3 partitions each).

### Phase 1.5 — Qdrant Vector DB Deployment (COMPLETE)
Files: `k8s/infra/qdrant/qdrant.yaml`, `create-collection.sh`
Qdrant running at `qdrant-svc:6333` (REST) and `:6334` (gRPC), 2Gi PVC. Collection `job-embeddings` (384-dim, Cosine) created after port-forward.

### Phase 1.6 — Ollama Deployment (COMPLETE)
Files: `k8s/infra/ollama/ollama.yaml`, `pull-model.sh`
Ollama running at `ollama-svc:11434`, 10Gi PVC at `/root/.ollama`. `mistral:7b` (4.4GB) loaded and tested — responds to prompts. Model stored on PVC, survives pod restarts.

**Phase 1 Infrastructure — FULLY COMPLETE**

```
namespace: ai-orchestrator
├── postgres-shard-a   1/1 Running  (postgres:16,        1Gi PVC)
├── postgres-shard-b   1/1 Running  (postgres:16,        1Gi PVC)
├── redis              1/1 Running  (redis:7-alpine,     no PVC — cache only)
├── kafka-0            1/1 Running  (apache/kafka:3.7.0, 2Gi PVC)
├── qdrant             1/1 Running  (qdrant/qdrant,      2Gi PVC)
└── ollama             1/1 Running  (ollama/ollama,      10Gi PVC + mistral:7b)
```
### Phase 2.1 — Maven Multi-Module Scaffold (COMPLETE)
Files: `orchestrator-parent/pom.xml`, `common/`, `api-gateway/`, `workflow-controller/`, `job-worker/`
Parent POM with Java 21 + Spring Boot 3.2.5 BOM. All 4 modules scaffolded with pom.xml, main classes, application.yml. DTOs: `JobRequest` (validated record), `JobResponse` (immutable record).

### Phase 2.2 — Workflow Controller Job Submission API (COMPLETE)
Files: `model/Job.java`, `repository/JobRepository.java`, `service/JobService.java`, `web/JobController.java`, `config/JpaConfig.java`
REST endpoints: POST /api/v1/jobs (201), GET /api/v1/jobs/{id} (200), GET /api/v1/jobs (200). Shard routing: hash(UUID) % 2. JPA entity with @PrePersist lifecycle hooks.
### Phase 2.3 — Database Sharding Configuration (COMPLETE)
Files: `config/ShardContextHolder.java`, `config/ShardRoutingDataSource.java`, updated `JpaConfig.java`, updated `JobService.java`
AbstractRoutingDataSource routes each DB call to shard-a or shard-b via ThreadLocal context. getAllJobs() queries both shards and merges results. try/finally guarantees ThreadLocal is always cleared.
### Phase 2.4 — Redis Caching Layer (COMPLETE)
Files: `config/CacheConfig.java`, updated `service/JobService.java`, updated `JobServicePort.java`, updated `JobController.java`, `web/JobStatusUpdateRequest.java`, `docs/phase2-caching.md`
Cache-aside pattern: Redis checked before every `getJob()` call, populated on miss and after every `submitJob()`. TTL = 5 minutes. Redis errors are silently swallowed — PostgreSQL remains authoritative. New endpoint: `PATCH /api/v1/jobs/{id}/status` for status updates that sync both DB and cache atomically.
### Phase 2.5 — Kafka Integration (COMPLETE)
Files: `controller/config/KafkaProducerConfig.java`, `controller/messaging/JobEventPublisher.java`, updated `JobService.java`, `worker/config/KafkaConsumerConfig.java`, `worker/config/RestTemplateConfig.java`, `worker/messaging/JobEventConsumer.java`, `docs/phase2-kafka.md`
Producer in `workflow-controller` publishes JSON to `job-submitted` topic after every `submitJob()` — fire-and-forget (Kafka failure never breaks the HTTP response). Consumer in `job-worker` listens to `job-submitted`, simulates 2s processing, then calls `PATCH /api/v1/jobs/{id}/status` to mark job `COMPLETED`. Full async pipeline: HTTP request returns in ~25ms, job executes asynchronously.
### Phase 2.6 — Java 21 Virtual Threads (COMPLETE)
Files: `controller/config/ThreadConfig.java`, `worker/config/ThreadConfig.java`, updated `application.yml` in both modules
`TomcatProtocolHandlerCustomizer` replaces Tomcat's fixed thread pool with `Executors.newVirtualThreadPerTaskExecutor()` in `workflow-controller`. `spring.threads.virtual.enabled: true` added to both modules. Each HTTP request and each Kafka listener callback now runs on a dedicated virtual thread — I/O waits (DB, Redis, Kafka) suspend the virtual thread without holding an OS thread.
### Phase 3.1 — Qdrant Client Integration (COMPLETE)
Files: `config/QdrantConfig.java`, `ai/EmbeddingService.java`, `ai/QdrantService.java`, `docs/phase3-qdrant-integration.md`
REST-based Qdrant client (port 6333, no gRPC dependency conflicts). `EmbeddingService` calls Ollama `nomic-embed-text` to embed job descriptions into 384-dim float vectors. `QdrantService` searches for similar past jobs (threshold 0.9) and stores new embeddings. Build fix: replaced `io.qdrant:qdrant-client` (wrong artifactId, gRPC conflicts) with plain RestTemplate calling Qdrant REST API.
### Phase 3.2 — Ollama LLM Routing Service (COMPLETE)
Files: `ai/OllamaService.java`, `ai/RoutingDecision.java`, `config/OllamaRestTemplateConfig.java`, updated `Job.java`, updated `JobService.java`, updated `JobResponse.java`, updated `init-jobs-table.sql`, `docs/phase3-ollama-routing.md`
Calls Mistral 7B via `POST /api/generate` with a structured JSON-only prompt. Extracts JSON from model output using `indexOf('{')` + `lastIndexOf('}')`. Dedicated `ollamaRestTemplate` bean with 30s read timeout. `defaultDecision()` fallback ensures job submission never fails due to LLM unavailability. Build fix: replaced `RestTemplateBuilder.connectTimeout(Duration)` (removed in Spring Boot 3.2) with `SimpleClientHttpRequestFactory.setConnectTimeout(int)`.
### Phase 3.3 — End-to-End AI Routing Flow (COMPLETE)
Files: updated `JobService.java` (removed sync Ollama call), `web/JobRoutingUpdateRequest.java`, updated `JobController.java` (PATCH /routing), updated `JobServicePort.java`, updated `JobEventConsumer.java` (full AI pipeline), `worker/ai/EmbeddingService.java`, `worker/ai/OllamaService.java`, `worker/ai/QdrantService.java`, `worker/ai/RoutingDecision.java`, `worker/config/AiConfig.java`, `docs/phase3-end-to-end.md`
Full async pipeline: HTTP returns instantly (PENDING, ~15ms). job-worker reads from Kafka, embeds description via nomic-embed-text, checks Qdrant cache (threshold 0.9), calls Mistral 7B only on miss, stores new embedding in Qdrant, PATCHes workflow-controller /routing (ROUTED), simulates work, PATCHes /status (COMPLETED). Three-stage job lifecycle: PENDING -> ROUTED -> COMPLETED.
### Phase 4.1 — Dockerfiles (COMPLETE)
See dedicated section below ("Phase 4 — Dockerfiles") for full details.

### Phase 4.2 — K8s Application Deployment (COMPLETE)
Files: `k8s/app/api-gateway.yaml`, `k8s/app/workflow-controller.yaml`, `k8s/app/job-worker.yaml`, `scripts/deploy-apps.ps1`
Each Spring Boot module gets a Deployment (1 replica, `imagePullPolicy: Never` for Minikube), Service, and ConfigMap. ConfigMaps inject runtime env vars: DB shard URLs, Kafka bootstrap servers, Qdrant/Ollama hosts, Redis host. Readiness and liveness probes hit `/actuator/health`. `api-gateway` exposed via NodePort 30080; the other two are internal ClusterIP services. Resource requests/limits set per module (workflow-controller and job-worker get higher RAM since they handle DB/AI calls).

### Phase 4.3 — End-to-End Deployment Verification (IN PROGRESS)
Files: `scripts/smoke-test.ps1` (extended), `scripts/deploy-apps.ps1`
Smoke test now validates: all pods Running, NodePort URL resolves, POST /api/v1/jobs returns 201 with shardKey, polls GET until COMPLETED (180s timeout for first job to handle Mistral cold-start), cache-hit test (semantically similar second job should be faster than first), 5-job concurrency test (validates Java 21 Virtual Threads under parallel load).

**Major issues resolved during 4.3:**

| Issue | Root Cause | Fix |
|---|---|---|
| `no main manifest attribute, in app.jar` -> CrashLoopBackOff | Spring Boot `repackage` goal wasn't fat-jarring without `spring-boot-starter-parent` | Added explicit `<executions><goal>repackage</goal></executions>` in all 3 module POMs |
| `UnsatisfiedDependencyException: 2 DataSource beans found` | Two separate `@Bean` methods exposed `dataSourceShardA` and `dataSourceShardB` to Spring's context, breaking auto-config | Refactored `JpaConfig.routingDataSource()` to instantiate shard `DataSource`s as local variables; only `routingDataSource` is a `@Bean` |
| `hbm2ddl.auto=validate` -> `UnknownHostException` outside K8s | Hibernate connects to PG at startup to validate schema; fails when DNS not in cluster context | Changed to `hbm2ddl.auto=none`; explicit schema creation moved into `deploy-infra.ps1` after PG shards are Ready |
| `Multiple compiler errors: parameter name information missing` in Spring 6.x | Java 21 strips parameter names by default; Spring 6 requires `-parameters` | Added `<parameters>true</parameters>` to `maven-compiler-plugin` in parent POM |
| Stale image in Minikube containerd registry after rebuild | `minikube image load` doesn't always overwrite in-use tags | `minikube delete --purge` + `docker rmi -f` + `docker buildx prune -f` + fresh build (deep clean sequence in script comments) |
| Ingress addon enable timeouts crashing setup script | Corporate firewall blocks `registry.k8s.io` digest verification during addon callback | `setup-cluster.ps1` catches the addon failure and patches deployment to use local image cache + skips digest match |
| Setup script crashed mid-run leaving stale `~/.minikube/machines/minikube` | `id_rsa.pub` file locked by previous process | `setup-cluster.ps1` now runs `minikube delete` upfront to guarantee clean state before `start` |
| `kubectl wait` matching admission Job pods (`ingress-nginx-admission-create-*`) | Label selector `app.kubernetes.io/name=ingress-nginx` matches both controller and one-time Jobs | Narrowed selector to `app.kubernetes.io/component=controller` |
| Amdocs IT compliance force-rebooted machine after `wsl --update` | `wsl --update` replaced certified Amdocs WSL kernel with vanilla Microsoft one; compliance scanner triggered enforcement | Re-installed Amdocs-certified WSL image via `000-wsl.ps1`. Documented Hyper-V backend as long-term alternative for corporate machines |

### Phase 5.1 — React Frontend (PENDING)
### Phase 6 — Observability (PENDING)
### Phase 7 — CI/CD + GitHub (PENDING)

---

## Database Sharding Strategy

Two PostgreSQL pods act as independent shards. The Spring Boot controller routes each job write
to the correct shard using `hash(job_id) % 2`:

- `hash(job_id) % 2 == 0` → `postgres-shard-a-svc:5432`
- `hash(job_id) % 2 == 1` → `postgres-shard-b-svc:5432`

Implemented via Spring's `AbstractRoutingDataSource`. Read queries check both shards.

---

## Kafka Topics

| Topic | Producer | Consumer | Carries |
|---|---|---|---|
| `job-submitted` | workflow-controller | job-worker | New job accepted by API |
| `job-routed` | workflow-controller | job-worker | Sub-tasks after LLM routing |
| `job-completed` | job-worker | workflow-controller | Sub-task completion events |

---

## Key Concepts Learned

### Containers and Kubernetes
- **Container** — isolated Linux process with its own filesystem, network, and process space
- **Pod** — K8s wrapper around one or more containers, smallest deployable unit
- **Node** — machine that runs pods; Minikube has one node that is both control plane and worker
- **Namespace** — logical partition inside a cluster; `ai-orchestrator` isolates our pods
- **Service** — stable DNS name + IP for a set of pods; pods come and go, Service stays
- **Deployment** — declares desired state (e.g. 2 replicas of workflow-controller); K8s maintains it
- **ConfigMap** — key-value config injected into pods as env vars or files
- **Secret** — like ConfigMap but for sensitive values; base64-encoded, access-controlled

### Networking
- **ClusterIP** — service accessible only inside the cluster
- **NodePort** — service accessible from outside via a port on the node IP
- **Ingress** — reverse proxy routing HTTP requests to services by hostname/path
- **Reverse proxy** — sits between internet and your servers; clients see one address, servers are hidden

### Image Pull Policies
- `Always` — always contact registry (even if local copy exists); fails on VPN
- `IfNotPresent` — use local if available; only pull if missing
- `Never` — never pull; fail if not in local cache (requires exact digest match)

### Environment Variables
- **`dotenv`** — reads `.env` file and loads values into `process.env` at startup
- **`.env`** — local secrets file; never committed to git
- **`.env.example`** — committed template showing required variables without real values

---

## Day-to-Day Commands

```powershell
# Start cluster (run once per session)
.\scripts\setup-cluster.ps1

# Stop cluster (frees 16GB RAM)
minikube stop

# Full reset (delete everything)
minikube delete

# Run a subtask agent
npx ts-node scripts/run-subtask.ts 1.2

# Check all subtask statuses
npx ts-node scripts/list-agents.ts

# Apply a K8s manifest
kubectl apply -f k8s/infra/postgres/postgres-shard-a.yaml

# Check pods in our namespace
kubectl get pods -n ai-orchestrator

# See logs of a pod
kubectl logs <pod-name> -n ai-orchestrator

# Open Minikube dashboard
minikube dashboard
```

---

## Git Strategy

```
# First time setup
git init
git remote add origin https://github.com/piyushvi/local-ai-orchestrator.git
git add .
git commit -m "Phase 0+1.1: orchestrator setup and Minikube cluster"
git push -u origin main
```

**What gets committed:** all source code, manifests, scripts, docs, `package.json`, `subtasks.json`

**What never gets committed:** `node_modules/`, `.env`, `target/`, `dist/`, `.minikube/`

---

## Phase 4 — Dockerfiles (Subtask 4.1) — DONE

Multi-stage Dockerfiles created for all three Spring Boot modules. Key points:

| Module | Port | JVM Flags |
|--------|------|-----------|
| `api-gateway` | 8080 | default |
| `workflow-controller` | 8081 | `UseContainerSupport`, `MaxRAMPercentage=75` |
| `job-worker` | 8082 | `UseContainerSupport`, `MaxRAMPercentage=75` |

**Security hardening applied:**
- All runtime containers run as non-root (`appuser:appgroup`)
- Docker `HEALTHCHECK` on `/actuator/health` for all three modules
- `.dockerignore` extended to exclude `.env`, `.env.*`, `backups/`, `*.sql`

**Script:** `scripts/build-images.ps1` — builds and loads all images into Minikube.

Full documentation: `docs/phase4-dockerfiles.md`

---

## Next Step

**Subtask 4.3 — End-to-End Deployment Verification** (in progress; needs final smoke-test run after Amdocs WSL reinstall completes).

After 4.3 passes:
- Phase 5: React dashboard
- Phase 6: Observability (OpenTelemetry + Jaeger + Prometheus)
- Phase 7: CI/CD via GitHub Actions

## Operational Runbook

### Daily start
```powershell
# 1. Ensure Docker Desktop is running (whale icon green)
# 2. Start cluster + load images
cd C:\Users\piyushvi\Downloads\project\local-ai-orchestrator
.\scripts\setup-cluster.ps1

# 3. Deploy infra (PG, Redis, Kafka, Qdrant, Ollama + create jobs table)
.\scripts\deploy-infra.ps1

# 4. Deploy apps (api-gateway, workflow-controller, job-worker)
.\scripts\deploy-apps.ps1

# 5. Smoke test
.\scripts\smoke-test.ps1
```

### Daily stop (saves RAM)
```powershell
minikube stop
```

### Full reset (when stuck)
```powershell
minikube delete --purge
docker rmi -f local-ai/workflow-controller:latest local-ai/api-gateway:latest local-ai/job-worker:latest
docker buildx prune -f

# Then rebuild and redeploy from scratch
cd orchestrator-parent
docker build --no-cache -f workflow-controller/Dockerfile -t local-ai/workflow-controller:latest .
docker build --no-cache -f api-gateway/Dockerfile -t local-ai/api-gateway:latest .
docker build --no-cache -f job-worker/Dockerfile -t local-ai/job-worker:latest .
cd ..
.\scripts\setup-cluster.ps1
.\scripts\deploy-infra.ps1
.\scripts\deploy-apps.ps1
```

### Docker backend choice (corporate machines)
On Amdocs/restricted environments, **prefer Hyper-V backend** to avoid forced WSL compliance reboots:
- Docker Desktop -> Settings -> General -> uncheck "Use WSL 2 based engine" -> Apply & Restart
- Trade-off: ~5-10% slower builds, larger fixed RAM allocation
- Benefit: zero dependency on WSL distribution; no IT compliance interference

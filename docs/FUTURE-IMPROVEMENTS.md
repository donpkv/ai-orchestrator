# Future Improvements & Expansion Areas

Everything that can be added, improved, or scaled up — ordered from near-term quick wins to long-term architectural evolutions.

---

## Tier 1 — Already Planned (Phases 6–9, subtasks.json)

These are committed to the roadmap and have subtask entries:

| Phase | What | Impact |
|---|---|---|
| 6.1 | OpenTelemetry + Jaeger tracing | See full request journey across all pods with timing |
| 6.2 | Prometheus + Grafana dashboards | Real-time metrics: job throughput, Kafka lag, Ollama latency, cache hit rate |
| 6.3 | Fluent Bit + Loki logging | All pod logs in one searchable place |
| 6b.1 | RAG ingestion microservice | Upload domain documents → inject context into Ollama routing prompt |
| 6b.2 | Job Worker RAG context injection | Domain-aware routing — Mistral 7B uses your uploaded knowledge base |
| 7.1 | Keycloak identity provider | Production-grade OAuth2/OIDC identity management |
| 7.2 | API Gateway JWT validation | Every request authenticated before reaching backend services |
| 7.3 | RBAC in workflow-controller | Role-based access: admin / submitter / viewer |
| 7.5 | Istio service mesh + mTLS | Automatic encryption between all pods, circuit breaking, Kiali visual map |
| 8.1 | Kafka NetworkPolicy | Only workflow-controller and job-worker can reach Kafka port 9092 |
| 8.2 | Kafka SASL/SCRAM + ACLs | Kafka authentication and topic-level authorization |
| 9.1 | GitHub Actions CI/CD | Auto-build, test, push images to GHCR on every push to main |

---

## Tier 2 — High Value, Medium Effort

### T2-01: Dead Letter Topic (DLT) for Failed Jobs
**What:** If `job-worker` throws an unhandled exception after N retries, publish to a `job-failed` DLT instead of silently dropping the message.
**Why:** Currently a job that fails in AI processing stays `PENDING` forever. With a DLT, failed jobs are visible and can be replayed.
**How:** Spring Kafka `@RetryableTopic` annotation — 3 retries with exponential backoff, then DLT. Add a separate consumer to mark jobs `FAILED` and notify.

---

### T2-02: Real-time Job Status via WebSocket
**What:** Replace frontend polling (every 3 seconds) with a WebSocket connection. Server pushes status updates instantly.
**Why:** Polling creates unnecessary load on Redis and workflow-controller. With 100 concurrent users polling every 3s, that's 100 Redis reads/second for no reason.
**How:** Add `spring-boot-starter-websocket` to workflow-controller. Emit status change events from `updateJobStatus()`. Frontend subscribes via SockJS/STOMP.

---

### T2-03: Explicit Resource Limits on Infra Pods
**What:** Add `resources.requests` and `resources.limits` to postgres, redis, kafka, qdrant, ollama manifests.
**Why:** Currently Ollama can consume all available RAM when loading Mistral 7B, starving other pods. Kubernetes cannot enforce QoS guarantees without limits.
**Suggested limits:**

| Pod | Memory Request | Memory Limit |
|---|---|---|
| postgres-shard-a/b | 128 Mi | 512 Mi |
| redis | 64 Mi | 256 Mi |
| kafka | 1 Gi | 2 Gi |
| qdrant | 256 Mi | 512 Mi |
| ollama | 5 Gi | 7 Gi |

---

### T2-04: Job Priority Queue
**What:** Higher-priority jobs (priority 8-10) skip ahead of lower-priority jobs in the Kafka queue.
**Why:** Currently all jobs go into the same single-partition topic. A priority=10 urgent job waits behind a priority=1 batch job.
**How:** Create multiple topics (`job-submitted-high`, `job-submitted-normal`, `job-submitted-low`). Publish to correct topic based on priority. Job-worker subscribes to all three, polled in priority order.

---

### T2-05: Job Result Storage (not just status)
**What:** Store the actual output/result of job execution in PostgreSQL alongside the routing decision.
**Why:** Currently `routingDecision` stores the Ollama JSON (workerType, reasoning). There's no field for what the job actually produced. Extending the schema enables job history, result retrieval, and analytics.
**How:** Add `result TEXT` column to the jobs table. Have job-worker write the execution output to `PATCH /api/v1/jobs/{id}/result`.

---

### T2-06: Horizontal Pod Autoscaler for Job Worker
**What:** Automatically scale `job-worker` replicas based on Kafka consumer lag.
**Why:** When many jobs are submitted quickly, a single job-worker takes too long (each Ollama call blocks a thread for 20-180s). Multiple replicas would process in parallel.
**How:** Add HPA manifest targeting `kafka_consumer_group_lag` metric (via Prometheus + KEDA). Scale 1→5 replicas when lag > 10 messages.

---

### T2-07: Graceful Ollama Warm-up on Pod Start
**What:** On `job-worker` startup, send a dummy embed request to Ollama to warm the model into RAM before the first real job arrives.
**Why:** The first real job after a cluster restart currently takes 90-180s because Mistral 7B loads cold. A warm-up request at startup absorbs this latency before any user is waiting.
**How:** `@PostConstruct` method in `JobEventConsumer` or `AiConfig` that calls `embeddingService.embed("warmup")` silently.

---

## Tier 3 — Architectural Evolutions (Long Term)

### T3-01: Replace PostgreSQL Sharding with Citus (Distributed PostgreSQL)
**What:** Replace the two independent PostgreSQL pods and `AbstractRoutingDataSource` with a Citus cluster — a distributed PostgreSQL that handles sharding transparently.
**Why:** Current sharding requires application-level shard routing and scatter-gather reads. Citus handles this at the database layer — queries look like normal SQL to the application. Real production sharding pattern.
**Impact:** Remove `ShardContextHolder`, `ShardRoutingDataSource`, `JpaConfig` sharding logic. Replace with single `DataSource` pointing to Citus coordinator.

---

### T3-02: Replace Ollama with a Proper LLM Serving Stack
**What:** Replace `ollama/ollama` with `vllm` (for GPU) or `llama.cpp` server (for CPU) with proper batching and quantization.
**Why:** Ollama is great for development but not optimized for throughput. vLLM supports continuous batching (multiple requests to the same model in parallel). With a GPU, inference drops from 20s to <2s per request.
**When:** When deploying to cloud (Phase 9+) with a GPU node.

---

### T3-03: Multi-Model Routing
**What:** Instead of always routing to `mistral:7b`, use a fast small model (e.g. `phi3:mini`) for simple classification and fall back to `mistral:7b` only for complex jobs.
**Why:** `phi3:mini` (2.3 GB) can classify job types in ~3s vs `mistral:7b` at 20-90s. Most jobs ("Process sales report", "Send notification") are simple enough for the small model.
**How:** Add a `ModelSelector` service that uses keyword heuristics or a lightweight classifier to decide which model to call.

---

### T3-04: Event Sourcing for Job State
**What:** Replace status updates via `PATCH /status` with an event log. Each state transition (`PENDING→ROUTED→COMPLETED`) is an immutable event appended to Kafka. Current state is derived by replaying events.
**Why:** Full audit trail. Time-travel debugging — replay events to see exactly what happened to any job. Natural fit for CQRS architecture.
**How:** New Kafka topic `job-events`. Each event: `{jobId, fromStatus, toStatus, timestamp, actor}`. New `job-event-consumer` builds read model in PostgreSQL.

---

### T3-05: Multi-Tenant Support
**What:** Each user/organisation gets isolated job queues, isolated Qdrant namespaces, and separate resource quotas.
**Why:** Current system is single-tenant. All users share one Kafka topic, one Qdrant collection, one job table.
**How:** Add `tenantId` to JWT claims (from Keycloak). Propagate `tenantId` through all hops. Use Qdrant collection per tenant or Qdrant payload filter. Separate Kafka consumer groups per tenant for isolation.

---

### T3-06: Cloud Deployment — EKS / GKE
**What:** Deploy the same Kubernetes manifests to a managed cloud cluster (AWS EKS or GCP GKE).
**Why:** Makes the project publicly accessible, demonstrates production deployment skills, enables CI/CD (GitHub Actions deploy step).
**Requires:**
- Replace `imagePullPolicy: Never` with GHCR image references (Phase 9)
- Replace Ollama local models with cloud-hosted LLM (Bedrock, Vertex AI, or Ollama on GPU node)
- Add TLS via cert-manager + Let's Encrypt
- Add ingress with real domain (Cloudflare DNS)
- Estimated monthly cost: ~$80-150 on GKE Autopilot (no GPU) or ~$200+ with GPU node

---

### T3-07: Advanced RAG — Modular, Agentic, Graph RAG
**What:** Upgrade the basic chunk-and-search RAG (Phase 6b) to:
- **Modular RAG:** Separate retriever, reranker (cross-encoder), and generator stages
- **Agentic RAG:** Job-worker decides whether to query knowledge base at all based on job type
- **Graph RAG:** Build a knowledge graph from documents — relationships between entities, not just chunks
**Why:** Better routing accuracy for complex domain-specific jobs. Demonstrates state-of-the-art RAG patterns.
**Tools:** ColBERT for late interaction retrieval, cross-encoder reranker, Apache Jena or Neo4j for graph.

---

### T3-08: A/B Testing for LLM Routing
**What:** Route a percentage of jobs to different models (e.g. 20% to `llama3:8b`, 80% to `mistral:7b`) and compare routing accuracy.
**Why:** Validate that the chosen LLM produces better routing decisions than alternatives. Data-driven model selection.
**How:** Feature flag in `AiConfig` driven by environment variable. Log model choice with each job. Grafana dashboard comparing routing outcomes by model.

---

## Quick Wins (Can be done in <1 hour each)

| Item | What | Effort |
|---|---|---|
| QW-01 | Add resource limits to infra pods | 30 min — edit 5 YAML files |
| QW-02 | Add `@PostConstruct` Ollama warm-up | 15 min — 5 lines of Java |
| QW-03 | Add `failureReason` field to Job entity | 20 min — 1 column, 1 field, used in DLT handler |
| QW-04 | Add `job-worker.5` subtask entry (Istio Phase 7.5) | 5 min — already noted in subtasks.json |
| QW-05 | Add Grafana pre-built dashboard JSON to repo | 30 min — export from Grafana UI after Phase 6 |
| QW-06 | Add `nomic-embed-text` to `/actuator/health` custom indicator | 20 min — HTTP GET ollama /api/tags, check model present |

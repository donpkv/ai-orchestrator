# Architecture Document — HLD & LLD

---

## Part 1: High-Level Design (HLD)

### 1.1 System Purpose

The Intelligent Workflow Orchestrator accepts natural-language job descriptions from users, uses a local AI pipeline to classify and route each job to the appropriate worker type, and tracks job lifecycle through a distributed backend. All components run as Kubernetes pods on a single Minikube cluster.

---

### 1.2 High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Minikube)                        │
│                    Namespace: ai-orchestrator                           │
│                                                                         │
│  ┌──────────┐    ┌─────────────────┐    ┌──────────────────────────┐  │
│  │ Browser  │───▶│   API Gateway   │───▶│  Workflow Controller     │  │
│  │ React UI │    │ Spring Cloud GW │    │  Spring Boot REST API    │  │
│  └──────────┘    │ :8080           │    │  :8081                   │  │
│                  └─────────────────┘    └────────┬─────────────────┘  │
│                                                  │                     │
│               ┌──────────────────────────────────┤                     │
│               │              │                   │                     │
│               ▼              ▼                   ▼                     │
│        ┌──────────┐  ┌──────────────┐  ┌──────────────┐              │
│        │PostgreSQL│  │    Redis     │  │    Kafka     │              │
│        │Shard A+B │  │  Cache :6379 │  │  KRaft :9092 │              │
│        └──────────┘  └──────────────┘  └──────┬───────┘              │
│                                                │                       │
│                                                ▼                       │
│                                    ┌───────────────────────┐          │
│                                    │      Job Worker       │          │
│                                    │   Kafka Consumer      │          │
│                                    │   :8082               │          │
│                                    └──────┬──────┬─────────┘          │
│                                           │      │                     │
│                              ┌────────────┘      └──────────┐         │
│                              ▼                              ▼          │
│                    ┌──────────────────┐         ┌──────────────────┐  │
│                    │     Qdrant       │         │     Ollama       │  │
│                    │  Vector DB :6333 │         │  LLM Runtime     │  │
│                    │  job-embeddings  │         │  :11434          │  │
│                    └──────────────────┘         │  mistral:7b      │  │
│                                                 │  nomic-embed-text│  │
│                                                 └──────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 1.3 Component Responsibilities (HLD)

| Component | Responsibility |
|---|---|
| **React Frontend** | Submit jobs, display job list with status, filter by status, expand job details |
| **API Gateway** | Single entry point for all external traffic; CORS; route `/api/v1/**` to workflow-controller |
| **Workflow Controller** | REST API for jobs; persist to sharded PostgreSQL; cache status in Redis; publish Kafka event |
| **Job Worker** | Consume Kafka events; run AI pipeline (embed → Qdrant search → Ollama); update job status |
| **Qdrant** | Store 768-dim job embeddings; semantic similarity search for routing cache |
| **Ollama** | Run `nomic-embed-text` (embedding) and `mistral:7b` (routing classification) locally |
| **Kafka** | Async message bus decoupling job submission from AI processing |
| **PostgreSQL × 2** | Persistent job storage; two independent shards for horizontal scaling |
| **Redis** | Job status cache-aside; reduces repeated DB reads during frontend polling |

---

### 1.4 Data Flow — Job Submission (HLD)

```
1. User submits job description via browser
2. API Gateway receives POST /api/v1/jobs, routes to workflow-controller
3. Workflow-controller:
   a. Generates UUID, computes shard (hash % 2)
   b. Saves job to correct PostgreSQL shard (status=PENDING)
   c. Caches status in Redis
   d. Publishes job-submitted event to Kafka
   e. Returns 201 with job ID instantly
4. Browser polls GET /api/v1/jobs/{id} every 3 seconds
5. Job-worker consumes Kafka event asynchronously:
   a. Embeds description → 768-dim vector via nomic-embed-text
   b. Searches Qdrant for similar past jobs (threshold 0.9)
   c. Cache HIT → reuse routing decision (skip LLM, ~7s total)
   d. Cache MISS → call Mistral 7B (~90-180s cold, ~20s warm)
   e. Store embedding + routing in Qdrant
   f. PATCH workflow-controller → status=ROUTED
   g. PATCH workflow-controller → status=COMPLETED
6. Browser poll returns COMPLETED — UI updates
```

---

### 1.5 Non-Functional Requirements

| Concern | Implementation |
|---|---|
| **Availability** | Kubernetes restarts crashed pods automatically via liveness probes |
| **Scalability** | Job-worker can scale horizontally (multiple replicas consume from same Kafka topic) |
| **Latency** | Redis cache-aside for O(1) status reads; Qdrant cache reduces LLM dependency |
| **Concurrency** | Java 21 Virtual Threads — each HTTP request and Kafka event on its own thread |
| **Security** | Non-root Docker containers; CORS at gateway; JWT/Keycloak planned (Phase 7) |
| **Observability** | Spring Actuator health endpoints; Prometheus metrics planned (Phase 6) |

---

## Part 2: Low-Level Design (LLD)

### 2.1 workflow-controller — Internal Design

#### Job Submission Flow

```
JobController.submitJob(JobRequest)
    │
    ├── @Validated — validates description (NotBlank), priority (1-10)
    │
    └── JobService.submitJob(request)
            │
            ├── id = UUID.randomUUID()
            ├── shardKey = Math.floorMod(id.hashCode(), 2)
            │
            ├── ShardContextHolder.setShard("shard-a" or "shard-b")
            │       └── ThreadLocal<String> — thread-safe, one value per virtual thread
            │
            ├── Job entity built:
            │     id, description, priority, status="PENDING",
            │     shardKey, workerType=null, routingDecision=null
            │
            ├── jobRepository.save(job)
            │       └── ShardRoutingDataSource.determineCurrentLookupKey()
            │               └── reads ShardContextHolder → routes to correct HikariDataSource
            │
            ├── ShardContextHolder.clear() [finally block]
            │
            ├── redisTemplate.opsForValue().set("job:status:{id}", "PENDING", 5min)
            │
            ├── kafkaTemplate.send("job-submitted", id.toString(), jsonPayload)
            │       └── fire-and-forget — Kafka failure never breaks HTTP response
            │
            └── return JobResponse(id, description, priority, "PENDING", shardKey, submittedAt)
```

#### Sharding — AbstractRoutingDataSource

```
ShardRoutingDataSource extends AbstractRoutingDataSource
    │
    determineCurrentLookupKey()
        └── returns ShardContextHolder.getShard()  →  "shard-a" or "shard-b"

JpaConfig
    ├── HikariDataSource dataSourceShardA  (DB_SHARD_A_URL env var)
    ├── HikariDataSource dataSourceShardB  (DB_SHARD_B_URL env var)
    └── @Bean @Primary ShardRoutingDataSource
            ├── targetDataSources: {"shard-a": shardA, "shard-b": shardB}
            └── defaultTargetDataSource: shardA
```

#### Redis Cache-Aside Pattern

```
getJob(UUID id):
    1. key = "job:status:" + id
    2. cached = redisTemplate.opsForValue().get(key)
    3. IF cached != null → populate JobResponse with cached status (skip DB)
    4. ELSE:
       a. ShardContextHolder.setShard(shard)
       b. job = jobRepository.findById(id)
       c. ShardContextHolder.clear()
       d. redisTemplate.set(key, job.getStatus(), 5min)
       e. return full JobResponse from DB
```

---

### 2.2 job-worker — AI Pipeline LLD

```
JobEventConsumer.handleJobSubmitted(String kafkaMessage)
    │
    ├── Parse JSON: jobId (UUID), description (String)
    │
    ├── STEP 1: Embed
    │   EmbeddingService.embed(description)
    │       POST http://ollama-svc:11434/api/embed
    │       body: {"model":"nomic-embed-text","input":"<description>"}
    │       response: {"embeddings":[[0.12, -0.03, ...]]}  ← 768 floats
    │       returns: float[768]
    │
    ├── STEP 2: Qdrant Cache Lookup
    │   QdrantService.findSimilarRouting(float[768])
    │       POST /collections/job-embeddings/points/search
    │       body: {vector: [...], limit: 1, with_payload: true}
    │       response: [{id, score, payload: {routingDecision, jobId}}]
    │       IF score >= 0.9 → return Optional.of(routingDecision)  ← CACHE HIT
    │       ELSE → return Optional.empty()                          ← CACHE MISS
    │
    ├── STEP 3a (Cache HIT):
    │   workerType = cachedRoutingDecision
    │   routingDecisionJson = {"source":"qdrant-cache","workerType":"<wt>"}
    │
    ├── STEP 3b (Cache MISS):
    │   OllamaService.route(description)
    │       POST http://ollama-svc:11434/api/generate
    │       body: {
    │           model: "mistral:7b",
    │           stream: false,
    │           prompt: "You are a job routing system...
    │                   Respond ONLY with JSON:
    │                   {workerType, estimatedSeconds, suggestedPriority, reasoning}"
    │       }
    │       Parse response.response field → find first { last } → Jackson parse
    │       IF parse fails → RoutingDecision.defaultDecision() (workerType="general")
    │
    │   QdrantService.storeJobEmbedding(jobId, vector, workerType)
    │       PUT /collections/job-embeddings/points
    │       body: {points:[{id:jobId, vector:[...], payload:{routingDecision, jobId}}]}
    │
    ├── STEP 4: Update Routing
    │   PATCH http://workflow-controller-svc:8081/api/v1/jobs/{jobId}/routing
    │   body: {workerType, routingDecision}  → status becomes ROUTED in DB + Redis
    │
    ├── STEP 5: Simulate Work
    │   Thread.sleep(2000)
    │
    └── STEP 6: Mark Complete
        PATCH http://workflow-controller-svc:8081/api/v1/jobs/{jobId}/status
        body: {status: "COMPLETED"}  → DB + Redis updated
```

---

### 2.3 Database Schema (LLD)

```sql
-- Applied to BOTH postgres-shard-a and postgres-shard-b
CREATE TABLE IF NOT EXISTS jobs (
    id               UUID         PRIMARY KEY,
    description      TEXT         NOT NULL,
    priority         INTEGER      DEFAULT 5,
    status           VARCHAR(50)  DEFAULT 'PENDING',
    shard_key        INTEGER,                          -- 0 or 1
    worker_type      VARCHAR(100),                     -- set by job-worker
    routing_decision TEXT,                             -- JSON from Ollama/Qdrant
    submitted_at     TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS jobs_pkey ON jobs (id);
```

**Shard assignment:** `shard_key = Math.floorMod(id.hashCode(), 2)`. Shard A stores `shard_key=0`, Shard B stores `shard_key=1`.

---

### 2.4 Qdrant Collection Schema (LLD)

```
Collection: job-embeddings
    Vector:  size=768, distance=Cosine   (auto-created on first upsert)
    Payload per point:
        jobId           String   — UUID of the job that generated this embedding
        routingDecision String   — workerType assigned (e.g. "analysis", "general")
    
Search parameters:
    limit: 1           — return only best match
    score_threshold:   — filter applied in application code (score >= 0.9)
    with_payload: true — return payload fields for routing reuse
```

---

### 2.5 Kafka Topic Schema (LLD)

```
Topic: job-submitted
    Partitions:      1
    Replication:     1 (single node)
    Key:             job UUID (String)
    Value (JSON):
        {
            "jobId":       "550e8400-e29b-41d4-a716-446655440000",
            "description": "Generate weekly inventory report for warehouse A",
            "priority":    7,
            "shardKey":    "shard-a"
        }
    Consumer group: job-worker-group
    Auto-offset-reset: earliest
```

---

### 2.6 API Contract (LLD)

#### POST /api/v1/jobs
```
Request:  { "description": "string (required)", "priority": int (1-10, default 5) }
Response: 201 Created
          {
            "id":              "uuid",
            "description":     "string",
            "priority":        int,
            "status":          "PENDING",
            "shardKey":        "shard-a" | "shard-b",
            "workerType":      null,
            "routingDecision": null,
            "submittedAt":     "ISO-8601"
          }
```

#### GET /api/v1/jobs/{id}
```
Response: 200 OK — same structure as above, status will be PENDING|ROUTED|COMPLETED|FAILED
          404 Not Found — if ID doesn't exist on computed shard
```

#### PATCH /api/v1/jobs/{id}/status  (internal — job-worker only)
```
Request:  { "status": "ROUTED" | "COMPLETED" | "FAILED" }
Response: 204 No Content
```

#### PATCH /api/v1/jobs/{id}/routing  (internal — job-worker only)
```
Request:  { "workerType": "string", "routingDecision": "json-string" }
Response: 204 No Content
```

---

### 2.7 Thread Model (LLD)

```
workflow-controller:
    Tomcat thread pool → replaced with Executors.newVirtualThreadPerTaskExecutor()
    Each HTTP request:  1 virtual thread
    Each virtual thread does:
        - 2× JDBC calls (shard lookup + save) → parks on I/O
        - 1× Redis call                       → parks on I/O
        - 1× Kafka send                       → parks on I/O
    Total platform threads held: 0 during I/O waits

job-worker:
    Kafka listener executor → SimpleAsyncTaskExecutor with virtual thread factory
    Each Kafka message: 1 virtual thread
    Each virtual thread does:
        - 1× HTTP POST to Ollama (embed)      → parks on I/O (320ms)
        - 1× HTTP POST to Qdrant (search)     → parks on I/O (12ms)
        - 1× HTTP POST to Ollama (generate)   → parks on I/O (20-180s)
        - 2× HTTP PATCH to workflow-controller → parks on I/O
    Total platform threads held: 0 during I/O waits
```

---

### 2.8 Kubernetes Resource Model (LLD)

| Pod | CPU Request | CPU Limit | Memory Request | Memory Limit | PVC |
|---|---|---|---|---|---|
| api-gateway | 250m | 500m | 256 Mi | 512 Mi | — |
| workflow-controller | 500m | 1000m | 512 Mi | 1 Gi | — |
| job-worker | 500m | 1000m | 512 Mi | 1 Gi | — |
| frontend | 100m | 250m | 64 Mi | 128 Mi | — |
| postgres-shard-a | — | — | — | — | 1 Gi |
| postgres-shard-b | — | — | — | — | 1 Gi |
| redis | — | — | — | — | — |
| kafka | — | — | — | — | 2 Gi |
| qdrant | — | — | — | — | 2 Gi |
| ollama | — | — | — | — | 10 Gi |

Infra pods (postgres, redis, kafka, qdrant, ollama) currently have no explicit CPU/memory limits set — **this is a known gap** to fix in Phase 6 (add explicit limits so Ollama doesn't starve other pods during model loading).

# Intelligent Workflow Orchestrator — Architecture & UML Diagrams

---

## 1. System Architecture Diagram

```mermaid
graph TB
    subgraph Client["Client Layer"]
        Browser["Browser\nReact + TypeScript"]
    end

    subgraph K8s["Kubernetes Cluster (Minikube) — ai-orchestrator namespace"]
        subgraph Ingress["Ingress Layer"]
            NG["Nginx Ingress Controller"]
            FE["Frontend Pod\n(Nginx + React)"]
        end

        subgraph AppLayer["Application Layer"]
            GW["API Gateway\n(Spring Cloud Gateway)\nPort 8080"]
            WC["Workflow Controller\n(Spring Boot)\nPort 8081"]
            JW["Job Worker\n(Spring Boot)\nPort 8082"]
        end

        subgraph AILayer["AI/ML Layer"]
            OL["Ollama\n(Mistral 7B LLM)\nPort 11434"]
            QD["Qdrant\n(Vector DB)\nPort 6333"]
        end

        subgraph DataLayer["Data Layer"]
            PSA["PostgreSQL\nShard-A\nPort 5432"]
            PSB["PostgreSQL\nShard-B\nPort 5432"]
            RD["Redis\n(Cache)\nPort 6379"]
            KF["Kafka\n(KRaft)\nPort 9092"]
        end
    end

    Browser -->|"HTTP /api/"| NG
    NG -->|"/"| FE
    FE -->|"/api/ proxy"| GW
    GW -->|"Path=/api/v1/**"| WC
    WC -->|"hash(UUID)%2==0"| PSA
    WC -->|"hash(UUID)%2==1"| PSB
    WC -->|"cache-aside"| RD
    WC -->|"publish job event"| KF
    KF -->|"consume job-submitted"| JW
    JW -->|"embed + search"| QD
    JW -->|"LLM routing fallback"| OL
    JW -->|"PATCH status"| WC
```

---

## 2. Job Submission Sequence Diagram (Cache MISS — LLM Path)

```mermaid
sequenceDiagram
    actor User
    participant FE as Frontend (Nginx)
    participant GW as API Gateway
    participant WC as Workflow Controller
    participant PG as PostgreSQL (Shard)
    participant KF as Kafka
    participant JW as Job Worker
    participant EM as Ollama (nomic-embed-text)
    participant QD as Qdrant
    participant LLM as Ollama (Mistral 7B)
    participant RD as Redis

    User->>FE: Submit job description
    FE->>GW: POST /api/v1/jobs
    GW->>WC: Route to workflow-controller
    WC->>PG: INSERT job (status=PENDING)
    WC->>KF: publish job-submitted event
    WC-->>GW: 201 Created {id, status: PENDING}
    GW-->>FE: JobResponse
    FE-->>User: Shows PENDING

    Note over KF,JW: Async Processing Begins

    KF->>JW: Consume job-submitted event
    JW->>EM: POST /api/embed {text: description}
    EM-->>JW: float[768] embedding vector

    JW->>QD: Search similar vectors (cosine ≥ 0.9)
    QD-->>JW: No results (CACHE MISS)

    JW->>LLM: POST /api/generate {prompt: routing system...}
    Note over LLM: Mistral 7B inference (~60-90s on CPU)
    LLM-->>JW: {workerType, reasoning, priority}

    JW->>QD: Upsert embedding + routingDecision
    JW->>WC: PATCH /api/v1/jobs/{id}/status {status: ROUTED}
    WC->>PG: UPDATE job (status=ROUTED, workerType=analysis)
    JW->>WC: PATCH /api/v1/jobs/{id}/status {status: COMPLETED}
    WC->>PG: UPDATE job (status=COMPLETED)

    Note over FE,User: Frontend polls every 3s

    FE->>GW: GET /api/v1/jobs/{id}
    GW->>WC: Route request
    WC->>RD: GET job:status:{id}
    RD-->>WC: MISS (first read)
    WC->>PG: SELECT * FROM jobs WHERE id=?
    PG-->>WC: Job{status: COMPLETED}
    WC->>RD: SET job:status:{id} = COMPLETED
    WC-->>GW: JobResponse
    GW-->>FE: JobResponse
    FE-->>User: Shows COMPLETED ✓
```

---

## 3. Job Submission Sequence Diagram (Cache HIT — Qdrant Fast Path)

```mermaid
sequenceDiagram
    actor User
    participant FE as Frontend
    participant GW as API Gateway
    participant WC as Workflow Controller
    participant KF as Kafka
    participant JW as Job Worker
    participant EM as Ollama (nomic-embed-text)
    participant QD as Qdrant
    participant RD as Redis

    User->>FE: Submit similar job description
    FE->>GW: POST /api/v1/jobs
    GW->>WC: Route
    WC->>WC: Persist (PENDING) + Publish to Kafka
    WC-->>FE: 201 Created

    KF->>JW: Consume event
    JW->>EM: Embed description → float[768]
    EM-->>JW: embedding vector

    JW->>QD: Search (cosine similarity)
    Note over QD: Score = 0.99999934 ≥ 0.9 threshold
    QD-->>JW: CACHE HIT — routingDecision: "general"

    Note over JW: Skips Mistral 7B entirely (saves 60-90s)

    JW->>WC: PATCH status → COMPLETED (workerType from cache)
    WC-->>FE: COMPLETED in ~2s
    FE-->>User: Shows COMPLETED ✓ (7s total)
```

---

## 4. Component Diagram

```mermaid
graph LR
    subgraph Frontend
        RC["React Components\n(JobForm, JobTable, Stats)"]
        API["api.ts\n(fetch wrapper)"]
        VT["Vite Dev Server /\nNginx (prod)"]
    end

    subgraph APIGateway["api-gateway"]
        SCG["Spring Cloud Gateway"]
        CORS["CORS Filter\n(GlobalCors)"]
        RT["Route: /api/v1/**\n→ workflow-controller-svc:8081"]
    end

    subgraph WorkflowController["workflow-controller"]
        JC["JobController\n(REST)"]
        JS["JobService\n(business logic)"]
        JP["JobEventPublisher\n(Kafka producer)"]
        ADS["AbstractRoutingDataSource\n(sharding)"]
        CS["CacheService\n(Redis)"]
        JR["JobRepository\n(JPA)"]
    end

    subgraph JobWorker["job-worker"]
        JEC["JobEventConsumer\n(Kafka listener)"]
        ES["EmbeddingService\n(nomic-embed-text)"]
        QDS["QdrantService\n(vector search + upsert)"]
        OLS["OllamaService\n(Mistral 7B routing)"]
        TC["ThreadConfig\n(Virtual Threads)"]
    end

    RC --> API
    API --> VT
    VT -->|"/api/*"| SCG
    CORS --> SCG
    SCG --> RT
    RT --> JC
    JC --> JS
    JS --> JP
    JS --> ADS
    JS --> CS
    ADS --> JR
    JP -->|"job-submitted topic"| JEC
    JEC --> ES
    JEC --> QDS
    JEC --> OLS
    TC -.->|"Executor"| JEC
```

---

## 5. State Machine — Job Lifecycle

```mermaid
stateDiagram-v2
    [*] --> PENDING: POST /api/v1/jobs\n(workflow-controller persists)

    PENDING --> ROUTED: job-worker processes\nOllama/Qdrant routing decision
    PENDING --> FAILED: job-worker exception\n(unrecoverable error)

    ROUTED --> COMPLETED: simulated execution done\njob-worker PATCH /status
    ROUTED --> FAILED: execution failure

    COMPLETED --> [*]: terminal state
    FAILED --> [*]: terminal state

    note right of PENDING
        Kafka event published
        Stored in PostgreSQL
    end note

    note right of ROUTED
        workerType assigned
        routingDecision stored
        Vector upserted to Qdrant
    end note

    note right of COMPLETED
        Cached in Redis
        Available via GET /api/v1/jobs/{id}
    end note
```

---

## 6. Entity Relationship Diagram (PostgreSQL Schema)

```mermaid
erDiagram
    JOBS {
        uuid id PK
        text description
        integer priority
        varchar50 status
        integer shard_key
        varchar100 worker_type
        text routing_decision
        timestamptz submitted_at
        timestamptz updated_at
    }

    SHARD_A ||--o{ JOBS : "stores shard_key=0"
    SHARD_B ||--o{ JOBS : "stores shard_key=1"
```

---

## 7. Class Diagram — Domain Model

```mermaid
classDiagram
    class Job {
        +UUID id
        +String description
        +int priority
        +String status
        +int shardKey
        +String workerType
        +String routingDecision
        +Instant submittedAt
        +Instant updatedAt
    }

    class JobRequest {
        +String description
        +int priority
    }

    class JobResponse {
        +UUID id
        +String description
        +int priority
        +String status
        +String shardKey
        +String workerType
        +String routingDecision
        +String submittedAt
    }

    class JobService {
        +submitJob(JobRequest) JobResponse
        +getJob(UUID) JobResponse
        +getAllJobs() List~JobResponse~
        +updateJobStatus(UUID, String) void
        +updateJobRouting(UUID, String, String) void
        -shardOf(UUID) int
    }

    class JobEventPublisher {
        +publish(UUID, String) void
    }

    class JobEventConsumer {
        +consume(String) void
        -patchJobStatus(UUID, String) void
    }

    class EmbeddingService {
        +embed(String) float[]
    }

    class QdrantService {
        +findSimilarRouting(float[]) Optional~String~
        +storeJobEmbedding(UUID, float[], String) void
        -ensureCollectionExists(int) void
    }

    class OllamaService {
        +route(String) RoutingDecision
    }

    class RoutingDecision {
        +String workerType
        +int estimatedSeconds
        +int suggestedPriority
        +String reasoning
        +boolean isDefault()
        +defaultDecision()$ RoutingDecision
    }

    JobRequest --> Job : creates
    Job --> JobResponse : maps to
    JobService --> Job : manages
    JobService --> JobEventPublisher : uses
    JobEventConsumer --> EmbeddingService : uses
    JobEventConsumer --> QdrantService : uses
    JobEventConsumer --> OllamaService : uses
    OllamaService --> RoutingDecision : returns
```

---

## 8. Deployment Diagram (Kubernetes)

```mermaid
graph TB
    subgraph Windows["Windows 11 Host"]
        DD["Docker Desktop\n(WSL2 backend)"]
        MK["Minikube\n(Docker driver)"]
    end

    subgraph Cluster["Kubernetes Cluster"]
        subgraph NS["Namespace: ai-orchestrator"]
            subgraph Deployments["Deployments"]
                D1["api-gateway\n1 replica\n256Mi-512Mi"]
                D2["workflow-controller\n1 replica\n256Mi-512Mi"]
                D3["job-worker\n1 replica\n256Mi-512Mi"]
                D4["frontend\n1 replica\n64Mi-128Mi"]
                D5["ollama\n1 replica\n4GB+"]
                D6["qdrant\n1 replica\n256Mi-512Mi"]
                D7["redis\n1 replica\n64Mi-128Mi"]
            end

            subgraph StatefulSets["StatefulSets"]
                S1["kafka\n1 replica\n512Mi-1Gi\nPVC: 2Gi"]
                S2["postgres-shard-a\n1 replica\nPVC: 1Gi"]
                S3["postgres-shard-b\n1 replica\nPVC: 1Gi"]
            end

            subgraph Services["Services (ClusterIP)"]
                SV1["api-gateway-svc:8080\nNodePort: 30080"]
                SV2["workflow-controller-svc:8081"]
                SV3["job-worker-svc:8082"]
                SV4["frontend-svc:8083"]
                SV5["kafka-svc:9092"]
                SV6["redis-svc:6379"]
                SV7["qdrant-svc:6333"]
                SV8["postgres-shard-a-svc:5432"]
                SV9["postgres-shard-b-svc:5432"]
                SV10["ollama-svc:11434"]
            end

            subgraph Config["ConfigMaps"]
                CM1["api-gateway-config\nSPRING_PROFILES_ACTIVE\nALLOWED_ORIGINS"]
                CM2["workflow-controller-config\nDB, Redis, Kafka URLs"]
                CM3["job-worker-config\nKafka, Ollama, Qdrant URLs"]
            end

            IG["Ingress\norchestrator-ingress\n/ → frontend-svc:8083"]
        end

        subgraph INS["Namespace: ingress-nginx"]
            IC["Nginx Ingress Controller"]
        end
    end

    DD --> MK
    MK --> Cluster
    IG --> IC
```

---

## 9. Data Flow Diagram

```mermaid
flowchart LR
    U([User]) -->|"Job Description\n+ Priority"| FE[Frontend]
    FE -->|"POST /api/v1/jobs\nJSON body"| GW[API Gateway]
    GW -->|"Forward request"| WC[Workflow Controller]

    WC -->|"INSERT jobs\nshard_key = hash mod 2"| DB[(PostgreSQL\nShard A/B)]
    WC -->|"SET job:status:{id}"| RD[(Redis)]
    WC -->|"JobSubmittedEvent\n{jobId, description}"| KF[[Kafka\njob-submitted]]

    KF -->|"Consume event"| JW[Job Worker]

    JW -->|"POST /api/embed\n{text: description}"| EM[Ollama\nnomic-embed-text]
    EM -->|"float[768]\nembedding vector"| JW

    JW -->|"POST /collections/job-embeddings/points/search\n{vector, limit:1}"| QV[(Qdrant\nVector DB)]

    QV -->|"score ≥ 0.9\nroutingDecision"| JW
    QV -->|"score < 0.9\n(cache miss)"| JW

    JW -->|"Cache MISS only\nPOST /api/generate\n{model: mistral:7b, prompt}"| LLM[Ollama\nMistral 7B]
    LLM -->|"workerType\nreasoning\npriority"| JW

    JW -->|"PUT /collections/job-embeddings/points\nupsert embedding"| QV

    JW -->|"PATCH /api/v1/jobs/{id}/status\n{status: COMPLETED, workerType}"| WC
    WC -->|"UPDATE jobs SET status=COMPLETED"| DB

    FE -->|"GET /api/v1/jobs\nevery 3s poll"| GW
    GW -->|"Forward"| WC
    WC -->|"GET job:status:{id}"| RD
    RD -->|"Cache HIT"| WC
    WC -->|"JobResponse[]"| FE
    FE -->|"Live status update"| U
```

---

## 10. AI Routing Pipeline — Detailed Flow

```mermaid
flowchart TD
    START([Job Event Consumed from Kafka]) --> EMBED

    EMBED["Step 1: Embed\nnomic-embed-text via Ollama\ntext → float[768] vector"]

    EMBED --> EMBED_OK{Embedding\nsucceeded?}
    EMBED_OK -->|No| DEFAULT1["Use default routing\nworkerType=general"]
    EMBED_OK -->|Yes| SEARCH

    SEARCH["Step 2: Vector Search\nQdrant cosine similarity\nTop-1 result"]
    SEARCH --> HIT{Score ≥ 0.9?}

    HIT -->|"YES — Cache HIT\n(~1-2s)"| CACHED["Use cached routingDecision\nSkip LLM entirely"]
    HIT -->|"NO — Cache MISS"| LLM_CALL

    LLM_CALL["Step 3: Ollama LLM\nMistral 7B inference\n(~60-90s on CPU)"]
    LLM_CALL --> LLM_OK{LLM\nsucceeded?}
    LLM_OK -->|No timeout/error| DEFAULT2["defaultDecision()\nworkerType=general"]
    LLM_OK -->|Yes| PARSE["Parse JSON response\n{workerType, estimatedSeconds,\nsuggestedPriority, reasoning}"]

    PARSE --> STORE["Step 4: Store in Qdrant\nupsert(jobId, embedding, routingDecision)\nfor future cache hits"]
    CACHED --> PATCH
    DEFAULT1 --> PATCH
    DEFAULT2 --> PATCH
    STORE --> PATCH

    PATCH["Step 5: PATCH workflow-controller\nPUT /api/v1/jobs/{id}/routing\n{workerType, routingDecision}"]
    PATCH --> EXEC["Step 6: Simulated Execution\nThread.sleep(estimatedSeconds * 100ms)"]
    EXEC --> COMPLETE["Step 7: PATCH COMPLETED\nJob marked as COMPLETED in PostgreSQL\nStatus cached in Redis"]
    COMPLETE --> END([Done])

    style HIT fill:#4CAF50,color:#fff
    style CACHED fill:#2196F3,color:#fff
    style LLM_CALL fill:#FF9800,color:#fff
    style COMPLETE fill:#4CAF50,color:#fff
```

---

## 11. Sharding Logic Diagram

```mermaid
flowchart TD
    JOB["Job UUID\ne.g. a72abdf1-5d11-4c45-93c5-73c13e1c7961"]
    HASH["shardKey = Math.floorMod(id.hashCode(), 2)"]
    JOB --> HASH

    HASH --> SHARD0{shardKey == 0?}
    SHARD0 -->|Yes| DSA["DataSource: Shard-A\npostgres-shard-a-svc:5432\ndatabase: orchestrator"]
    SHARD0 -->|No| DSB["DataSource: Shard-B\npostgres-shard-b-svc:5432\ndatabase: orchestrator"]

    DSA --> QA["SELECT/INSERT\njobs table on Shard-A"]
    DSB --> QB["SELECT/INSERT\njobs table on Shard-B"]

    NOTE["AbstractRoutingDataSource\ndetermines DataSource\nper request thread"]
```

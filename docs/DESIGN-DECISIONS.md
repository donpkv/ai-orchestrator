# Critical Design Decisions

Every significant architectural choice made during this project, with the reasoning behind it and the alternatives that were rejected.

---

## 1. Async AI Routing via Kafka (not synchronous HTTP)

**Decision:** The HTTP `POST /api/v1/jobs` returns immediately with `status=PENDING`. All AI work (embedding, Qdrant search, Ollama LLM) happens asynchronously in `job-worker` after consuming from Kafka.

**Why:** Mistral 7B on CPU takes 60–180 seconds for a cold inference. Holding an HTTP connection open that long would time out browsers, mobile clients, and any API gateway with default timeout settings. The user gets a job ID instantly and polls for completion.

**Alternative rejected:** Synchronous — `workflow-controller` calls Ollama directly during the HTTP request. Rejected because it blocks the Tomcat thread, ties HTTP latency to LLM latency, and makes the system appear broken to the caller.

**Trade-off accepted:** The frontend must poll (`GET /api/v1/jobs/{id}`) to detect completion. Redis cache-aside makes this cheap (no DB hit on repeated polls).

---

## 2. Qdrant as a Routing Decision Cache (not just a vector DB)

**Decision:** Qdrant is used to cache routing decisions keyed by semantic similarity. If a new job description is ≥ 0.9 cosine similarity to a previously seen embedding, reuse the `workerType` from that stored point — skip Mistral 7B entirely.

**Why:** A 35× speedup (7s vs 180s) for semantically similar jobs. Reduces LLM dependency. Makes the system faster and more deterministic over time as the cache warms up.

**Threshold chosen (0.9):** Below 0.9 the semantic match is too loose and may route incorrectly. Above 0.9 is a near-identical job description that safely reuses the previous decision.

**Alternative rejected:** Redis as routing cache with exact string keys. Rejected because two jobs like "Analyze customer churn" and "Run churn analysis on Q4 data" are semantically identical but textually different — only vector similarity catches this.

---

## 3. PostgreSQL Sharding with AbstractRoutingDataSource

**Decision:** Two independent PostgreSQL pods (`shard-a`, `shard-b`). Shard is selected by `Math.floorMod(id.hashCode(), 2)`. Spring's `AbstractRoutingDataSource` routes each JPA call to the correct shard via `ThreadLocal` context.

**Why:** Demonstrates distributed data patterns at scale. Each shard is an independent pod with its own PVC — this is how real horizontal sharding works in production (Vitess, Citus, etc.). Hash-based routing ensures even distribution without a routing table.

**Alternative rejected:** Single PostgreSQL with a `shard_key` column. Rejected because it doesn't actually distribute load — it's just a logical partition on one server. The point is to have two independent data stores.

**Trade-off accepted:** `getAllJobs()` must query both shards and merge results in application code. This is the standard scatter-gather pattern for sharded reads.

---

## 4. REST-based Qdrant Client (not official gRPC client)

**Decision:** All Qdrant calls use `RestTemplate` against the REST API (port 6333), not the official `io.qdrant:qdrant-client` gRPC library.

**Why:** The official Qdrant gRPC client (`io.qdrant:qdrant-client:1.9.1`) caused `ClassNotFoundException` conflicts with Spring Boot's own gRPC/Netty dependencies. Switching to plain REST eliminated all dependency conflicts with zero loss of functionality — all required operations (search, upsert, collection create) are available via REST.

**Alternative rejected:** Official gRPC client. Rejected after confirmed dependency hell — `io.grpc`, `io.netty` version mismatches between the Qdrant client BOM and Spring Boot's BOM.

---

## 5. Job Worker Owns the Full AI Pipeline (not workflow-controller)

**Decision:** `job-worker` contains `EmbeddingService`, `QdrantService`, `OllamaService`. `workflow-controller` does not call Ollama or Qdrant.

**Why:** Clean separation of concerns. `workflow-controller` is the orchestration layer (HTTP API, DB, Redis, Kafka publish). `job-worker` is the execution layer (AI inference, vector search). This lets them scale independently — you could run 3 `job-worker` replicas to handle concurrent AI workloads without touching `workflow-controller`.

**Alternative rejected:** `workflow-controller` calls Ollama during submit. Rejected because it ties the synchronous API to slow AI calls and violates single-responsibility. Also, `workflow-controller` already has enough dependencies (2× PostgreSQL, Redis, Kafka).

---

## 6. Apache HttpClient for RestTemplate (not Java HttpURLConnection)

**Decision:** `job-worker`'s default `RestTemplate` uses `HttpComponentsClientHttpRequestFactory` (Apache HttpClient 5) instead of the default `SimpleClientHttpRequestFactory`.

**Why:** Java's built-in `HttpURLConnection` does not support the `PATCH` HTTP method. `job-worker` calls `PATCH /api/v1/jobs/{id}/status` on `workflow-controller`. Without this fix, every job silently fails with `java.net.ProtocolException: Invalid HTTP method: PATCH`.

**Ollama RestTemplate is separate:** A dedicated `ollamaRestTemplate` bean uses `SimpleClientHttpRequestFactory` with a 180-second read timeout. Ollama calls are only `POST /api/generate` (not PATCH), so the default factory is fine there. The long timeout handles Mistral 7B CPU cold-start (can take 90–180s).

---

## 7. CORS Configured at API Gateway Only

**Decision:** CORS is configured via `spring.cloud.gateway.globalcors` in `api-gateway/application.yml` only. No `@CrossOrigin` annotations on `workflow-controller` or `job-worker`.

**Why:** Internal services (`workflow-controller`, `job-worker`) should never be called directly by browsers — they are only reachable inside the cluster. Putting `@CrossOrigin` on them is both wrong (they have no ingress from outside) and a false security signal. The gateway is the single entry point and owns CORS policy.

**`ALLOWED_ORIGINS` is env-var driven:** Set via ConfigMap so it can be changed per environment without rebuilding the image — `localhost:3000` for local dev, `https://yourdomain.com` for production.

---

## 8. Qdrant Collection Auto-Created by Application (not by init script)

**Decision:** `QdrantService.ensureCollectionExists()` programmatically creates the `job-embeddings` collection on first upsert if it doesn't exist. Vector size is auto-detected from the actual embedding output (768 for `nomic-embed-text` v1).

**Why:** The original `create-collection.sh` script required manual port-forwarding after pod startup. This was error-prone and broke automated deployments. The application self-heals — even after a cluster wipe and redeploy, the collection is recreated automatically on the first job submission.

**Auto-detect dimension:** The `ensureCollectionExists(int vectorSize)` method takes the dimension from the actual embedding, not a hardcoded constant. This means if the Ollama model changes to one with different output dimensions, the collection adapts.

---

## 9. Virtual Threads for HTTP and Kafka

**Decision:** Both `workflow-controller` and `job-worker` use Java 21 Virtual Threads — Tomcat's thread pool replaced with `Executors.newVirtualThreadPerTaskExecutor()`, Kafka listener executor also uses virtual threads.

**Why:** Every job submission involves: 2 PostgreSQL calls (shard lookup), 1 Redis call, 1 Kafka publish, all blocking I/O. With platform threads (default Tomcat pool of ~200), 200 concurrent requests would exhaust the pool and queue. Virtual threads park on I/O without holding an OS thread — theoretically unlimited concurrency for I/O-bound workloads.

**Not used for Ollama calls:** Ollama inference is CPU-bound, not I/O-bound. Virtual threads offer no benefit for CPU-bound work. The benefit is entirely in the blocking database/network calls.

---

## 10. Nginx as Frontend Reverse Proxy (not Vite dev server in production)

**Decision:** The production frontend is a static React build served by Nginx. Nginx proxies `/api/*` to `api-gateway-svc` inside the cluster using the full FQDN (`api-gateway-svc.ai-orchestrator.svc.cluster.local:8080`).

**Why FQDN required:** Nginx's `resolver` directive uses Kubernetes CoreDNS (`10.96.0.10`) but does not use the pod's `/etc/resolv.conf` search domains. Short service names like `api-gateway-svc` fail to resolve from Nginx's `set $upstream` directive. The full FQDN always resolves correctly.

**Why not Vite dev server in production:** Vite's dev server is Node.js — not suitable for serving static files in a container. Nginx is purpose-built for static file serving and reverse proxying, with ~2 MB memory footprint vs Node.js ~30–50 MB.

---

## 11. KRaft Mode for Kafka (no Zookeeper)

**Decision:** Kafka runs in KRaft mode (`KAFKA_CFG_PROCESS_ROLES=broker,controller`), eliminating Zookeeper entirely.

**Why:** KRaft became production-ready in Kafka 3.3+. Zookeeper adds one more pod, one more PVC, one more thing to monitor, and one more dependency to fail. KRaft puts the controller quorum inside Kafka itself. For a single-node local cluster this is strictly simpler.

---

## 12. Multi-Stage Docker Builds with Non-Root User

**Decision:** All Spring Boot Dockerfiles use two stages: `eclipse-temurin:21-jdk-alpine` for Maven build, `eclipse-temurin:21-jre-alpine` for runtime. Runtime containers run as a non-root `appuser`.

**Why multi-stage:** Builder image (~500 MB with JDK + Maven) is discarded. Runtime image (~100 MB with JRE only) is what runs. No Maven, no JDK, no source code in the final image.

**Why non-root:** Container security best practice. If the JVM process is compromised, the attacker cannot write to system directories or escalate privileges.

**JVM flags:** `XX:+UseContainerSupport` makes the JVM read cgroup memory limits (not host RAM). `XX:MaxRAMPercentage=75.0` sets heap to 75% of the container's memory limit — critical for predictable memory usage inside Kubernetes.

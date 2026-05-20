# Phase 3 — End-to-end async routing (HTTP fast path)

## Two-phase job lifecycle

Jobs move through three observable statuses:

1. **PENDING** — Created when `POST /api/v1/jobs` persists the row and publishes to Kafka. The HTTP response returns immediately with this status; `workerType` and `routingDecision` are still unset.

2. **ROUTED** — Set when the job-worker finishes embedding + cache/LLM routing and calls `PATCH /api/v1/jobs/{id}/routing`. PostgreSQL and the Redis status cache are updated together so dashboards can show routing progress between submission and completion.

3. **COMPLETED** — After a short simulated execution window, the worker calls `PATCH /api/v1/jobs/{id}/status` with `COMPLETED`.

If anything fails inside the worker pipeline, errors are logged and the worker still attempts `PATCH .../status` with `COMPLETED` so jobs do not remain stuck in **PENDING** or **ROUTED**.

## Why Ollama runs in the job-worker (Option B)

Ollama calls (embed + generate) are slow and CPU-heavy. Running them inside `workflow-controller` during `submitJob()` would block the HTTP thread until routing finishes. Moving that work **after** Kafka delivery keeps submission latency low: the controller only validates, shards, persists, caches **PENDING**, publishes the event, and returns **201 Created**.

## Qdrant cache hit vs miss

1. **Embed** — The worker calls Ollama’s `/api/embed` with `nomic-embed-text` to produce a vector for the job description.

2. **Search** — That vector is searched in the `job-embeddings` collection. If the top hit’s score is ≥ **0.9** and payload `routingDecision` is present, we treat it as a **cache hit** and reuse the stored label without calling the routing LLM.

3. **Miss** — On miss (or empty embedding), the worker calls **Ollama generate** (`mistral:7b`) for a structured `RoutingDecision`, then **upserts** the embedding into Qdrant with payload `routingDecision` set to the chosen `workerType` so similar jobs later hit the cache.

Cache hits avoid an extra LLM round-trip and stabilize routing for repeated or near-duplicate descriptions.

## Kafka topics (`JobConstants`)

| Topic | Role today |
| ----- | ---------- |
| **job-submitted** | Producer: workflow-controller after insert. Payload JSON: `jobId`, `description`, `priority`, `shardKey`. Consumer: job-worker group runs the full routing + completion pipeline. |
| **job-routed** | Defined for forward-compatible event streaming; **no publisher wired yet**. Routing results are conveyed via REST `PATCH .../routing`. |
| **job-completed** | Defined for completion notifications; **no publisher wired yet**. Completion is conveyed via REST `PATCH .../status`. |

## Sequence: `POST /api/v1/jobs` → **COMPLETED**

Illustrative timings (actual embed/LLM latency dominates on cache miss):

| Time | Component | Action |
| ---- | --------- | ------ |
| **T0** | Client | `POST /api/v1/jobs` |
| **T0 + ms** | workflow-controller | UUID, shard, insert job (**PENDING**), Redis cache status, publish **job-submitted**, return **201** |
| **T1** | Kafka | Message delivered to job-worker |
| **T1 …** | job-worker | Embed description → Qdrant search |
| **T2a** | job-worker (hit) | Build routing metadata from cache; skip LLM |
| **T2b** | job-worker (miss) | Ollama route → store vector + worker type in Qdrant |
| **T3** | job-worker → controller | `PATCH /api/v1/jobs/{id}/routing` → DB + Redis **ROUTED** |
| **T4** | job-worker | `Thread.sleep(2000)` (simulated work) |
| **T5** | job-worker → controller | `PATCH /api/v1/jobs/{id}/status` `{ "status": "COMPLETED" }` |

Together, this splits **fast acknowledgement** (HTTP) from **heavy AI work** (async worker), with **ROUTED** exposing intermediate progress for operators and UIs.

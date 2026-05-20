# Phase 1: PostgreSQL Sharding Overview

This document summarizes how Phase 1 uses two PostgreSQL 16 shards in Kubernetes and how the orchestrator assigns work between them.

## What is database sharding?

**Sharding** partitions data across multiple databases so each shard holds only a subset of rows. Instead of storing every job in a single monolithic database, rows are routed to shard A or shard B by a deterministic rule (here, hashing the job id). Scaling and failure isolation improve because each shard has its own storage, process, and connection pool—at the cost of more operational complexity (two clusters to back up, monitor, and migrate).

## Why two separate PostgreSQL pods instead of one?

A **single PostgreSQL instance** is simpler but becomes a single bottleneck and a single point of failure for both capacity and outages. **Two pods** give you:

- **Horizontal headroom**: each shard can be sized and scaled independently as load grows.
- **Blast radius**: problems on one shard (slow disk, bad query, restart) affect only half of the key space under this design.
- **Clear mapping to routing**: the application (or a router layer) always knows “this id goes to shard A or B,” which matches how you will deploy and observe them in Kubernetes.

This is a **logical** split (two databases, same schema), not yet a full distributed SQL system; cross-shard transactions and global queries need explicit design.

## Routing: `hash(job_id) % 2`

Each job has a UUID primary key `id` (the “job id”). To pick a shard:

1. Compute a stable hash of the job id (for example a 32-bit or 64-bit hash; the important part is **same id → same hash every time**).
2. Take `hash(job_id) % 2`. The result is **0** or **1**.
3. **Remainder 0** → **shard A** (`postgres-shard-a-svc` in namespace `ai-orchestrator`).
4. **Remainder 1** → **shard B** (`postgres-shard-b-svc`).

This spreads ids pseudo-randomly across shards when the hash is well behaved, without a central registry of which id lives where.

## Verifying after you apply the manifests

1. **Check pods** in the `ai-orchestrator` namespace:

   ```bash
   kubectl get pods -n ai-orchestrator
   ```

   You should see the PostgreSQL shard pods reach `Running` and `READY` once the readiness probe on port 5432 succeeds.

2. **Open a shell in a shard pod** and use `psql` (replace pod name with the actual name from `kubectl get pods`):

   ```bash
   kubectl exec -it -n ai-orchestrator <postgres-shard-a-pod-name> -- psql -U admin -d orchestrator
   ```

   For shard B, use a pod from the `postgres-shard-b` deployment instead.

3. Inside `psql`, you can list tables (after running your init SQL), e.g. `\dt`, and inspect the `jobs` table schema.

Repeat for the other shard to confirm both databases are reachable independently.

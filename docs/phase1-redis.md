# Phase 1: Redis

This document describes how Redis is deployed for Phase 1 and why the chosen settings fit the local AI orchestrator.

## What Redis is used for in this project

Redis backs **fast, ephemeral data** that does not need PostgreSQL durability guarantees:

- **Job status caching**: recent job state can be read from memory to avoid hammering shards or repeating expensive lookups while work is in flight.
- **Rate limiting**: counters or token buckets in Redis throttle API or worker traffic without introducing heavy contention on the primary databases.

PostgreSQL remains the source of truth for durable job records; Redis is an acceleration and coordination layer.

## Memory limits and eviction policy

The manifest caps Redis at **256mb** via `maxmemory` and sets **`maxmemory-policy allkeys-lru`**.

When Redis reaches that limit, it must evict keys. **allkeys-lru** drops the **least recently used** keys from **any** key type, not only keys with an explicit TTL. That matches cached job status and rate-limit entries: they can be reconstructed or refetched if evicted, and keeping “hot” keys in memory while shedding cold ones is usually preferable to rejecting writes or requiring every key to have a TTL. Policies that only evict keys with TTL or refuse writes would be a poorer fit if some entries are long-lived without TTL but still safe to drop under pressure.

Persistence for this role is intentionally light: `save ""` disables RDB snapshots so the pod behaves as a **cache / ephemeral store**—consistent with repopulating cache and limits after a restart.

## Verify after applying the manifest

Apply `k8s/infra/redis/redis.yaml`, then confirm the instance responds:

```bash
kubectl exec -it <redis-pod> -n ai-orchestrator -- redis-cli ping
```

You should see `PONG` when the pod is healthy and reachable.

## Inspect cached keys

From inside the pod (or via `kubectl exec` as above), list keys matching a pattern:

```bash
redis-cli keys '*'
```

**Note:** `KEYS` is convenient for small dev clusters but scans the whole keyspace and can block Redis under heavy load. For production exploration, prefer `SCAN` with a cursor instead of `KEYS`.

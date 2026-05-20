# Phase 2: Redis cache-aside for job status

## What is cache-aside?

In the **cache-aside** pattern, the application treats Redis as a side cache next to PostgreSQL:

1. On a **read**, the service **checks Redis first**. If a value is present (a **hit**), it uses that value.
2. On a **miss** (no key or Redis unavailable), it **loads from PostgreSQL**, returns the result, and **writes the loaded value into Redis** so later reads can hit the cache.

Writes still go to PostgreSQL first; the cache is updated after a successful save so it tracks the authoritative state. This module caches only the **status string** for each job under keys `job:status:<jobId>` with a **5 minute TTL**.

## Why a 5 minute TTL?

A five-minute expiry balances **freshness** with **load reduction**. Status can change as workers progress, so an unbounded cache would serve stale values for too long. A short TTL ensures entries eventually realign with the database without requiring complex invalidation for every edge case, while still cutting repeated read traffic to PostgreSQL for hot keys.

## Why cache only the status string?

Storing a **plain string** (the status) instead of serializing the full `Job` object:

- **Uses less memory** in Redis (one small value per job vs. a larger JSON blob).
- **Avoids** Deserialize/serialize cost and schema drift for cached aggregates.
- Other fields (description, priority, shard, timestamps) stay **always loaded from the correct shard** on `GET /jobs/{id}`, with only the status taken from cache when present.

## How to verify in Kubernetes

1. Identify the Redis pod (for example via your Deployment or StatefulSet for `redis-svc`).
2. Exec into the pod and run Redis CLI:

   ```bash
   kubectl exec -it <redis-pod-name> -- redis-cli KEYS '*'
   ```

   You should see keys like `job:status:<uuid>` after jobs are created or read through the API.

## When Redis is down

Redis is wrapped as a **best-effort** layer: reads catch connection errors and behave like a **cache miss**, so the service still loads from PostgreSQL. Writes to Redis after DB updates are skipped on failure. **Job flows continue to work** with PostgreSQL as the source of truth; only cache acceleration and cross-instance status hints are lost until Redis is healthy again.

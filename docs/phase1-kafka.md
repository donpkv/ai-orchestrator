# Phase 1: Apache Kafka (KRaft)

This document describes how Kafka is deployed for local development and how it fits the AI orchestrator workflow.

## KRaft mode (no Zookeeper)

**KRaft** (Kafka Raft) is the metadata management mode introduced to replace Zookeeper. The Kafka brokers (and designated controller nodes) use an internal **Raft** quorum to store cluster metadata—topics, partitions, brokers, and configuration—instead of delegating that role to a separate Zookeeper ensemble.

For a local Minikube setup, KRaft **removes an extra moving part**: you do not provision, secure, or upgrade Zookeeper alongside Kafka. A single combined `broker,controller` process (as in this manifest) is enough to learn and test the event bus, which keeps manifests smaller and startup simpler while matching the project’s Kafka **3.7 (KRaft)** target.

Operational note: KRaft is the long-term direction for Kafka; Zookeeper mode is legacy for new deployments.

## Topics and workflow payloads

The job manifest creates three topics, each with **3 partitions** and **replication factor 1** (appropriate for a one-broker dev cluster).

| Topic | Role in the workflow |
| --- | --- |
| **job-submitted** | Emitted when the workflow controller accepts a new user job (for example after `POST /api/v1/jobs`). Carries the **submission event**: job identity, raw natural-language description, and request metadata needed for embeddings and routing. |
| **job-routed** | Emitted after the controller decides **how** work should run—whether routing came from Qdrant similarity, the LLM decomposition, or a fallback. Carries the **routing plan**: target shard/worker hints, sub-task breakdown, and correlation IDs so workers consume the right work. |
| **job-completed** | Emitted when execution reaches a terminal success (or structured failure) state. Carries the **outcome event**: final status, result summaries, timing, and pointers for cache or DB updates so the API and dashboard stay consistent. |

Together these topics form a simple **submit → route → complete** narrative over Kafka, decoupling the Spring controller from worker pods.

## Deploy order

1. Apply `k8s/infra/kafka/kafka.yaml` and wait until the `kafka-0` pod is **Ready**.
2. Apply `k8s/infra/kafka/create-topics.yaml`. The Job waits for the broker, then runs `kafka-topics.sh` for each topic.

Re-running the Job is safe: `--if-not-exists` avoids errors if topics are already present.

## Manual test: console producer and consumer

Replace `<kafka-pod>` with the pod name (typically `kafka-0`).

**Producer** (type a few lines; end with Ctrl+D on Unix or Ctrl+Z then Enter on Windows shells when using `kubectl exec -it`):

```bash
kubectl exec -it <kafka-pod> -n ai-orchestrator -- kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic job-submitted
```

**Consumer** (from another terminal):

```bash
kubectl exec -it <kafka-pod> -n ai-orchestrator -- kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic job-submitted \
  --from-beginning
```

You should see the lines you typed appear on the consumer. Repeat with `job-routed` or `job-completed` to verify those topics.

**List topics** after the Job completes:

```bash
kubectl exec -it <kafka-pod> -n ai-orchestrator -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list
```

From application pods in the same namespace, use bootstrap server **`kafka-svc:9092`** (or the full DNS name `kafka-svc.ai-orchestrator.svc.cluster.local:9092`) instead of `localhost`.

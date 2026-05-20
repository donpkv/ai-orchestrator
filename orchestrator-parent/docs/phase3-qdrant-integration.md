# Phase 3: Qdrant vector similarity for job routing

## What vector similarity search does here

Each job description is turned into a **dense vector** (a fixed-length array of floats). Qdrant stores those vectors for past jobs together with a small **payload** (metadata), including the **`routingDecision`** that was chosen when that job ran. For a new job, we embed the new text and ask Qdrant for the **nearest neighbor** among stored vectors. Geometrically, “nearest” means the stored job whose vector is closest in angle/distance—i.e. the **most semantically similar** past job, not identical string matching.

## Why the score cutoff is **0.9**

Search returns a **similarity score** for the closest point (depending on configured distance metric, commonly cosine-related on normalized embeddings). Values near **1.0** indicate very aligned meaning; lower values mean the closest stored job is still a weak match.

We treat **`score >= 0.9`** as “similar enough to reuse that job’s routing.” Below **0.9**, we assume the cache would mis-route or hallucinate continuity from an unrelated job, so the system should **call the LLM** (or another primary router) instead of trusting Qdrant.

## What **`nomic-embed-text`** does

**`nomic-embed-text`** is an embedding model served by Ollama. It maps arbitrary text into a **single 384-dimensional float vector** so that semantic content is captured numerically: paraphrases and similar intents land near each other in vector space. That vector is what Qdrant indexes and compares. Deployments must configure the **`job-embeddings`** collection vector size (and metric) to match this model.

## gRPC **6334** vs REST **6333**

Qdrant exposes two main wire protocols:

- **REST/HTTP** is typically on port **6333** (JSON over HTTP, easy to curl and debug).
- **gRPC** is typically on port **6334** (binary, efficient; the official Java client uses this channel).

This service configures the Java **`QdrantClient`** against the **gRPC** port so the controller can use the generated async client without an extra HTTP adapter.

## How this reduces LLM calls (routing cache)

1. **First time** a kind of job appears: there is no strong neighbor in Qdrant (or score is low). The controller runs the **LLM** (or full routing pipeline), gets a **`routingDecision`**, completes the job path, and **stores** the text embedding plus that decision in Qdrant under the job id.
2. **Later**, a **semantically similar** job arrives: embedding + search returns a hit above **0.9**, so the controller **reuses `routingDecision`** from the payload and **skips the LLM** for that routing step.

The vector store therefore acts as a **semantic cache** keyed by meaning rather than by exact text.

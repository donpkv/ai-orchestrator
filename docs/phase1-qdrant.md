# Phase 1: Qdrant (vector database)

This document explains what Qdrant provides for Phase 1, how it differs from PostgreSQL in this stack, and how to exercise it locally over `kubectl port-forward`.

## Vector database versus a relational database

A **relational database** (such as PostgreSQL) stores rows in tables with fixed schemas, keys, and transactional guarantees. You query primarily with predicates on columns (`WHERE`, joins, indexes on discrete values). It excels at enforcing structure, ACID semantics, and reporting over structured attributes.

A **vector database** stores **high-dimensional vectors** (embeddings) and metadata, optimized for **approximate nearest-neighbor search**: given a query vector, return the stored vectors that are *most similar* under a chosen geometry. It is not a replacement for a relational DB for inventory, billing, or job lifecycle tables; it complements them when the core operation is **similarity in embedding space**, not equality on scalar keys.

In this orchestrator, PostgreSQL (or other relational stores) remain suited to durable job records and relational constraints; Qdrant holds **semantic search payloads** (e.g. job descriptions encoded as vectors) where “close in meaning” is the retrieval criterion.

## What embeddings are

**Embeddings** are **dense numerical vectors** produced by a model (often a transformer) from text, images, or other inputs. Semantically similar inputs tend to land **near each other** in that vector space after training, so geometric distance or angle between vectors proxies **semantic similarity**. Each dimension is a learned feature, not a human-labeled column; the model maps raw content into a fixed-length array you can index and search.

## Why vector size 384

The collection `job-embeddings` is defined with **vector size 384** to align with models such as **`sentence-transformers/all-MiniLM-L6-v2`**, which outputs **384-dimensional** embeddings. Qdrant requires every stored vector in a collection to match the configured size; mismatching dimensions will cause ingest or search errors. Keeping the collection dimension equal to your encoder’s output avoids silent padding mistakes and keeps indexes efficient.

## How similarity search works (Cosine distance)

Qdrant’s **Cosine** metric measures **angular similarity** between vectors (related to the cosine of the angle between them). Vectors pointing in a similar direction—regardless of magnitude—score as more alike. For normalized embedding models, cosine distance often tracks **semantic nearness** well. At query time, you send a query vector; Qdrant returns identifiers of stored points ranked by **lowest cosine distance** (highest cosine similarity) to that query, optionally filtered by payload metadata.

## Port-forward and smoke test

1. Apply the manifest (from the repo root, when you are ready to use a cluster):

   ```bash
   kubectl apply -f k8s/infra/qdrant/qdrant.yaml
   ```

2. Forward the REST port to your machine:

   ```bash
   kubectl port-forward svc/qdrant-svc 6333:6333 -n ai-orchestrator
   ```

3. In another terminal, create and verify the `job-embeddings` collection:

   ```bash
   ./k8s/infra/qdrant/create-collection.sh
   ```

   The script creates the collection with the PUT payload, then GETs `http://localhost:6333/collections/job-embeddings` so you can confirm the API sees the collection.

For gRPC clients, forward **6334** the same way (`6334:6334`) if you need the gRPC endpoint locally.

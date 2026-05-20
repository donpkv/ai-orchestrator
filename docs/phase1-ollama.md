# Phase 1: Ollama in Kubernetes

## What Ollama is

[Ollama](https://ollama.com/) is a **local LLM runtime**: it downloads, loads, and serves large language models on your own machines (CPU or GPU) behind a simple HTTP API. You interact with models through REST endpoints instead of relying on hosted cloud inference, which keeps payloads on-cluster and avoids per-token cloud bills during development and routing workflows.

## Why `mistral:7b`

We use **`mistral:7b`** as the default routing model because it offers a practical **balance between response quality and speed** on commodity hardware. A 7B-parameter model typically **fits comfortably in about 8GB RAM** (with quantization and runtime overhead accounted for), so it is workable on smaller nodes while still producing structured-enough outputs for routing and classification-style tasks.

## Why we persist `/root/.ollama`

Ollama stores **downloaded model weights and related cache data** under `/root/.ollama`. Without a persistent volume, **each new pod restart would start with an empty directory** and re-download sizable artifacts (for `mistral:7b`, on the order of **roughly ~4GB** depending on quantization and versioning). Mounting a **PersistentVolumeClaim** at `/root/.ollama` **retains weights across restarts**, so pods come up quickly after the initial pull.

## Role of Ollama in this project

In **local-ai-orchestrator**, Ollama is the **inference backend** that receives natural-language **job descriptions** (for example, what the user wants to run or automate) and is expected to return **JSON-shaped routing decisions**—which agent, queue, tool, or next step should handle the work. Application code wraps those HTTP calls so orchestration stays deterministic and testable while the model fills in intent and structure.

## Expected response time

For **routing-style prompts** over the HTTP API on **CPU-only** nodes, expect roughly **about 2–5 seconds per call**, depending on node size, load, quantization, concurrent traffic, and prompt length. GPU-backed nodes typically reduce latency for the same workload.

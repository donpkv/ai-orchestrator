# Phase 3: Ollama Mistral routing (job classification)

The workflow-controller calls **Ollama’s `/api/generate` endpoint** with the **`mistral:7b`** model to classify each new job submission. The model returns structured JSON describing which **worker type** should handle the work, **how long it might take**, and a **suggested priority**.

## Prompt: JSON-only output

The system prompt tells Mistral that it is a **job routing system** and that it must **respond only with valid JSON**, with **no explanation text and no Markdown**. That avoids preamble or fenced code blocks (“Here is the JSON…”), keeps token noise low, and makes parsing predictable: the HTTP response body’s `response` field should contain a single JSON object we can deserialize into `RoutingDecision`.

## Why `stream: false`

With **`stream: false`**, Ollama returns **one complete JSON document** after generation finishes. The controller can read the **`response`** string once and parse it. With streaming enabled, the client would receive **incremental chunks** and would need to buffer and reassemble the model output manually.

## Why a **30-second read** timeout (`ollamaRestTemplate`)

**Mistral 7B** on CPU often finishes routing in roughly **a few seconds**, but latency can **spike** under load or cold caches. **30 seconds** of read timeout is a conservative margin so legitimate generations do not fail while still bounding how long **`submitJob`** blocks waiting for routing.

Connection timeout is set to **5 seconds** so misconfigured URLs fail fast instead of hanging the submit path indefinitely.

The dedicated **`ollamaRestTemplate`** bean carries these timeouts. The existing default **`RestTemplate`** bean (marked **`@Primary`**) stays **without** bespoke timeouts so Redis, Qdrant, and embedding calls behave as before.

## Worker types and typical job mappings

| `workerType` | Typical jobs |
|--------------|----------------|
| **data-processing** | ETL, batch transforms, file parsing, indexing large datasets |
| **notification** | Email/SMS/webhook/alerts triggered by events |
| **deployment** | Releases, infra rollouts, CI/CD orchestration hooks |
| **analysis** | Reports, diagnostics, anomaly checks, exploratory analytics |
| **general** | Anything that does not cleanly fit above, or when the router is unsure |

Exact assignment is ultimately the model’s choice within that constrained vocabulary.

## When the LLM path fails (`defaultDecision()`)

On **timeouts**, transport errors, **model not loaded**, empty bodies, or **JSON parse failures**, `OllamaService.route` logs a **warning** and returns **`RoutingDecision.defaultDecision()`**:

- `workerType`: `"general"`
- `estimatedSeconds`: `30`
- `suggestedPriority`: `5`
- `reasoning`: `"default routing"`

The job is still **persisted and published**: routing never prevents submission.

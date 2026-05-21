# Development Process: Agentic Workflow, Rules, Skills & Token Cost Management

This document explains how the development of this project was structured using Cursor's agentic features — not just how the code was written, but how the *development environment itself* was engineered to be efficient, consistent, and low-cost.

---

## Overview

The entire project was built using **Cursor Agent** — an AI coding assistant that can plan, write, execute terminal commands, read files, and iterate autonomously within a defined workspace.

Rather than treating the agent as a simple code-completion tool, the development process was designed around three pillars:

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Structured Work** | `subtasks.json` | Break the project into small, atomic, self-contained tasks |
| **Persistent Guidance** | `.cursor/rules/` (`.mdc` files) | Give the agent standing instructions it applies to every session |
| **Cost Control** | Chat summaries, small subtasks, focused context | Minimize token usage without losing continuity |

---

## 1. Agentic Flows: `subtasks.json`

### What It Is

`subtasks.json` is a hand-maintained JSON registry at the root of the project. Every piece of work — from setting up Minikube to writing the frontend — is broken into a numbered subtask entry:

```json
{
  "id": "2.1",
  "phase": "app",
  "title": "Workflow Controller – Job Submission API",
  "status": "done",
  "agentId": "agent-xxxx-...",
  "lastRunAt": "2026-05-16T...",
  "prompt": "You are working inside the folder: ...\n\nTask: ..."
}
```

### Why This Pattern

Each subtask has a **self-contained prompt** that gives the agent:
- The absolute workspace path
- A single, focused objective
- Exact file names to create or modify
- No ambiguity about what "done" means

This means a fresh agent invocation (with zero prior chat context) can pick up any subtask, execute it correctly, and complete it — without needing to re-read the entire project history.

### Subtask Lifecycle

```
PLANNED → IN PROGRESS → done
                  ↓
           (agent runs, files created)
                  ↓
         agentId + lastRunAt recorded
```

Each subtask is assigned a unique `agentId` after execution. This creates an audit trail: if a piece of code behaves unexpectedly, you can trace it back to the exact agent run that generated it.

### Coverage

The `subtasks.json` covers all 5 completed phases plus 4 planned future phases:

| Phase | Subtasks | Status |
|-------|----------|--------|
| Phase 1 – Infrastructure (Minikube, PostgreSQL, Redis, Kafka, Qdrant, Ollama) | 1.1–1.6 | Done |
| Phase 2 – Application Services (Controller, Worker, Gateway) | 2.1–2.4 | Done |
| Phase 3 – Integration & Smoke Tests | 3.1–3.2 | Done |
| Phase 4 – AI Pipeline (embeddings, Qdrant cache, Mistral routing) | 4.1–4.3 | Done |
| Phase 5 – Frontend (React, Ingress, UI polish) | 5.1–5.3 | Done |
| Phase 6 – Observability (Prometheus, Grafana, Jaeger, Loki) | 6.1–6.4 | Planned |
| Phase 6b – RAG Ingestion Service | 6b.1–6b.2 | Planned |
| Phase 7 – Security (Keycloak, JWT, RBAC) | 7.1–7.3 | Planned |
| Phase 8 – Kafka Security (TLS, SASL, ACLs, NetworkPolicy) | 8.1–8.3 | Planned |
| Phase 9 – CI/CD (GitHub Actions, GHCR) | 9.1–9.2 | Planned |

---

## 2. Persistent Rules: `.cursor/rules/`

Cursor rules are Markdown files (`.mdc` extension) stored in `.cursor/rules/`. When `alwaysApply: true` is set in the frontmatter, the rule is automatically injected into the agent's context at the start of every session — without the developer having to re-explain the same standards each time.

### Rule: `new-pod-checklist.mdc`

**Location:** `.cursor/rules/new-pod-checklist.mdc`

**What it does:** Defines a comprehensive integration checklist that the agent must follow every time a new pod or microservice is added to the cluster. The checklist covers:

1. **Kubernetes Manifests** — Deployment, Service, ConfigMap, resource limits, health probes
2. **Observability** — Prometheus scrape config, OTel auto-instrumentation, Grafana panels
3. **Security** — Route through API Gateway, JWT header forwarding, CORS ConfigMap
4. **Kafka** — NetworkPolicy update, ACL entries, SASL credentials
5. **Scripts** — `setup-cluster.ps1`, `deploy-apps.ps1`, `safe-shutdown.ps1` updates
6. **Documentation** — `PROJECT.md`, `README.md`, architecture diagrams, `subtasks.json`
7. **Memory Budget** — Verifying headroom in the 18 Gi Minikube allocation

**Why this matters:** Without this rule, it would be easy to deploy a new service that is missing health probes, has no resource limits, is not scraped by Prometheus, or is not documented. The rule enforces consistency automatically.

```markdown
---
description: Checklist for integrating new pods into ai-orchestrator
alwaysApply: true
---
```

### How to Add More Rules

Place any `.mdc` file in `.cursor/rules/`. The frontmatter controls scope:

```markdown
---
description: Short description shown in the rules list
alwaysApply: true        # inject into every session
# globs: ["**/*.java"]  # OR: only when editing Java files
---
```

Rules can encode any project convention: naming standards, commit message formats, which framework patterns to prefer, what to check before marking a task done, etc.

---

## 3. Cursor Skills

Cursor Skills are reusable prompt templates stored at `~/.cursor/skills/` (user-level, not project-level). They provide the agent with domain-specific playbooks for complex, recurring tasks.

### Skills Used in This Project

| Skill | Purpose |
|-------|---------|
| **canvas** | Render rich analytical artifacts (tables, charts, architecture reviews) as live React canvases in the IDE rather than plain markdown |
| **create-rule** | Guided workflow for authoring `.cursor/rules/` `.mdc` files with correct frontmatter and structure |
| **update-cursor-settings** | Modify `settings.json` without manually hunting through the IDE settings UI |
| **split-to-prs** | Split a large set of changes into small, reviewable pull requests |
| **babysit** | Keep a PR merge-ready by triaging review comments and fixing CI in a loop |

### How Skills Differ from Rules

| | Rules | Skills |
|---|---|---|
| **Scope** | Project-specific, lives in repo | User-level, available across all projects |
| **Trigger** | Auto-applied (alwaysApply) or file-glob matched | Manually invoked by reading the skill file |
| **Content** | Standing instructions / checklists | Step-by-step playbooks for a specific workflow |
| **Persistence** | Committed to git | Stored in `~/.cursor/skills/` |

---

## 4. Token Cost Management

LLM API calls are priced per token. A large project like this — with hundreds of files, Kubernetes manifests, Java services, and documentation — can easily consume millions of tokens per session if not managed carefully. The following strategies were used to keep costs under control.

### 4.1 Small, Focused Subtasks

Each subtask prompt is scoped to a **single concern** (one service, one manifest set, one doc file). This means:
- The agent reads only the files it needs for that task
- Context windows stay small
- There are no wasted tokens re-reading irrelevant parts of the codebase

A monolithic prompt like "Build the entire backend" would force the agent to load everything at once and produce unpredictable results. Subtask decomposition keeps each invocation cheap and correct.

### 4.2 Chat Summaries Instead of Full Transcripts

Long conversations accumulate thousands of tokens of history. Instead of replaying the entire chat, periodic **conversation summaries** were generated at natural checkpoints (end of a phase, after a major fix). These summaries:
- Capture decisions, file changes, and error resolutions in compact form
- Replace the raw chat history as the context seed for new sessions
- Are stored in the agent transcript system for reference

The summary at the start of each new chat is typically ~2,000–5,000 tokens, versus the raw chat history which could be 50,000+ tokens for the same information.

### 4.3 Targeted File Reads

Rather than asking the agent to "look at the project," specific file paths were referenced in prompts:
- `subtasks.json` — for current task state
- `k8s/app/<service>.yaml` — for manifest fixes
- `src/main/java/.../<Class>.java` — for code fixes

This prevents the agent from scanning the entire workspace when only one or two files are relevant.

### 4.4 Ask/Plan Mode for Design Decisions

Cursor's **Ask Mode** (read-only) and **Plan Mode** were used for:
- Architecture discussions (no file writes, no tool calls, pure reasoning)
- Deciding between options before committing to an implementation
- Understanding error logs and diagnosing root causes

Switching to Ask/Plan mode for these conversations avoids the overhead of agentic tool calls (each tool call — read file, run command, write file — costs additional tokens in reasoning and response).

### 4.5 Incremental Documentation

Documentation was written **incrementally as features were built**, not retroactively in one large pass. Each phase's doc file (`docs/phase1-setup.md`, `docs/phase1-kafka.md`, etc.) was created as part of the subtask that built the feature. This means:
- The agent already has the feature context fresh in its window
- No need to re-read source code later just to document it
- Docs stay accurate because they are written at implementation time

### 4.6 Reusing Context via `agentId`

Every completed subtask stores the `agentId` that executed it. If a bug is found in a feature later, the relevant agent run can be referenced directly, allowing the debugging session to start with precise context rather than a broad search.

---

## 5. The Control Node Pattern

The main chat (this conversation) functions as a **control node** — it does not do the heavy implementation work itself. Instead, it:

1. **Plans** — breaks work into subtasks, identifies dependencies, orders execution
2. **Delegates** — each subtask is executed by a focused agent invocation with a precise prompt
3. **Verifies** — smoke tests, log checks, and status confirmations happen here
4. **Explains** — architectural concepts, design decisions, and trade-offs are discussed here
5. **Documents** — the living documentation (`PROJECT.md`, `DIAGRAMS.md`, this file) is maintained here

This separation of concerns keeps the control node's context clean and focused on high-level coordination, while the worker agents stay cheap and task-focused.

```
Control Node (main chat)
    │
    ├── Plan phases + subtasks
    ├── Verify deploys + smoke tests
    ├── Explain concepts
    └── Maintain living documentation
              │
              ├── Subtask Agent 1.1  (Minikube setup)
              ├── Subtask Agent 1.2  (PostgreSQL shards)
              ├── Subtask Agent 2.1  (workflow-controller)
              ├── Subtask Agent 4.2  (AI pipeline)
              └── ...
```

---

## 6. Workspace-Level Configuration Summary

| File / Folder | Role |
|---------------|------|
| `subtasks.json` | Registry of all planned, in-progress, and completed work |
| `.cursor/rules/new-pod-checklist.mdc` | Auto-injected integration checklist for new microservices |
| `docs/PROJECT.md` | Living spec: architecture, phases, tech decisions |
| `docs/DESIGN-DECISIONS.md` | Why we made key architectural choices |
| `docs/TROUBLESHOOTING-LOG.md` | What broke and how we fixed it |
| `docs/ARCHITECTURE-HLD-LLD.md` | High-Level and Low-Level design detail |
| `docs/FUTURE-IMPROVEMENTS.md` | Tiered roadmap for future phases |
| `docs/diagrams/` | Mermaid source + rendered PNGs for all 11 architecture diagrams |
| `scripts/` | Fully automated PowerShell scripts for cluster lifecycle |

---

## 7. Lessons Learned

- **Small prompts win.** A 200-line focused prompt produces better results than a 2,000-line omnibus one, and costs a fraction of the tokens.
- **Rules are force multipliers.** Writing the integration checklist once as a rule saves re-explaining the same requirements across every new pod session.
- **Summaries are cheap memory.** A well-written 3,000-token summary replaces 60,000 tokens of raw history with no loss of actionable context.
- **Ask mode is free exploration.** Design discussions in Ask/Plan mode cost almost nothing compared to agentic implementation runs — use it liberally before committing to an approach.
- **Document as you go.** Retroactive documentation requires the agent to re-read all source files. Writing docs during the implementation subtask adds almost no extra cost.
- **Every error is a rule candidate.** If the same mistake (wrong probe timeout, missing resource limits, wrong FQDN) keeps happening, encode the fix as a standing rule rather than fixing it again later.

# Orchestrator Dashboard

Minimal React + TypeScript + Tailwind UI for submitting jobs and watching them flow through the AI Orchestrator pipeline.

## Stack

- **React 18** + **TypeScript** + **Vite** (fast HMR)
- **Tailwind CSS** for styling (no UI library bloat)
- Zero state-management library — `useState` + polling is enough

## Architecture

```
JobForm  ──POST /api/v1/jobs──>  api-gateway (NodePort 30080)
                                       │
                                       ▼
                              workflow-controller
                                       │
                              ┌────────┴────────┐
                              ▼                 ▼
                     PostgreSQL (sharded)    Kafka
                                                │
                                                ▼
                                           job-worker
                                                │
                                  ┌─────────────┴─────────────┐
                                  ▼                           ▼
                              Qdrant cache check      Mistral 7B (on miss)

JobTable  <──GET /api/v1/jobs every 3s──  api-gateway
```

## Local dev

```bash
cd frontend
npm install
npm run dev        # http://localhost:3000
```

Vite proxies `/api/*` to `http://localhost:30080` by default (the api-gateway NodePort exposed by Minikube). Override with:

```bash
VITE_API_TARGET=http://192.168.49.2:30080 npm run dev
```

## Production build

```bash
npm run build      # output: dist/
npm run preview    # serve dist on http://localhost:4173
```

## Features

- **Live job stats** — pending / routed / completed counts
- **Natural-language job submission** — with sample prompts
- **Priority slider** — 1 (low) to 10 (urgent)
- **Auto-refreshing table** — polls every 3s, sorted newest first
- **Expandable rows** — show job UUID, shard, routing decision JSON
- **Status badges** with live pulse animation on in-flight states

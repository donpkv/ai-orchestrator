#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-orchestrator}"
LOCAL_PORT="${LOCAL_PORT:-11434}"

kubectl port-forward -n "$NAMESPACE" "svc/ollama-svc" "${LOCAL_PORT}:11434" &
PF_PID=$!
cleanup() {
  kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "Waiting for Ollama at http://localhost:${LOCAL_PORT} ..."
for _ in $(seq 1 60); do
  if curl -sf "http://localhost:${LOCAL_PORT}/api/tags" >/dev/null; then
    break
  fi
  sleep 1
done

echo "Pulling mistral:7b ..."
curl -sS "http://localhost:${LOCAL_PORT}/api/pull" \
  -d '{"name":"mistral:7b"}'

echo
echo "Testing generate with a short prompt ..."
curl -sS "http://localhost:${LOCAL_PORT}/api/generate" \
  -d '{"model":"mistral:7b","prompt":"Say hello in one word","stream":false}'

echo

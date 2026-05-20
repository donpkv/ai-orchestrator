# Phase 4: Kubernetes manifests for Spring Boot apps

This phase adds three Deployments (`api-gateway`, `workflow-controller`, `job-worker`) in the `ai-orchestrator` namespace so they run next to Phase 1 infrastructure (PostgreSQL shards, Redis, Kafka, Qdrant, Ollama).

## Why `imagePullPolicy: Never`?

Images are tagged `local-ai/api-gateway:latest`, `local-ai/workflow-controller:latest`, and `local-ai/job-worker:latest`. They are built on your machine and loaded into Minikube with `minikube image load`; they are not published to a registry the cluster can pull from.

If Kubernetes tried to pull those names from the default registry, the pull would typically fail or pull the wrong image. `Never` tells the kubelet to use only the image already present in the node’s local image cache.

## ConfigMaps versus hard-coded env vars in the Deployment

A ConfigMap holds non-secret configuration (and sometimes low-sensitivity literals) as key–value pairs. The Pod references it with `envFrom.configMapRef` so variables appear as container environment variables.

Using a ConfigMap instead of repeating `env:` blocks inside every Deployment keeps configuration in one place, makes diffs clearer, lets you iterate on settings without rewriting the Deployment’s pod template, and matches how teams often promote the same manifests across clusters by swapping ConfigMap data.

**Note:** The workflow-controller ConfigMap includes `DB_PASSWORD` for local Minikube convenience. For production you would inject secrets via a Kubernetes `Secret` or an external secrets operator, not a ConfigMap.

## Why does workflow-controller get more memory than api-gateway?

The API gateway is primarily an edge HTTP routing layer with lighter baseline usage. The workflow-controller connects to two PostgreSQL shards, Redis, Kafka, Qdrant, and Ollama, coordinates workflow state, and runs application logic — so it tends to use more heap, buffers, and client libraries. Giving it higher requests/limits (for example 512Mi request / 1Gi limit vs 256Mi / 512Mi on the gateway) reduces the chance of OOM kills under normal load while still constraining the pod.

## Why does job-worker have no NodePort?

The job-worker is oriented around consuming work from Kafka and calling internal services (workflow-controller, Ollama, Qdrant). There is no need for clients on your Windows host or the public internet to open HTTP directly to it. A `ClusterIP` Service is enough for in-cluster DNS (`job-worker-svc:8082`) and optional actuator checks from inside the cluster.

## Why deploy workflow-controller before job-worker?

The job-worker Kafka consumer starts soon after the pod boots and interacts with workflow-controller for status and coordination over HTTP. Bringing workflow-controller (and its Service) up first avoids startup races where the worker cannot reach `http://workflow-controller-svc:8081` right away.

Order used by `scripts/deploy-apps.ps1`: apply `workflow-controller.yaml`, then `job-worker.yaml`, then `api-gateway.yaml`, and rollout status follows the same order.

## Quick end-to-end test

Resolve the gateway URL Minikube publishes for the NodePort:

```powershell
minikube service api-gateway-svc -n ai-orchestrator --url
```

Use that base URL with `curl` (adjust body to match your API). Example shape:

```powershell
curl -Method POST -Uri "<URL-from-minikube>/api/v1/jobs" -ContentType "application/json" -Body "{}"
```

## View logs

Tail workflow-controller logs:

```powershell
kubectl logs deployment/workflow-controller -n ai-orchestrator -f
```

Replace the deployment name for other apps (`job-worker`, `api-gateway`) as needed.

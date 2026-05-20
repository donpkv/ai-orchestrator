# Phase 1: Local Kubernetes with Minikube

## What is Minikube?

Minikube runs a single-node Kubernetes cluster on your machine inside a VM or container (here, Docker). It packages the control plane and kubelet so you get a real Kubernetes API and workloads without a cloud account or multi-machine lab.

We use it on Windows for **local development and integration checks**: you can apply manifests, exercise `kubectl`, and run services similar to production—fast feedback on a laptop.

## What is the `ai-orchestrator` namespace?

Kubernetes namespaces isolate resources (pods, services, configmaps, etc.) within one cluster. The **`ai-orchestrator`** namespace is reserved for this project’s workloads so they stay grouped and separate from `default` or system namespaces. The setup script creates it idempotently (`kubectl apply` after `create --dry-run=client`).

## Verify the cluster

With Minikube running and `kubectl` using the Minikube context:

```powershell
kubectl get nodes
```

You should see the Minikube node in `Ready` state.

After you deploy apps into the namespace:

```powershell
kubectl get pods -n ai-orchestrator
```

An empty list is normal until manifests are applied; the important part is that the command succeeds and shows no unexpected errors.

For setup and teardown, use:

- `scripts/setup-cluster.ps1` — start cluster, namespace, and addons
- `scripts/teardown-cluster.ps1` — delete namespace and stop Minikube

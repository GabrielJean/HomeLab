# Homepage — Unified Homelab Dashboard

Stateless, unified dashboard deployed across both `k8s-talos-1` and `k8s-talos-2` using a single declarative configuration file.

---

## Architecture

- **Single Source of Truth**: All dashboard settings, layouts, widgets, and services are defined in dedicated configuration files under [`configs/`](configs/) and packaged dynamically into a hashed ConfigMap via Kustomize's `configMapGenerator`.
- **Automatic Rolling Updates**: Because `configMapGenerator` computes a SHA hash appended to the ConfigMap name, any Git changes to configuration files immediately update the Deployment template and trigger an automatic pod restart in Flux CD.
- **Unified Multi-Home View**: Consolidates both Home 1 (`pve-1`, `talos-1`, `docker-1`) and Home 2 (`pve-2`, `talos-2`, `docker-2`) into a single view.
- **Stateless & High Availability**: Deployed natively to both clusters (`k8s-talos-1` and `k8s-talos-2`) through Flux CD without requiring persistent volumes or synchronization daemons.
- **Zero Secrets Dependency**: Clean, lightweight service link navigation without requiring API keys or secret stores. App link cards load instantly without external API polling.
- **Kubernetes Native Metrics**: Homepage utilizes an in-cluster `ServiceAccount` with RBAC permissions to query `metrics-server` for real-time node and cluster utilization.

---

## Access & Routing

- **Home 1**: `https://homepage.talos-1.gwebs.ca`
- **Home 2**: `https://homepage.talos-2.gwebs.ca`
- **Gateway API**: Routed via Traefik Gateway (`traefik-gateway`) using wildcard TLS certificates (`*.talos-1.gwebs.ca` / `*.talos-2.gwebs.ca`).

---

## Directory Structure

```
├── configs/              # Modular Homepage configuration files
│   ├── bookmarks.yaml    # Infrastructure bookmarks (Talos Omni, Azure, etc.)
│   ├── kubernetes.yaml   # In-cluster Kubernetes widget configuration
│   ├── services.yaml     # Homelab service cards across Home 1 and Home 2
│   ├── settings.yaml     # Layout, theme, background, and allowed hosts
│   └── widgets.yaml      # Cluster and system resource metric widgets
├── namespace.yaml        # 'homepage' namespace
├── serviceaccount.yaml   # ServiceAccount for in-cluster K8s API queries
├── rbac.yaml             # ClusterRole & Binding for node/pod metric observation
├── deployment.yaml       # Homepage container deployment with health probes
├── service.yaml          # ClusterIP service on port 3000
├── httproute.yaml        # Gateway API HTTPRoute binding to traefik-gateway
├── kustomization.yaml    # Kustomize aggregation & configMapGenerator
└── README.md             # Documentation
```


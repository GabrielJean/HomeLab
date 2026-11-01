# Gitea

Gitea is a painless self-hosted Git service written in Go, acting as a local mirror and backup system for GitHub repositories.

---

## Architecture

- **Workload Type**: Single-replica Kubernetes `Deployment` with `Recreate` strategy.
- **Topology**: Deployed exclusively on `k8s-talos-1` (Home 1) as a centralized single instance.
- **Database**: Self-contained SQLite3 (`/data/gitea/gitea.db`), providing low-overhead, zero-network-latency database operations with atomic filesystem storage.
- **Storage**: Persistent local volume via `local-path` storage class (15Gi) mounted at `/data`, housing git repositories, SQLite database, attachments, avatars, and the container package registry.
- **Security Context**: Runs with `fsGroup: 1000` to ensure user `git` (UID 1000 / GID 1000) maintains full write permissions across the `/data` mount.
- **SSH Access**: Native SSH service exposed directly via host binding (`hostPort: 222` mapping to container port `22`) on the Talos Linux control-plane node (`192.168.10.15`), supporting seamless `git clone ssh://git@gitea.talos-1.gwebs.ca:222/...`.
- **Ingress & TLS**: Gateway API `HTTPRoute` attached to `traefik-gateway` in the `traefik` namespace, serving HTTPS on `gitea.${CLUSTER_DOMAIN:=talos-1}.gwebs.ca` with cluster wildcard TLS certificates.
- **Health Probes**: Integrated startup, liveness, and readiness probes checking `/api/healthz` on port 3000.

---

## Directory Structure

```
├── namespace.yaml           # 'gitea' namespace with privileged PSA labels
├── pvc.yaml                 # 15Gi local-path PersistentVolumeClaim
├── deployment.yaml          # Application Deployment with probes, hostPort 222, and resources
├── service.yaml             # ClusterIP Service for HTTP (3000) and SSH (222)
├── httproute.yaml           # Traefik Gateway API HTTPRoute
├── kustomization.yaml       # Kustomize resource list
└── README.md                # Documentation
```

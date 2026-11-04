# FinGlass

FinGlass is a personal wealth intelligence and financial portfolio tracking web application built with Django.

---

## Architecture

- **Workload Type**: Single-replica Kubernetes `Deployment` with `Recreate` strategy.
- **Storage**: Persistent local volume via `local-path` storage class mounted at `/app/data` for SQLite database (`finglass.sqlite3`).
- **Ingress & TLS**: Gateway API `HTTPRoute` attached to `traefik-gateway` in the `traefik` namespace, serving HTTPS on `finglass.${CLUSTER_DOMAIN:=talos-1}.gwebs.ca` with cluster wildcard TLS certificates.
- **Health Probes**: Integrated startup, liveness, and readiness probes checking `/__django__/health/` on port 8000.

---

## Directory Structure

```
├── namespace.yaml      # 'finglass' namespace
├── pvc.yaml            # 2Gi local-path PersistentVolumeClaim
├── deployment.yaml     # Application Deployment with probes and resources
├── service.yaml        # ClusterIP Service on port 8000
├── httproute.yaml      # Traefik Gateway API HTTPRoute
├── kustomization.yaml  # Kustomize resource list
└── README.md           # Documentation
```


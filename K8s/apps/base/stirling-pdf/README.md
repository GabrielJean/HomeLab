# Stirling-PDF

Stirling-PDF is a robust, locally hosted web application that allows you to perform various operations on PDF files including merging, splitting, converting, reorganizing, and OCR text extraction.

---

## Architecture

- **Workload Type**: Single-replica Kubernetes `Deployment` with `Recreate` strategy.
- **Topology**: Deployed exclusively on `k8s-talos-1` (Home 1) as a centralized single instance serving both sites.
- **Storage**: Persistent local volume via `local-path` storage class (5Gi) mounted with subpaths for `/configs`, `/usr/share/tessdata` (OCR packs), and `/logs`.
- **Security Context**: Runs with `fsGroup: 1000` to allow the container's non-root user write access to mounted volumes.
- **Ingress & TLS**: Gateway API `HTTPRoute` attached to `traefik-gateway` in the `traefik` namespace, serving HTTPS on `pdf.${CLUSTER_DOMAIN:=talos-1}.gwebs.ca` with cluster wildcard TLS certificates.
- **Health Probes**: Integrated startup, liveness, and readiness probes checking `/api/v1/info/status` on port 8080.

---

## Directory Structure

```
├── namespace.yaml      # 'stirling-pdf' namespace
├── pvc.yaml            # 5Gi local-path PersistentVolumeClaim
├── deployment.yaml     # Application Deployment with probes and resources
├── service.yaml        # ClusterIP Service on port 8080
├── httproute.yaml      # Traefik Gateway API HTTPRoute
├── kustomization.yaml  # Kustomize resource list
└── README.md           # Documentation
```


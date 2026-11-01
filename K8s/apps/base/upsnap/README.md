# UpSnap

UpSnap is a simple, web-based Wake-on-LAN (WOL) application with network scanning and device status monitoring built on PocketBase and SvelteKit.

---

## Architecture

- **Workload Type**: Single-replica Kubernetes `Deployment` with `Recreate` strategy.
- **Host Networking**: Deployed with `hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet` to allow raw Layer 2 Ethernet broadcasts (WOL magic packets) and ICMP/nmap scanning directly on the local physical LAN interface.
- **Capabilities**: Container runs with `CAP_NET_RAW` for raw socket access required by `nmap` device discovery and privileged ICMP pings.
- **Pod Security Standards (PSA)**: Namespace is labeled with `pod-security.kubernetes.io/enforce: privileged` to allow `hostNetwork` on Kubernetes 1.31+.
- **Multi-Cluster Model**: One independent instance per cluster (`k8s-talos-1` for Home 1 `192.168.10.0/24`, `k8s-talos-2` for Home 2 `192.168.15.0/24`), each managing local LAN devices with its own isolated SQLite database.
- **Storage**: Persistent local volume via `local-path` storage class (2Gi) mounted at `/app/pb_data` for SQLite database (`data.db`).
- **Ingress & TLS**: Gateway API `HTTPRoute` attached to `traefik-gateway` in the `traefik` namespace, serving HTTPS on `upsnap.${CLUSTER_DOMAIN:=talos-1}.gwebs.ca` with cluster wildcard TLS certificates.
- **Health Probes**: Integrated startup, liveness, and readiness probes checking `/api/health` on port 8090.

---

## Directory Structure

```
├── namespace.yaml      # 'upsnap' namespace with privileged PSA labels
├── pvc.yaml            # 2Gi local-path PersistentVolumeClaim
├── deployment.yaml     # HostNetwork Deployment with NET_RAW and probes
├── service.yaml        # ClusterIP Service on port 8090
├── httproute.yaml      # Traefik Gateway API HTTPRoute
├── kustomization.yaml  # Kustomize resource list
└── README.md           # Documentation
```


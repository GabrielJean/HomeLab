# Multi-Cluster GitOps with Flux CD

Declarative GitOps configuration for the two homelab Talos Kubernetes clusters (`k8s-talos-1` and `k8s-talos-2`).

Because the repository is **public**, zero SSH keys or GitHub tokens are required. Everything bootstraps and reconciles via standard HTTPS using native `kubectl`.

---

## Topology

```text
               +-------------------------------------------------+
               |            Public GitHub Repository             |
               |      https://github.com/GabrielJean/HomeLab     |
               +-----------------------+-------------------------+
                                       |
                   (Public HTTPS Clone | No Tokens or Keys)
                                       |
               +-----------------------+-------------------------+
               |                                                 |
               v                                                 v
      +-------------------+                             +-------------------+
      | Cluster 1         |                             | Cluster 2         |
      | k8s-talos-1       |                             | k8s-talos-2       |
      | (Home 1 / pve-1)  |                             | (Home 2 / pve-2)  |
      |                   |                             |                   |
      | Path:             |                             | Path:             |
      | clusters/         |                             | clusters/         |
      |   k8s-talos-1     |                             |   k8s-talos-2     |
      +-------------------+                             +-------------------+
               |                                                 |
               +---> Reconciles:                                 +---> Reconciles:
                     - K8s/infrastructure (Headlamp, etc.)             - K8s/infrastructure (Headlamp, etc.)
                     - K8s/apps/k8s-talos-1 (Local apps)               - K8s/apps/k8s-talos-2 (Local apps)
```

Each cluster runs its own **independent, pull-based Flux instance**. A WAN outage at one home has zero impact on the other.

---

## Directory Structure

```text
clusters/
├── README.md                      # Operational guide
├── k8s-talos-1/                   # Cluster 1 (Home 1 / pve-1 / talos-1)
│   ├── kustomization.yaml         # Cluster entrypoint
│   ├── infrastructure.yaml        # Reconciles K8s/infrastructure
│   ├── apps.yaml                  # Reconciles K8s/apps/k8s-talos-1 (dependsOn: infrastructure)
│   └── flux-system/
│       ├── gotk-components.yaml   # Flux controller manifests (v2.9.6)
│       ├── gotk-sync.yaml         # Public HTTPS GitRepository & root sync
│       └── kustomization.yaml
└── k8s-talos-2/                   # Cluster 2 (Home 2 / pve-2 / talos-2)
    ├── kustomization.yaml         # Cluster entrypoint
    ├── infrastructure.yaml        # Reconciles K8s/infrastructure
    ├── apps.yaml                  # Reconciles K8s/apps/k8s-talos-2 (dependsOn: infrastructure)
    └── flux-system/
        ├── gotk-components.yaml   # Flux controller manifests (v2.9.6)
        ├── gotk-sync.yaml         # Public HTTPS GitRepository & root sync
        └── kustomization.yaml
```

---

## How to Bootstrap (One Single Command Per Cluster)

Connect `kubectl` to your cluster via Omni, and run:

### For Cluster 1 (`k8s-talos-1`):
```bash
omnictl kubeconfig -c k8s-talos-1 > ~/.kube/config
kubectl apply -k K8s/clusters/k8s-talos-1
```

### For Cluster 2 (`k8s-talos-2`):
```bash
omnictl kubeconfig -c k8s-talos-2 > ~/.kube/config
kubectl apply -k K8s/clusters/k8s-talos-2
```

That's it. Flux installs itself, clones the public repository over HTTPS, starts reconciling, and deploys Headlamp automatically.

---

## Day-to-Day Operations

You **never** need to run `kubectl apply` again:
1. Make changes to any manifest under `infrastructure/` or `apps/`.
2. Commit and push to GitHub:
   ```bash
   git commit -m "update headlamp"
   git push
   ```
3. Flux automatically syncs your changes to the cluster within minutes.
4. Monitor sync status directly from the **Headlamp UI** (via the built-in Flux tab) or with:
   ```bash
   kubectl -n flux-system get kustomizations
   ```

# Multi-Cluster GitOps with Flux CD

Declarative GitOps configuration for the two homelab Talos Kubernetes clusters (`k8s-talos-1` and `k8s-talos-2`).

Because the repository is **public**, zero SSH keys or GitHub tokens are required. Everything bootstraps and reconciles via standard HTTPS using native `kubectl`.

---

## Table of Contents

- [Topology](#topology)
- [Directory Structure](#directory-structure)
- [How to Bootstrap (One Single Command Per Cluster)](#how-to-bootstrap-one-single-command-per-cluster)
  - [For Cluster 1 (`k8s-talos-1`)](#for-cluster-1-k8s-talos-1)
  - [For Cluster 2 (`k8s-talos-2`)](#for-cluster-2-k8s-talos-2)
- [Secretless GitOps & Dynamic Variable Substitution](#secretless-gitops--dynamic-variable-substitution)
- [Day-to-Day Operations](#day-to-day-operations)

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

That's it. Flux installs itself, clones the public repository over HTTPS, starts reconciling, and deploys platform infrastructure (Headlamp, Traefik, External Secrets Operator) automatically.

---

## Secretless GitOps & Dynamic Variable Substitution

To keep the repository completely public and free of secrets or personal identity information (e.g. administrator emails):

1. **External Secrets Operator** connects to **Azure Key Vault** using passwordless **Workload Identity Federation**.
2. ESO writes sensitive configuration (such as `headlamp-admin-email`) into Secret `cluster-secrets` in the `flux-system` namespace.
3. The cluster `infrastructure.yaml` Kustomization uses `postBuild.substituteFrom` to dynamically substitute variables into manifests at deployment time:
   ```yaml
   postBuild:
     substitute:
       CLUSTER_NAME: talos-1
     substituteFrom:
       - kind: Secret
         name: cluster-secrets
         optional: true
   ```
4. Manifests reference variables like `${OIDC_ADMIN_EMAIL:=admin@example.com}`, keeping all personal data completely outside Git.

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

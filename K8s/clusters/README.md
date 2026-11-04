# Multi-Cluster GitOps with Flux CD

Declarative GitOps configuration for the two homelab Talos Kubernetes clusters (`k8s-talos-1` and `k8s-talos-2`).

Because the repository is **public**, zero SSH keys or GitHub tokens are required. Everything bootstraps and reconciles via standard HTTPS using native `kubectl`.

---

## Table of Contents

- [Topology](#topology)
- [Directory Structure](#directory-structure)
- [Staged Reconciliation Architecture](#staged-reconciliation-architecture)
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
                     1. infra-controllers (CRDs & Helm releases)       1. infra-controllers (CRDs & Helm releases)
                     2. infra-configs (Home 1 configs + Samba/Vault)   2. infra-configs (Home 2 configs)
                     3. apps (Local Home 1 workloads)                  3. apps (Local Home 2 workloads)
```

Each cluster runs its own **independent, pull-based Flux instance**. A WAN outage at one home has zero impact on the other.

---

## Directory Structure

```text
clusters/
├── README.md                      # Operational guide
├── k8s-talos-1/                   # Cluster 1 (Home 1 / pve-1 / talos-1)
│   ├── kustomization.yaml         # Cluster entrypoint
│   ├── infra-controllers.yaml     # Reconciles K8s/infrastructure/controllers (serverSideApply: true)
│   ├── infra-configs.yaml         # Reconciles K8s/infrastructure/overlays/k8s-talos-1 (dependsOn: infra-controllers)
│   ├── apps.yaml                  # Reconciles K8s/apps/k8s-talos-1 (dependsOn: infra-configs)
│   └── flux-system/
│       ├── gotk-components.yaml   # Flux controller manifests (v2.9.6)
│       ├── gotk-sync.yaml         # Public HTTPS GitRepository & root sync
│       └── kustomization.yaml
└── k8s-talos-2/                   # Cluster 2 (Home 2 / pve-2 / talos-2)
    ├── kustomization.yaml         # Cluster entrypoint
    ├── infra-controllers.yaml     # Reconciles K8s/infrastructure/controllers (serverSideApply: true)
    ├── infra-configs.yaml         # Reconciles K8s/infrastructure/overlays/k8s-talos-2 (dependsOn: infra-controllers)
    ├── apps.yaml                  # Reconciles K8s/apps/k8s-talos-2 (dependsOn: infra-configs)
    └── flux-system/
        ├── gotk-components.yaml   # Flux controller manifests (v2.9.6)
        ├── gotk-sync.yaml         # Public HTTPS GitRepository & root sync
        └── kustomization.yaml
```

---

## Staged Reconciliation Architecture

To avoid race conditions and eliminate manual CRD pre-installation steps, infrastructure and applications reconcile in three deterministic stages:

1. **Stage 1 (`infra-controllers`)**:
   - Deploys core operators, Helm releases, and CRDs (Gateway API, cert-manager, External Secrets Operator, Traefik, Local Path Provisioner, Metrics Server, Tailscale, VolSync).
   - Uses `serverSideApply: true` to prevent OpenAPI schema annotation size limits.
2. **Stage 2 (`infra-configs`)**:
   - `dependsOn: [infra-controllers]` ensures all CRDs and controllers are fully ready.
   - Deploys cluster resources that instantiate CRDs: `ClusterIssuer`, `ClusterSecretStore`, Traefik Gateway, wildcard certificates, and Headlamp.
   - Includes cluster-specific overlays (e.g. Samba and VirtioFS PVs on `k8s-talos-1` only).
3. **Stage 3 (`apps`)**:
   - `dependsOn: [infra-configs]` ensures storage classes, wildcard certificates, and secrets stores are live before workload pods start.

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

Flux installs itself, clones the public repository over HTTPS, and reconciles controllers, configurations, and applications autonomously in sequence without manual CRD pre-installation.

---

## Secretless GitOps & Dynamic Variable Substitution

To keep the repository completely public and free of secrets or personal identity information:

1. **External Secrets Operator** connects to **Azure Key Vault** using passwordless **Workload Identity Federation**.
2. ESO writes sensitive configuration (such as `headlamp-admin-email`) into Secret `cluster-secrets` in the `flux-system` namespace.
3. The cluster `infra-configs.yaml` Kustomization uses `postBuild.substituteFrom` to dynamically substitute variables into manifests at deployment time:
   ```yaml
   postBuild:
     substitute:
       CLUSTER_NAME: k8s-talos-1
       CLUSTER_DOMAIN: talos-1
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

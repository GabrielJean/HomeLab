# VolSync (Asynchronous Volume Replication Operator)

In-cluster deployment of [VolSync](https://volsync.readthedocs.io/) across `k8s-talos-1` and `k8s-talos-2`.

VolSync is a Kubernetes-native operator designed for asynchronous, cross-cluster volume data replication. It provides a declarative CRD-driven architecture (`ReplicationSource` and `ReplicationDestination`) to automate volume snapshots, backups, and warm-standby replication without injecting bespoke scripts or sidecars into application manifests.

---

## Component Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Project** | [backube/volsync](https://github.com/backube/volsync) | Kubernetes volume replication operator |
| **Helm Chart** | `volsync` (`0.17.0`) | Repository: `https://backube.github.io/helm-charts/` |
| **Namespace** | `volsync-system` | Dedicated platform namespace |
| **CRDs Managed** | `ReplicationSource`, `ReplicationDestination` | Automatic lifecycle management via Flux |
| **Data Mover Used** | `restic` (`copyMethod: Direct`) | Fully compatible with Talos Linux & `local-path` |
| **Cloud Repository** | Azure Blob Storage (`gjtalossa`) | Deduplicated, encrypted offsite snapshot storage |

---

## How It Works with `local-path`

Because the homelab uses `local-path` storage on Talos Linux (which lacks native CSI volume snapshotting), VolSync uses:
- `copyMethod: Direct`: The VolSync data mover pod attaches directly to the volume to snapshot or restore data without requiring CSI snapshot drivers.
- `restic`: Provides fast incremental backups, deduplication, and encryption to Azure Blob Storage.

---

## Directory Structure

```text
infrastructure/storage/volsync/
├── README.md                      # Operational guide
├── namespace.yaml                 # volsync-system namespace
├── helmrepository.yaml            # backube official Helm repo
├── helmrelease.yaml               # HelmRelease (v0.17.0, CRDs enabled)
└── kustomization.yaml             # Kustomize entrypoint
```


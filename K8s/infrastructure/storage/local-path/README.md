# Rancher Local Path Provisioner

In-cluster dynamic local volume provisioner for the Homelab Talos Kubernetes clusters.

The **Local Path Provisioner** provides dynamic persistent storage using node-local directories. It serves as the primary **Default StorageClass** (`local-path`) for databases, configuration files, and stateful applications (Gitea, Home Assistant, Prometheus, Grafana, etc.).

---

## Component Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Project** | [rancher/local-path-provisioner](https://github.com/rancher/local-path-provisioner) | Official Rancher CNCF project |
| **Version** | `v0.0.37` | Latest stable release (patched for CVE-2025-62878) |
| **Namespace** | `local-path-storage` | Dedicated storage namespace |
| **StorageClass Name** | `local-path` | Annotated as cluster default (`is-default-class: true`) |
| **Host Storage Path** | `/var/local-path-provisioner/<namespace>/<pvc-name>` | Predictable namespace-scoped structure on `/var` partition |
| **Volume Binding Mode**| `WaitForFirstConsumer` | Provisions on the exact node where the pod is scheduled |
| **RAM Footprint** | ~15–20 MB | Minimal resource overhead |

---

## Why `/var/mnt/local-path` on Talos Linux?

Talos Linux has an immutable, read-only root filesystem (`/`).

Upstream default manifests attempt to use `/opt/local-path-provisioner`, which fails immediately on Talos with a `Read-only file system` error.

In our [`configmap.yaml`](configmap.yaml) and [`storageclass.yaml`](storageclass.yaml), the provisioner is dynamically configured for all nodes with a clean path template:

```text
/var/local-path-provisioner/<namespace>/<pvc-name>
```

For example:
- Gitea: `/var/local-path-provisioner/default/gitea-data`
- Home Assistant: `/var/local-path-provisioner/homeassistant/config`
- Prometheus: `/var/local-path-provisioner/monitoring/prometheus-db`

Because `/var` is mounted on the VM's main writable data partition, volumes are created without permission issues and are automatically included in your nightly **Proxmox Backup Server (PBS)** VM image backups with clean, human-readable directory browsing. Zero hardcoded node names.

---

## How Applications Consume Storage

Because `local-path` is marked as the default StorageClass, any application can request storage without needing to specify a storage class explicitly.

### Example: Standard Application PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  # storageClassName: local-path  # (Optional: defaults automatically)
  resources:
    requests:
      storage: 10Gi
```

### Example: Mounting into a Pod / Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: gitea
          image: gitea/gitea:latest
          volumeMounts:
            - name: gitea-storage
              mountPath: /data
      volumes:
        - name: gitea-storage
          persistentVolumeClaim:
            claimName: gitea-data
```

---

## Verification & Troubleshooting

```bash
# Check provisioner status
kubectl -n local-path-storage get pods

# Verify the default StorageClass
kubectl get storageclass

# Check provisioned PVs and PVCs
kubectl get pv,pvc -A

# Check provisioner logs
kubectl -n local-path-storage logs -l app=local-path-provisioner -f
```


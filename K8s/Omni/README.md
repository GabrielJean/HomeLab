# Sidero Omni Cluster Bootstrap Guide

Declarative templates for provisioning and managing two independent single-node Kubernetes clusters via **Sidero Omni SaaS** and **`omnictl`**.

---

## Clusters Overview

| Cluster Name | Host / Site | Node Name | Omni Label | Machine Class | Template File |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`k8s-talos-1`** | Home 1 (`pve-1`) | `talos-1` | `pve-1` | `pve-1` | [`k8s-talos-1.yaml`](clusters/k8s-talos-1.yaml) |
| **`k8s-talos-2`** | Home 2 (`pve-2`) | `talos-2` | `pve-2` | `pve-2` | [`k8s-talos-2.yaml`](clusters/k8s-talos-2.yaml) |

Both clusters run as **single-node schedulable control planes** with native Flannel CNI and network policies enabled (`kubeNetworkPoliciesEnabled: true`).

---

## 4-Step Bootstrap Walkthrough

### Step 1: Boot the VM in Proxmox

1. **Apply Media Presets to Omni (GitOps)**:
   ```bash
   omnictl apply -f Omni/media/
   ```
   *(Registers declarative presets for `talos-1` and `talos-2` with Talos 1.14.4, NoCloud cloud-init, QEMU guest agent, NVIDIA 580 LTS extensions, and auto-labels).*

2. **Download Boot Media from Omni**:
   - In your [Omni SaaS Dashboard](https://omni.siderolabs.com), open **Installation Media**, locate `talos-1` or `talos-2`, and click **Download ISO**.
3. Upload the ISO to Proxmox and create your VM (`talos-1` on `pve-1` or `talos-2` on `pve-2`).
4. Boot the VM.

---

### Step 2: Apply Machine Classes and Label Machines in Omni

1. **Apply the Machine Classes to Omni**:
   ```bash
   omnictl apply -f Omni/classes/
   ```
   *(This registers the `pve-1` and `pve-2` machine selectors in Omni).*

2. **Label the Discovered Machine in Omni**:
   Once booted, the node connects over SideroLink and appears in the Omni UI under **Machines**:
   - In the Omni dashboard, click the discovered machine.
   - For Home 1: add label **`pve-1`**
   - For Home 2: add label **`pve-2`**

*(Omni's Machine Classes match this label automatically—no UUIDs needed in Git).*

---

### Step 3: Sync the Cluster Template
From this repository, push the declarative cluster configuration to Omni:

```bash
# For Home 1 (k8s-talos-1):
omnictl cluster template sync -f Omni/clusters/k8s-talos-1.yaml

# For Home 2 (k8s-talos-2):
omnictl cluster template sync -f Omni/clusters/k8s-talos-2.yaml
```

Omni will automatically:
- Allocate the labeled node to the cluster.
- Apply the single-node patch (`allowSchedulingOnControlPlanes: true`).
- Enable native NetworkPolicies on Flannel.
- Apply site-to-site static routes between Home 1 and Home 2 via local Tailscale routers.
- Bootstrap etcd and Kubernetes.

---

### Step 4: Get `kubeconfig` and Verify
Fetch the admin credentials routed through Omni's secure WireGuard proxy:

```bash
# Merge credentials into your ~/.kube/config:
omnictl kubeconfig -c k8s-talos-1 --service-account --user admin --force-context-name admin@k8s-talos-1 --force
omnictl kubeconfig -c k8s-talos-2 --service-account --user admin --force-context-name admin@k8s-talos-2 --force

# Verify the clusters:
kubectl --context admin@k8s-talos-1 get nodes
kubectl --context admin@k8s-talos-2 get nodes
```

---

## Automated S3 etcd Backups

Omni natively supports continuous `etcd` snapshots stored directly to S3 or S3-compatible object storage (AWS S3, Cloudflare R2, MinIO, Backblaze B2, etc.).


### 1. Schedule Backups in Cluster Templates
Both [`k8s-talos-1.yaml`](clusters/k8s-talos-1.yaml) and [`k8s-talos-2.yaml`](clusters/k8s-talos-2.yaml) have automated backups configured under `features.backupConfiguration`:

```yaml
features:
  backupConfiguration:
    interval: 1h  # Automatically snapshots etcd every hour
```

When you run `omnictl cluster template sync -f ...`, Omni immediately triggers an initial backup and schedules recurring snapshots according to this interval.

### 2. Check Backup Records
```bash
# List all etcd backups for a cluster:
omnictl get etcdbackup --selector omni.sidero.dev/cluster=k8s-talos-1
```

---

## Quick Reference Commands

```bash
# Check discovered machines and connection status
omnictl get machines

# Check cluster status
omnictl get clusters

# Preview template changes before syncing
omnictl cluster template diff -f Omni/clusters/k8s-talos-1.yaml

# Stream live node logs
omnictl machine-logs <machine-id>
```

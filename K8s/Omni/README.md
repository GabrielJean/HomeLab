# Sidero Omni Cluster Bootstrap Guide

Declarative templates for provisioning and managing two independent single-node Kubernetes clusters via **Sidero Omni SaaS** and **`omnictl`**.

---

## Clusters Overview

| Cluster Name | Host / Site | Node Name | Omni Label | Machine Class | Template File |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`k8s-talos-1`** | Home 1 (`pve-1`) | `talos-1` | `pve-1` | `pve-1` | [`talos-1-cluster.yaml`](clusters/talos-1-cluster.yaml) |
| **`k8s-talos-2`** | Home 2 (`pve-2`) | `talos-2` | `pve-2` | `pve-2` | [`talos-2-cluster.yaml`](clusters/talos-2-cluster.yaml) |

Both clusters run as **single-node schedulable control planes** with native Flannel CNI and network policies enabled (`kubeNetworkPoliciesEnabled: true`).

---

## 4-Step Bootstrap Walkthrough

### Step 1: Boot the VM in Proxmox
1. Log in to your [Omni SaaS Dashboard](https://omni.siderolabs.com).
2. Download the Talos boot ISO for your account.
3. Upload the ISO to Proxmox and create your VM (`talos-1` on `pve-1` or `talos-2` on `pve-2`).
4. Boot the VM.

---

### Step 2: Label the Discovered Machine in Omni
Once booted, the node connects over SideroLink and appears in the Omni UI under **Machines**:
1. In the Omni dashboard, click the discovered machine.
2. Add the corresponding label:
   - For Home 1: add label **`pve-1`**
   - For Home 2: add label **`pve-2`**

*(Omni's Machine Classes match this label automatically—no UUIDs needed in Git).*

---

### Step 3: Sync the Cluster Template
From this repository, push the declarative cluster configuration to Omni:

```bash
# For Home 1 (k8s-talos-1):
omnictl cluster template sync -f omni/clusters/talos-1-cluster.yaml

# For Home 2 (k8s-talos-2):
omnictl cluster template sync -f omni/clusters/talos-2-cluster.yaml
```

Omni will automatically:
- Allocate the labeled node to the cluster.
- Apply the single-node patch (`allowSchedulingOnControlPlanes: true`).
- Enable native NetworkPolicies on Flannel.
- Bootstrap etcd and Kubernetes.

---

### Step 4: Get `kubeconfig` and Verify
Fetch the admin credentials routed through Omni's secure WireGuard proxy:

```bash
# Merge credentials into your ~/.kube/config:
omnictl kubeconfig -c k8s-talos-1

# Verify the cluster:
kubectl --context admin@k8s-talos-1 get nodes
```

---

## Quick Reference Commands

```bash
# Check discovered machines and connection status
omnictl get machines

# Check cluster status
omnictl get clusters

# Preview template changes before syncing
omnictl cluster template diff -f omni/clusters/talos-1-cluster.yaml

# Stream live node logs
omnictl machine-logs <machine-id>
```

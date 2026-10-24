# Kubernetes Clusters Bootstrap Guide

End-to-end operational guide for provisioning, bootstrapping, and operating the two independent homelab Talos Linux Kubernetes clusters: **`k8s-talos-1`** (Home 1) and **`k8s-talos-2`** (Home 2).

---

## Architecture Overview

```text
               +-------------------------------------------------+
               |             Sidero Omni SaaS Control            |
               |            https://omni.siderolabs.com          |
               +-----------------------+-------------------------+
                                       |
                     (SideroLink Mesh  | Zero Inbound WAN Ports)
                                       |
               +-----------------------+-------------------------+
               |                                                 |
               v                                                 v
      +-------------------+                             +-------------------+
      | Node: talos-1     |                             | Node: talos-2     |
      | Cluster:          |                             | Cluster:          |
      |   k8s-talos-1     |                             |   k8s-talos-2     |
      | Host: pve-1       |                             | Host: pve-2       |
      | Location: Home 1  |                             | Location: Home 2  |
      +-------------------+                             +-------------------+
               |                                                 |
               v                                                 v
       (Runs Flux CD)                                    (Runs Flux CD)
               |                                                 |
               +=======================+=========================+
                                       |
                          (Public HTTPS Pull Sync)
                                       |
                                       v
               +-------------------------------------------------+
               |              Public GitHub Monorepo             |
               |      https://github.com/GabrielJean/HomeLab     |
               +-------------------------------------------------+
```

| Layer | Component | Role |
| :--- | :--- | :--- |
| **OS & Hardware** | **Talos Linux v1.14.4** | Immutable, API-driven Linux OS with schedulable control plane |
| **Management** | **Sidero Omni SaaS** | Machine registration, WireGuard SideroLink tunnels, OS lifecycle |
| **Networking** | **Flannel CNI** | Out-of-the-box CNI with native NetworkPolicies enabled |
| **GitOps** | **Flux CD v2.9.6** | Declarative state reconciliation directly from GitHub over HTTPS |
| **Dashboard** | **Headlamp v0.46.0** | In-cluster web dashboard with pre-loaded Flux CD GitOps plugin |
| **Ingress & TLS** | **Traefik + cert-manager** | HostPort (80/443) entrypoint with automated Let's Encrypt TLS |

---

## Prerequisites

Run the automated tool installer to ensure `omnictl`, `kubectl`, and `flux` are installed:

```bash
cd /home/gabriel/HomeLab
./install-tools.sh
```

Ensure your `omnictl` CLI is authenticated to your Omni SaaS account:
```bash
omnictl config merge <path-to-omni-auth-download>.yaml
omnictl get machines
```

---

## End-to-End Bootstrap (6 Simple Steps)

### Step 1: Register Media Presets & Download ISO

From the repository root:

```bash
# 1. Apply declarative media presets to Omni
omnictl apply -f K8s/Omni/media/

# 2. Download the customized Talos ISO for each host
omnictl media download talos-1 --output ~/Downloads/
omnictl media download talos-2 --output ~/Downloads/
```

*Note: These presets automatically bundle the QEMU Guest Agent and platform drivers.*

---

### Step 2: Create & Boot the Proxmox VM

1. Upload the downloaded ISO to Proxmox (`pve-1` for Home 1, `pve-2` for Home 2).
2. Create a VM with recommended specs:
   - **CPU**: 4 vCPU (Host type)
   - **RAM**: 8–16 GB
   - **Disk**: 60–100 GB SSD (SCSI / VirtIO SCSI single)
   - **Options**: Enable **QEMU Guest Agent**
3. Attach the ISO and power on the VM.

---

### Step 3: Label the Node & Sync Cluster Template

Once booted, the node securely connects to Omni via SideroLink and appears in the Omni console:

```bash
# 1. Apply the Machine Classes to Omni
omnictl apply -f K8s/Omni/classes/

# 2. View discovered machines
omnictl get machines
```

In the Omni dashboard (or via CLI), assign the matching label to the discovered machine:
* For Home 1 VM: Add label **`pve-1`**
* For Home 2 VM: Add label **`pve-2`**

Now trigger declarative cluster provisioning:

```bash
# For Cluster 1 (Home 1):
omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-1.yaml

# For Cluster 2 (Home 2):
omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-2.yaml
```

Omni will automatically partition the disk, install Talos, bootstrap etcd, enable Flannel NetworkPolicies, and start Kubernetes.

---

### Step 4: Fetch Kubeconfig

Retrieve the admin kubeconfig routed through Omni's secure encrypted proxy:

#### Cluster 1 (`k8s-talos-1`):
```bash
omnictl kubeconfig -c k8s-talos-1 --service-account --user admin --force-context-name admin@k8s-talos-1 --force
kubectl --context admin@k8s-talos-1 get nodes
```

#### Cluster 2 (`k8s-talos-2`):
```bash
omnictl kubeconfig -c k8s-talos-2 --service-account --user admin --force-context-name admin@k8s-talos-2 --force
kubectl --context admin@k8s-talos-2 get nodes
```

---

### Step 5: Bootstrap GitOps & Platform Stack

Because the repository is public, **no SSH keys or GitHub tokens are required**.

To bootstrap a fresh cluster into GitOps cleanly, apply the Flux components and CRDs first, followed by the cluster root synchronization:

#### For Cluster 1 (`k8s-talos-1`):
```bash
# 1. Install Flux namespace, CRDs, and controllers
kubectl --context admin@k8s-talos-1 apply -f K8s/clusters/k8s-talos-1/flux-system/gotk-components.yaml

# 2. Apply the cluster synchronization manifests (GitRepository + Kustomizations)
kubectl --context admin@k8s-talos-1 apply -k K8s/clusters/k8s-talos-1
```

#### For Cluster 2 (`k8s-talos-2`):
```bash
# 1. Install Flux namespace, CRDs, and controllers
kubectl --context admin@k8s-talos-2 apply -f K8s/clusters/k8s-talos-2/flux-system/gotk-components.yaml

# 2. Apply the cluster synchronization manifests (GitRepository + Kustomizations)
kubectl --context admin@k8s-talos-2 apply -k K8s/clusters/k8s-talos-2
```

> [!TIP]
> Alternatively, running `kubectl apply -k K8s/clusters/<cluster>` directly will install everything in one go. If running on a brand-new cluster where CRDs are not yet established, simply re-run the same command once more so the custom resources (`Kustomization`, `GitRepository`) attach cleanly.

**What happens automatically:**
1. Flux CD starts up in the `flux-system` namespace.
2. Flux pulls `https://github.com/GabrielJean/HomeLab.git` via anonymous HTTPS.
3. Flux deploys all shared platform components under [`K8s/infrastructure/`](infrastructure/):
   - **Local Path Provisioner**: dynamic host storage at `/var/local-path-provisioner/<namespace>/<pvc-name>`.
   - **Traefik Ingress Controller**: binds host ports `80` & `443` with automatic HTTP-to-HTTPS redirect.
   - **Headlamp Dashboard**: Kubernetes web UI with the Flux GitOps plugin.
4. Flux begins reconciling cluster-specific apps under [`K8s/apps/`](apps/).

Verify Flux reconciliation status:
```bash
kubectl --context admin@k8s-talos-1 -n flux-system get kustomizations
# All entries (flux-system, infrastructure, apps) should report READY: True
```

---

### Step 6: Log Into Headlamp Web Dashboard

#### 1. Retrieve the Pre-Configured Admin Token
```bash
kubectl --context admin@k8s-talos-1 -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d
```
*(Copy the resulting token string).*

#### 2. Open Headlamp
* **Via Ingress (once DNS/Traefik is configured)**:
  * Home 1 (`k8s-talos-1`): `https://headlamp.talos-1.gwebs.ca`
  * Home 2 (`k8s-talos-2`): `https://headlamp.talos-2.gwebs.ca`
* **Via Port-Forward (Immediate / Local)**:
  ```bash
  kubectl --context admin@k8s-talos-1 -n headlamp port-forward svc/headlamp 8080:80
  ```
  Open `http://localhost:8080` in your web browser.

#### 3. Paste the Token
Paste the token into the Headlamp authentication prompt. You now have full cluster visibility, live streaming logs, terminal exec, and a dedicated **Flux** GitOps sidebar tab.

---

## Summary Cheat Sheet

| Task | Cluster 1 (`k8s-talos-1`) | Cluster 2 (`k8s-talos-2`) |
| :--- | :--- | :--- |
| **Sync Omni Template** | `omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-1.yaml` | `omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-2.yaml` |
| **Fetch Kubeconfig** | `omnictl kubeconfig -c k8s-talos-1 > ~/.kube/config` | `omnictl kubeconfig -c k8s-talos-2 > ~/.kube/config` |
| **Bootstrap GitOps** | `kubectl apply -k K8s/clusters/k8s-talos-1` | `kubectl apply -k K8s/clusters/k8s-talos-2` |
| **Get Headlamp Token** | `kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' \| base64 -d` | *(Same command on context)* |
| **Update Any Workload** | Commit & push to `main` | Commit & push to `main` |

---

## Directory Reference

* [`K8s/Omni/`](Omni/): Machine classes, declarative media presets, site routing patches, and Omni cluster templates.
* [`K8s/clusters/`](clusters/): Independent Flux cluster overlays and root synchronization definitions.
* [`K8s/infrastructure/`](infrastructure/): Cluster-wide platform components (Headlamp, Ingress, storage, cert-manager).
* [`K8s/apps/`](apps/): Workload manifests separated into shared templates (`base/`) and cluster overlays (`k8s-talos-1/`, `k8s-talos-2/`).
* [`K8s/PLAN.md`](PLAN.md): Full architectural specification and phased migration plan from Docker Compose.


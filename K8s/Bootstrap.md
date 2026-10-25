# Kubernetes Clusters Bootstrap Guide

End-to-end operational guide for provisioning, bootstrapping, and operating the two independent homelab Talos Linux Kubernetes clusters from scratch: **`k8s-talos-1`** (Home 1) and **`k8s-talos-2`** (Home 2).

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites & Tools](#prerequisites--tools)
  - [1. Install CLI Tooling](#1-install-cli-tooling)
  - [2. Authenticate Omni CLI](#2-authenticate-omni-cli)
  - [3. Azure Infrastructure Setup](#3-azure-infrastructure-setup)
- [Step-by-Step Bootstrap Walkthrough](#step-by-step-bootstrap-walkthrough-8-steps)
  - [Step 1: Register Media Presets & Download ISO](#step-1-register-media-presets--download-iso)
  - [Step 2: Create & Boot the Proxmox VM](#step-2-create--boot-the-proxmox-vm)
  - [Step 3: Label Machine & Sync Omni Cluster Template](#step-3-label-machine--sync-omni-cluster-template)
  - [Step 4: Fetch Admin Kubeconfig](#step-4-fetch-admin-kubeconfig)
  - [Step 5: Establish Azure Workload Identity Federation (Path 2)](#step-5-establish-azure-workload-identity-federation-path-2)
  - [Step 6: Populate Secrets in Azure Key Vault](#step-6-populate-secrets-in-azure-key-vault)
  - [Step 7: Pre-Install CRD Bundles (Server-Side Apply)](#step-7-pre-install-crd-bundles-server-side-apply)
  - [Step 8: Bootstrap Flux GitOps & Platform Stack](#step-8-bootstrap-flux-gitops--platform-stack)
- [Verification & Day-to-Day Operations](#verification--day-to-day-operations)
  - [1. Verify Flux Reconciliation](#1-verify-flux-reconciliation)
  - [2. Verify External Secrets & Key Vault Sync](#2-verify-external-secrets--key-vault-sync)
  - [3. Verify Dynamic RBAC Binding](#3-verify-dynamic-rbac-binding)
  - [4. Log Into Headlamp Web Dashboard](#4-log-into-headlamp-web-dashboard)
- [Secret Expiration & Maintenance Runbook](#secret-expiration--maintenance-runbook)
- [Summary Cheat Sheet](#summary-cheat-sheet)
- [Documentation & Component Reference](#documentation--component-reference)

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
               | (Runs Flux CD & External Secrets)               | (Runs Flux CD & External Secrets)
               v                                                 v
  +---------------------------+                     +---------------------------+
  |    Azure Storage (oidc)   |                     |     Azure Key Vault       |
  |  Public Discovery & JWKS  |                     |        gjtaloskv          |
  +-------------+-------------+                     +-------------+-------------+
                |                                                 |
                +-----------------------+-------------------------+
                                        | (Workload Identity Federation)
                                        v
               +-------------------------------------------------+
               |             Microsoft Entra ID (OIDC)           |
               |            Directory: 10b7061b-f2d0...          |
               +-----------------------+-------------------------+
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
| **OS & Hardware** | **Talos Linux v1.14.4** | Immutable, API-driven Linux OS with schedulable single-node control plane |
| **Management** | **Sidero Omni SaaS** | Machine registration, WireGuard SideroLink tunnels, OS lifecycle |
| **Networking** | **Flannel CNI** | Host networking with native NetworkPolicies enabled |
| **GitOps Engine** | **Flux CD v2.9.6** | Declarative state reconciliation directly from GitHub over HTTPS |
| **Secrets Engine** | **External Secrets Operator v2.14.0** | 100% secretless Workload Identity federation with Azure Key Vault |
| **OIDC Discovery** | **Azure Blob Storage (`gjtalossa`)** | Hosts public cluster `.well-known/openid-configuration` & JWKS keys |
| **Secret Store** | **Azure Key Vault (`gjtaloskv`)** | Cloud vault storing OIDC client secrets and sensitive identities |
| **Dashboard** | **Headlamp v0.46.0** | In-cluster web dashboard with Entra ID SSO and pre-loaded Flux plugin |
| **Ingress & TLS** | **Traefik v42.1.3 + Gateway API** | HostPort (80/443) entrypoint routing via Kubernetes Gateway API `HTTPRoute` |
| **Host Storage** | **Local Path Provisioner** | Host-path PVC storage provisioner under `/var/local-path-provisioner` |

---

## Prerequisites & Tools

### 1. Install CLI Tooling
Run the automated tool installer to ensure `omnictl`, `kubectl`, and `flux` are installed:

```bash
cd /home/gabriel/HomeLab
./install-tools.sh
```

### 2. Authenticate Omni CLI
Merge your Omni service account / user credentials into your local environment:

```bash
omnictl config merge <path-to-omni-auth-download>.yaml
omnictl get machines
```

### 3. Azure Infrastructure Setup
Ensure the following resources are active in Microsoft Azure:
- **Azure Storage Account**: `gjtalossa` (with a publicly accessible container named `oidc`).
- **Azure Key Vault**: `gjtaloskv` (`https://gjtaloskv.vault.azure.net/`).
- **Microsoft Entra ID App Registration**:
  - **Application (client) ID**: `e1d55ddd-3453-4a91-9842-aa7d7dc620a3`
  - **Directory (tenant) ID**: `10b7061b-f2d0-4778-8cae-2666faf4af25`
  - **Web Redirect URIs**:
    - `https://headlamp.talos-1.gwebs.ca/oidc-callback`
    - `https://headlamp.talos-2.gwebs.ca/oidc-callback`

---

## Step-by-Step Bootstrap Walkthrough (8 Steps)

### Step 1: Register Media Presets & Download ISO

From the repository root:

```bash
# 1. Apply declarative media presets to Omni
omnictl apply -f K8s/Omni/media/

# 2. Download the customized Talos ISO for each host
omnictl media download talos-1 --output ~/Downloads/
omnictl media download talos-2 --output ~/Downloads/
```

*Note: These presets automatically bundle the QEMU Guest Agent and VirtIO storage drivers.*

---

### Step 2: Create & Boot the Proxmox VM

1. Upload the downloaded ISO to Proxmox (`pve-1` for Home 1, `pve-2` for Home 2).
2. Create a VM with recommended specs:
   - **CPU**: 4 vCPU (Type: `host`)
   - **RAM**: 8–16 GB
   - **Disk**: 60–100 GB SSD (SCSI / VirtIO SCSI single)
   - **Network**: Bridge to local LAN (VirtIO)
   - **Options**: Enable **QEMU Guest Agent**
3. Attach the ISO as CD-ROM and power on the VM.

---

### Step 3: Label Machine & Sync Omni Cluster Template

Once booted, the node connects securely to Omni via SideroLink:

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

**What Omni does:**
- Partitions the disk and installs Talos Linux.
- Bootstraps single-node etcd and control plane.
- Injects `KubeServiceAccountConfig` with `--service-account-issuer=https://gjtalossa.blob.core.windows.net/oidc/<cluster>`.
- Enables Flannel NetworkPolicies and site-to-site routes.

---

### Step 4: Fetch Admin Kubeconfig

Retrieve the admin kubeconfig routed through Omni's secure proxy:

```bash
# Cluster 1 (k8s-talos-1):
omnictl kubeconfig -c k8s-talos-1 --service-account --user admin --force-context-name admin@k8s-talos-1 --force
kubectl --context admin@k8s-talos-1 get nodes

# Cluster 2 (k8s-talos-2):
omnictl kubeconfig -c k8s-talos-2 --service-account --user admin --force-context-name admin@k8s-talos-2 --force
kubectl --context admin@k8s-talos-2 get nodes
```

Verify that the node status reports `Ready`.

---

### Step 5: Establish Azure Workload Identity Federation (Path 2)

Each cluster acts as an independent OIDC identity provider.

#### 1. Extract Cluster Public Signing Keys
```bash
# For talos-1:
kubectl --context admin@k8s-talos-1 get --raw /openid/v1/jwks > jwks-talos-1.json

# For talos-2:
kubectl --context admin@k8s-talos-2 get --raw /openid/v1/jwks > jwks-talos-2.json
```

#### 2. Create the Discovery Document
Create `.well-known/openid-configuration` with the cluster's issuer URL:
```json
{
  "issuer": "https://gjtalossa.blob.core.windows.net/oidc/talos-1",
  "jwks_uri": "https://gjtalossa.blob.core.windows.net/oidc/talos-1/openid/v1/jwks",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
```
*(Replace `talos-1` with `talos-2` for Cluster 2).*

#### 3. Upload to Azure Blob Storage
Upload to container `oidc` on `gjtalossa.blob.core.windows.net`:
- `oidc/talos-1/.well-known/openid-configuration`
- `oidc/talos-1/openid/v1/jwks`
- `oidc/talos-2/.well-known/openid-configuration`
- `oidc/talos-2/openid/v1/jwks`

Verify that both URLs are publicly reachable with HTTP 200:
```bash
curl -sI https://gjtalossa.blob.core.windows.net/oidc/talos-1/.well-known/openid-configuration | head -n 1
curl -sI https://gjtalossa.blob.core.windows.net/oidc/talos-1/openid/v1/jwks | head -n 1
```

#### 4. Configure Federated Identity Credentials in Azure
In the Azure Portal ➔ **Microsoft Entra ID** ➔ **App registrations** ➔ `e1d55ddd-3453-4a91-9842-aa7d7dc620a3` ➔ **Certificates & secrets** ➔ **Federated credentials**:

Add a federated credential for each cluster:
* **Issuer**: `https://gjtalossa.blob.core.windows.net/oidc/<cluster>`
* **Subject identifier**: `system:serviceaccount:external-secrets:external-secrets`
* **Name**: `k8s-<cluster>-eso` (e.g. `k8s-talos-1-eso`)
* **Audience**: `api://AzureADTokenExchange`

---

### Step 6: Populate Secrets in Azure Key Vault

In Azure Key Vault (`https://gjtaloskv.vault.azure.net/`) ➔ **Objects** ➔ **Secrets**:

| Secret Name | Value | Purpose |
| :--- | :--- | :--- |
| **`headlamp-oidc-client-secret`** | *Client Secret Value from Entra ID* | Used by Headlamp backend for OAuth code exchange. *(Valid until Oct 23, 2028)*. |
| **`headlamp-admin-email`** | *Admin email address* | Injected dynamically by Flux into Kubernetes RBAC (`oidc-admin` ClusterRoleBinding) so personal emails never appear in Git. |

---

### Step 7: Pre-Install CRD Bundles (Server-Side Apply)

Before deploying the GitOps tree, apply the External Secrets Operator CRDs to avoid OpenAPI size limits:

```bash
kubectl --context admin@<cluster> apply --server-side -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml
```

---

### Step 8: Bootstrap Flux GitOps & Platform Stack

Because the repository is public, **no SSH keys or GitHub tokens are required**.

> [!IMPORTANT]
> Ensure your working directory is the repository root:
> ```bash
> cd /home/gabriel/HomeLab
> ```

#### For Cluster 1 (`k8s-talos-1`):
```bash
# 1. Install Flux namespace, CRDs, and controllers
kubectl --context admin@k8s-talos-1 apply -f K8s/clusters/k8s-talos-1/flux-system/gotk-components.yaml

# 2. Apply the cluster synchronization overlay
kubectl --context admin@k8s-talos-1 apply -k K8s/clusters/k8s-talos-1
```

#### For Cluster 2 (`k8s-talos-2`):
```bash
# 1. Install Flux namespace, CRDs, and controllers
kubectl --context admin@k8s-talos-2 apply -f K8s/clusters/k8s-talos-2/flux-system/gotk-components.yaml

# 2. Apply the cluster synchronization overlay
kubectl --context admin@k8s-talos-2 apply -k K8s/clusters/k8s-talos-2
```

**What happens automatically:**
1. Flux starts up in the `flux-system` namespace.
2. Flux pulls `https://github.com/GabrielJean/HomeLab.git` anonymously over HTTPS.
3. Flux reconciles [`K8s/infrastructure/`](infrastructure/):
   - **Local Path Provisioner**: host storage for volumes.
   - **Traefik Controller**: Gateway API implementation binding ports 80 and 443.
   - **Metrics Server**: API metrics for `kubectl top`.
   - **External Secrets Operator**: Authenticates to Azure Key Vault via secretless Workload Identity.
   - **ClusterSecrets**: ESO pulls `headlamp-admin-email` and writes Secret `flux-system/cluster-secrets`.
   - **Headlamp**: ESO pulls `headlamp-oidc-client-secret` and starts the Headlamp dashboard.
   - **Dynamic RBAC**: Flux substitutes `${OIDC_ADMIN_EMAIL}` into `oidc-rbac.yaml`, binding `cluster-admin` to your email.
4. Flux reconciles cluster-specific applications under [`K8s/apps/`](apps/).

---

## Verification & Day-to-Day Operations

### 1. Verify Flux Reconciliation
```bash
kubectl --context admin@<cluster> -n flux-system get kustomizations
```
All entries (`flux-system`, `infrastructure`, `apps`) should report **`READY: True`**.

### 2. Verify External Secrets & Key Vault Sync
```bash
kubectl --context admin@<cluster> get externalsecrets -A
```
Expected output:
```text
NAMESPACE     NAME              STORETYPE            STORE            STATUS         READY   LAST SYNC
flux-system   cluster-secrets   ClusterSecretStore   azure-keyvault   SecretSynced   True    1m
headlamp      headlamp-oidc     ClusterSecretStore   azure-keyvault   SecretSynced   True    1m
```

### 3. Verify Dynamic RBAC Binding
Verify that your email was injected into `oidc-admin` without appearing in Git:
```bash
kubectl --context admin@<cluster> get clusterrolebinding oidc-admin -o jsonpath='{.subjects}'
```

### 4. Log Into Headlamp Web Dashboard
- **Web UI**: Navigate to `https://headlamp.<cluster>.gwebs.ca` in your browser.
- Click **Log in with Microsoft** and authenticate with your Entra ID credentials.
- Full cluster visibility and a dedicated **Flux** GitOps sidebar tab will be available.

#### Emergency Breakglass Token (Offline / Recovery)
If Microsoft Entra ID or external WAN is ever offline, log in using the static breakglass token:
```bash
kubectl --context admin@<cluster> get secret -n headlamp headlamp-breakglass-token -o jsonpath='{.data.token}' | base64 --decode
echo ""
```

---

## Secret Expiration & Maintenance Runbook

> [!WARNING]
> **Client Secret Expiration**:
> The Entra ID client secret (`headlamp-oidc-client-secret`) is valid until **October 23, 2028**.

If authentication suddenly fails:
1. **Symptom**: Microsoft returns error `AADSTS7000222` ("The provided client secret keys are expired").
2. **Immediate Access**: Use the breakglass token above to access Headlamp.
3. **Renewal Procedure**:
   - In Microsoft Entra ID App Registration ➔ **Certificates & secrets** ➔ **+ New client secret**.
   - Copy the value.
   - In Azure Key Vault (`gjtaloskv`) ➔ **Secrets** ➔ `headlamp-oidc-client-secret` ➔ **+ New version** and paste the value.
   - ESO will automatically sync the new secret within 1 hour (or run `kubectl annotate externalsecret -n headlamp headlamp-oidc force-sync=$(date +%s) --overwrite`).
   - Restart Headlamp: `kubectl rollout restart deployment/headlamp -n headlamp`.

---

## Summary Cheat Sheet

| Task | Cluster 1 (`k8s-talos-1`) | Cluster 2 (`k8s-talos-2`) |
| :--- | :--- | :--- |
| **Sync Omni Template** | `omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-1.yaml` | `omnictl cluster template sync -f K8s/Omni/clusters/k8s-talos-2.yaml` |
| **Fetch Kubeconfig** | `omnictl kubeconfig -c k8s-talos-1 --service-account --user admin --force-context-name admin@k8s-talos-1 --force` | `omnictl kubeconfig -c k8s-talos-2 --service-account --user admin --force-context-name admin@k8s-talos-2 --force` |
| **Pre-Apply CRDs** | `kubectl apply --server-side -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml` | *(Same command on context)* |
| **Bootstrap GitOps** | `kubectl apply -f K8s/clusters/k8s-talos-1/flux-system/gotk-components.yaml && kubectl apply -k K8s/clusters/k8s-talos-1` | `kubectl apply -f K8s/clusters/k8s-talos-2/flux-system/gotk-components.yaml && kubectl apply -k K8s/clusters/k8s-talos-2` |
| **Check Secrets Sync** | `kubectl get externalsecrets -A` | `kubectl get externalsecrets -A` |
| **Get Breakglass Token** | `kubectl -n headlamp get secret headlamp-breakglass-token -o jsonpath='{.data.token}' \| base64 -d` | *(Same command on context)* |
| **Deploy Any Workload** | Commit & push to `main` | Commit & push to `main` |

---

## Documentation & Component Reference

* **Cluster Management & Bootstrapping**:
  * [`K8s/Bootstrap.md`](Bootstrap.md) — Main end-to-end bootstrap walkthrough.
  * [`K8s/PLAN.md`](PLAN.md) — Architectural design and phased migration plan from Docker Compose.
  * [`K8s/Omni/README.md`](Omni/README.md) — Machine classes, media presets, site routing patches, and Omni cluster templates.
  * [`K8s/clusters/README.md`](clusters/README.md) — Independent Flux cluster overlays, dynamic substitutions, and root synchronization.
* **Platform Infrastructure Guides (`infrastructure/`)**:
  * [`K8s/infrastructure/external-secrets/README.md`](infrastructure/external-secrets/README.md) — External Secrets Operator, Azure Key Vault, Workload Identity federation, and renewal runbook.
  * [`K8s/infrastructure/headlamp/README.md`](infrastructure/headlamp/README.md) — Headlamp web dashboard, Microsoft Entra ID OIDC SSO, and breakglass recovery.
  * [`K8s/infrastructure/traefik/README.md`](infrastructure/traefik/README.md) — Traefik ingress & Gateway API controller routing host ports 80/443.
  * [`K8s/infrastructure/gateway-api/README.md`](infrastructure/gateway-api/README.md) — Kubernetes Gateway API CRDs and listeners.
  * [`K8s/infrastructure/metrics-server/README.md`](infrastructure/metrics-server/README.md) — Metrics Server deployment for pod resource utilization.
  * [`K8s/infrastructure/storage/local-path/README.md`](infrastructure/storage/local-path/README.md) — Local Path Provisioner host-path storage class.
* **Application Workloads (`apps/`)**:
  * [`K8s/apps/`](apps/) — Workload manifests separated into shared templates (`base/`) and cluster overlays (`k8s-talos-1/`, `k8s-talos-2/`).

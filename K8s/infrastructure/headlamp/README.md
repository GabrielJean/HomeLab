# Headlamp Kubernetes Dashboard

In-cluster deployment configuration for [Headlamp](https://github.com/kubernetes-sigs/headlamp) (Kubernetes SIG UI) in the Homelab Talos Kubernetes infrastructure.

Headlamp provides a developer-friendly, extensible web dashboard for monitoring workloads, viewing live pod logs, inspecting events, and managing Kubernetes resources across the clusters.

---

## Component Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Project** | [kubernetes-sigs/headlamp](https://github.com/kubernetes-sigs/headlamp) | Official Kubernetes SIG UI dashboard |
| **App Version** | `v0.46.0` | Latest release |
| **Container Image** | `ghcr.io/headlamp-k8s/headlamp:v0.46.0` | Multi-arch Linux container image |
| **Flux Plugin Image** | `ghcr.io/headlamp-k8s/headlamp-plugin-flux:v0.7.0` | Pre-loaded via initContainer |
| **Namespace** | `headlamp` | Dedicated platform namespace |
| **Service Port** | `80` (targets `4466`) | HTTP ClusterIP |
| **Ingress Host** | `headlamp.${CLUSTER_NAME}.gwebs.ca` | `headlamp.talos-1.gwebs.ca` or `headlamp.talos-2.gwebs.ca` via Flux substitution |

---

## Directory Structure

```text
infrastructure/headlamp/
├── README.md                      # Documentation & operational guide
├── namespace.yaml                 # Dedicated 'headlamp' namespace
├── service-account.yaml           # ServiceAccount for Headlamp pod
├── cluster-role-binding.yaml      # ClusterRoleBinding granting cluster inspection
├── deployment.yaml                # Headlamp v0.46.0 + Flux plugin initContainer
├── service.yaml                   # ClusterIP service on port 80 (targets 4466)
├── ingress.yaml                   # Traefik Ingress with cert-manager TLS
├── rbac-admin.yaml                # Admin ServiceAccount, ClusterRoleBinding & login token
└── kustomization.yaml             # Kustomize entrypoint bundling all manifests
```

---

## How Plugins Work (The InitContainer Pattern)

In-cluster Headlamp runs in an immutable container environment. Frontend plugins cannot be downloaded via web UI clicks.

Instead, we use the official **`initContainer` + shared `emptyDir` volume** pattern in [`deployment.yaml`](deployment.yaml):

```yaml
volumes:
  - name: plugins-dir
    emptyDir: {}

initContainers:
  - name: install-flux-plugin
    image: ghcr.io/headlamp-k8s/headlamp-plugin-flux:v0.7.0
    command: ["/bin/sh", "-c"]
    args:
      - mkdir -p /headlamp/plugins && cp -r /plugins/* /headlamp/plugins/
    volumeMounts:
      - name: plugins-dir
        mountPath: /headlamp/plugins

containers:
  - name: headlamp
    image: ghcr.io/headlamp-k8s/headlamp:v0.46.0
    args:
      - "-in-cluster"
      - "-plugins-dir=/headlamp/plugins"
    volumeMounts:
      - name: plugins-dir
        mountPath: /headlamp/plugins
```

### Benefits:
1. **Deterministic & Declarative**: The plugin version is an immutable container image tag committed to Git.
2. **Rock Solid**: Images are cached on the Talos node disk. Pod reboots never fail if Artifact Hub or an external site is down.
3. **Zero Persistent Memory Overhead**: The init container runs for 1 second to copy files, then exits cleanly. No continuous Node.js sidecar wasting RAM.

---

## Deployment Methods

### 1. GitOps with Flux CD (Recommended)

As outlined in [`PLAN.md`](../../PLAN.md), platform services are managed via Flux CD.

Add the Headlamp Kustomization to your cluster overlay (e.g. `K8s/clusters/k8s-talos-1/infrastructure.yaml`):

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-headlamp
  namespace: flux-system
spec:
  interval: 1h
  path: ./K8s/infrastructure/headlamp
  prune: true
  sourceRef:
    kind: GitRepository
    name: homelab-repo
```

Flux's `kustomize-controller` automatically reconciles all manifests in this folder with automated drift detection and pruning.

---

### 2. Direct Kustomize / `kubectl` Deployment

To test or deploy directly without a GitOps controller:

```bash
kubectl apply -k K8s/infrastructure/headlamp
```

---

## Access & Authentication

### 1. Ingress URL
Once Traefik and cert-manager are running, access Headlamp securely via HTTPS:
- **Home 1 (`k8s-talos-1`)**: `https://headlamp.talos-1.gwebs.ca`
- **Home 2 (`k8s-talos-2`)**: `https://headlamp.talos-2.gwebs.ca`

### 2. Local Port-Forward (Emergency or Pre-Ingress)
```bash
kubectl -n headlamp port-forward svc/headlamp 8080:80
```
Then navigate to: `http://localhost:8080`

### 3. Retrieving the Admin Login Token

Headlamp prompts for a Kubernetes Bearer token upon initial login. Retrieve the pre-provisioned static admin token:

```bash
kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d
```

Or generate an ephemeral time-limited token on demand:
```bash
kubectl -n headlamp create token headlamp-admin --duration=24h
```

Paste the token into the Headlamp authentication prompt.

---

## Microsoft Entra ID (OIDC) Single Sign-On

To enable single sign-on with your homelab Entra ID tenant:

1. Register an application in Microsoft Entra ID:
   - **Redirect URI (Web)**: `https://headlamp.talos-1.gwebs.ca/oidc-callback` (and/or `https://headlamp.talos-2.gwebs.ca/oidc-callback`)
   - Note the **Client ID**, **Tenant ID**, and generate a **Client Secret**.
2. In [`deployment.yaml`](deployment.yaml), uncomment the OIDC container arguments:
   ```yaml
   args:
     - "-in-cluster"
     - "-plugins-dir=/headlamp/plugins"
     - "-oidc-idp-issuer-url=https://login.microsoftonline.com/<TENANT_ID>/v2.0"
     - "-oidc-client-id=<ENTRA_CLIENT_ID>"
     - "-oidc-client-secret=<ENTRA_CLIENT_SECRET>" # Or inject from Azure Key Vault via ESO
     - "-oidc-scopes=openid,profile,email,offline_access"
     - "-oidc-use-pkce=true"
   ```
3. When using **External Secrets Operator (ESO)**:
   - Store the client secret in Azure Key Vault.
   - ESO creates a native Kubernetes `Secret` in namespace `headlamp`.
   - Mount the secret as an environment variable (`HEADLAMP_CONFIG_OIDC_CLIENT_SECRET`).

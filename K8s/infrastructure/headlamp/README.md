# Headlamp Kubernetes Dashboard

In-cluster deployment configuration for [Headlamp](https://github.com/kubernetes-sigs/headlamp) (official Kubernetes SIG UI) in the Homelab Talos Kubernetes infrastructure.

Headlamp provides a clean, extensible, multi-cluster web dashboard for monitoring workloads, viewing live pod logs and metrics, inspecting events, and managing Kubernetes resources across the clusters.

---

## Component Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Project** | [kubernetes-sigs/headlamp](https://github.com/kubernetes-sigs/headlamp) | Official Kubernetes SIG UI dashboard |
| **Helm Chart** | `headlamp` (`0.46.0`) | Repository: `https://kubernetes-sigs.github.io/headlamp/` |
| **App Version** | `v0.46.0` | Latest stable release |
| **Container Image** | `ghcr.io/headlamp-k8s/headlamp:v0.46.0` | Multi-arch Linux container image |
| **Flux Plugin Image** | `ghcr.io/headlamp-k8s/headlamp-plugin-flux:v0.7.0` | Pre-loaded via initContainer |
| **Namespace** | `headlamp` | Dedicated platform namespace |
| **Routing** | `headlamp.${CLUSTER_NAME}.gwebs.ca` | Kubernetes Gateway API `HTTPRoute` attached to `traefik-gateway` |
| **Authentication** | Microsoft Entra ID (Azure AD) OIDC SSO | With `headlamp-breakglass` ServiceAccount fallback token |

---

## Directory Structure

```text
infrastructure/headlamp/
├── README.md                      # Documentation & operational guide
├── namespace.yaml                 # Dedicated 'headlamp' namespace
├── helmrepository.yaml            # Official Headlamp Helm repository
├── helmrelease.yaml               # Headlamp HelmRelease (v0.46.0, Flux plugin, Gateway API, OIDC)
├── oidc-rbac.yaml                 # ClusterRoleBinding granting cluster-admin to Entra ID users
├── rbac-admin.yaml                # Emergency breakglass ServiceAccount & static token
└── kustomization.yaml             # Kustomize entrypoint bundling all manifests
```

---

## Microsoft Entra ID (Azure AD) SSO Configuration

Headlamp is configured to authenticate users via Microsoft Entra ID (Azure AD) using OpenID Connect (OIDC). When a user logs in, Headlamp passes the Entra ID bearer token directly to the Kubernetes API server (`kube-apiserver`), which validates the token against Entra ID and authorizes permissions via Kubernetes RBAC.

### Azure App Registration Parameters

- **Application (client) ID**: `e1d55ddd-3453-4a91-9842-aa7d7dc620a3`
- **Object ID**: `bff2982d-ebce-4ded-8ddd-527d9a2193bd`
- **Directory (tenant) ID**: `10b7061b-f2d0-4778-8cae-2666faf4af25`
- **Issuer URL**: `https://login.microsoftonline.com/10b7061b-f2d0-4778-8cae-2666faf4af25/v2.0`

### Step-by-Step Azure Portal Setup

1. **Authentication (Redirect URIs)**:
   - Navigate to **Microsoft Entra ID** > **App registrations** > select the Headlamp app (`e1d55ddd-3453-4a91-9842-aa7d7dc620a3`).
   - Under **Manage**, select **Authentication**.
   - Click **Add a platform** > select **Web**.
   - Add the following **Redirect URIs**:
     - `https://headlamp.talos-1.gwebs.ca/oidc-callback`
     - `https://headlamp.talos-2.gwebs.ca/oidc-callback`
   - Under **Implicit grant and hybrid flows**, enable **ID tokens (used for implicit and hybrid flows)**.
   - Click **Save**.

2. **Certificates & Secrets**:
   - Under **Manage**, select **Certificates & secrets** > **Client secrets**.
   - Click **New client secret**, enter a description (e.g. `headlamp-sso`), and choose an expiration period.
   - Copy the **Value** immediately. Set this secret in `K8s/infrastructure/headlamp/helmrelease.yaml` under `config.oidc.clientSecret` (or into Kubernetes Secret `headlamp-oidc`).

3. **API Permissions**:
   - Under **Manage**, select **API permissions**.
   - Ensure the following Microsoft Graph delegated permissions are added:
     - `openid`
     - `profile`
     - `email`
     - `offline_access`
   - Click **Grant admin consent for <Tenant>** if prompted.

4. **Token Configuration**:
   - Under **Manage**, select **Token configuration**.
   - Click **Add optional claim**:
     - Token type: **ID**
     - Select: `email`, `preferred_username`
     - Click **Add**.
   - Click **Add groups claim**:
     - Select: **Security groups**
     - Click **Add**.

---

## Talos Linux API Server Configuration

For Kubernetes to accept and authorize Entra ID tokens passed by Headlamp, the `kube-apiserver` must trust Entra ID as an OIDC issuer.

This is managed natively via Omni cluster template patch `K8s/Omni/clusters/patches/oidc.yaml`:

```yaml
apiVersion: v1alpha1
kind: KubeAPIServerConfig
extraArgs:
  oidc-issuer-url: "https://login.microsoftonline.com/10b7061b-f2d0-4778-8cae-2666faf4af25/v2.0"
  oidc-client-id: "e1d55ddd-3453-4a91-9842-aa7d7dc620a3"
  oidc-username-claim: "email"
  oidc-groups-claim: "groups"
```

Applied to both `k8s-talos-1` and `k8s-talos-2` via `omnictl cluster template sync`.

---

## Cluster RBAC Access

Permissions are granted using Kubernetes `ClusterRoleBinding` resources:

- **OIDC Administrator Binding** ([`oidc-rbac.yaml`](oidc-rbac.yaml)):
  Grants `cluster-admin` to the Entra ID user identity configured via `${OIDC_ADMIN_EMAIL}`.
- **Emergency Breakglass Binding** ([`rbac-admin.yaml`](rbac-admin.yaml)):
  Provides a static ServiceAccount `headlamp-breakglass` and Secret `headlamp-breakglass-token` for emergency cluster recovery when OIDC or external internet is unavailable.

### Retrieving the Breakglass Token

If OIDC is ever offline, log in with the breakglass token:

```bash
kubectl get secret -n headlamp headlamp-breakglass-token -o jsonpath='{.data.token}' | base64 --decode
echo ""
```
Paste this token into the Headlamp login page to regain full administrative control.

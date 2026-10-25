# External Secrets Operator (Azure Key Vault & Workload Identity)

Cluster-wide secrets management subsystem for the Homelab Talos Kubernetes infrastructure, powered by the [External Secrets Operator (ESO)](https://external-secrets.io/) and Microsoft Azure Key Vault.

This subsystem provides **100% secretless GitOps**: no static API keys, service account credentials, cloud passwords, or personal identity details (e.g. administrator emails) are stored in Git. All sensitive credentials reside exclusively in Azure Key Vault and are synchronized dynamically into Kubernetes Secrets via passwordless **Microsoft Entra Workload Identity Federation**.

---

## Table of Contents

- [Component Details](#component-details)
- [Architecture: Secretless Workload Identity Federation](#architecture-secretless-workload-identity-federation)
  - [Trust Chain Workflow](#trust-chain-workflow)
- [Directory Structure](#directory-structure)
- [Secrets Managed in Azure Key Vault](#secrets-managed-in-azure-key-vault)
- [Secret Lifecycle, Expiration & Failure Runbook](#secret-lifecycle-expiration--failure-runbook)
  - [How to Diagnose an Expired or Broken Secret](#how-to-diagnose-an-expired-or-broken-secret)
- [Integration with Flux CD (Dynamic Variable Substitution)](#integration-with-flux-cd-dynamic-variable-substitution)
- [Operational Verification & Troubleshooting](#operational-verification--troubleshooting)
  - [1. Check Operator Pods](#1-check-operator-pods)
  - [2. Check ClusterSecretStore Status](#2-check-clustersecretstore-status)
  - [3. Check ExternalSecret Synchronization](#3-check-externalsecret-synchronization)
  - [4. Verify Generated Kubernetes Secrets](#4-verify-generated-kubernetes-secrets)
  - [5. View Operator Logs](#5-view-operator-logs)

---

## Component Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Project** | [external-secrets/external-secrets](https://github.com/external-secrets/external-secrets) | Kubernetes SIG / CNCF Sandbox operator |
| **Helm Chart** | `external-secrets` (`2.14.0`) | Repository: `https://charts.external-secrets.io` |
| **Namespace** | `external-secrets` | Dedicated platform namespace |
| **Authentication Type** | `WorkloadIdentity` (Path 2 - Secretless) | Passwordless OIDC token exchange via Kubernetes `TokenRequest` |
| **Key Vault URL** | `https://gjtaloskv.vault.azure.net/` | Azure Key Vault instance |
| **Azure Tenant ID** | `10b7061b-f2d0-4778-8cae-2666faf4af25` | Microsoft Entra ID Directory |
| **Azure Client ID** | `e1d55ddd-3453-4a91-9842-aa7d7dc620a3` | Application registration client ID |
| **OIDC Storage Account**| `https://gjtalossa.blob.core.windows.net/oidc/` | Public discovery documents & JWKS hosting |

---

## Architecture: Secretless Workload Identity Federation

```text
  +---------------------------------------------------------------------------------+
  |                             Talos Linux Node                                    |
  |                                                                                 |
  |  +---------------------+        TokenRequest API         +-------------------+  |
  |  |   kube-apiserver    | <------------------------------ | External Secrets  |  |
  |  | (issues signed JWT) |                                 |     Operator      |  |
  |  +----------+----------+                                 +---------+---------+  |
  +-------------|------------------------------------------------------|------------+
                |                                                      |
                | (OIDC Discovery URL)                                 | (Presents SA JWT)
                v                                                      v
  +-------------------------------------+            +---------------------------------+
  |      Azure Blob Storage (oidc)      |            |    Microsoft Entra ID (STS)     |
  |   https://gjtalossa.blob.core...    |            |   login.microsoftonline.com     |
  |                                     |            |                                 |
  |  - /.well-known/openid-configuration| <--------- | Validates JWT against cluster   |
  |  - /openid/v1/jwks                  |  (Fetches  | public keys in JWKS container   |
  |    (Public keys for talos-1/talos-2)|    keys)   +----------------+----------------+
  +-------------------------------------+                             |
                                                                      | (Issues Azure Token)
                                                                      v
                                                     +---------------------------------+
                                                     |        Azure Key Vault          |
                                                     |   https://gjtaloskv.vault...    |
                                                     |                                 |
                                                     | Grants access to ESO via RBAC / |
                                                     | Entra Federated Credential      |
                                                     +----------------+----------------+
                                                                      |
                                                                      | (Pulls Secrets)
                                                                      v
  +---------------------------------------------------------------------------------+
  |                             Target Cluster Namespaces                           |
  |                                                                                 |
  |  Namespace: headlamp         ---> Secret: headlamp-oidc (Client Secret)         |
  |  Namespace: flux-system      ---> Secret: cluster-secrets (OIDC Admin Email)    |
  +---------------------------------------------------------------------------------+
```

### Trust Chain Workflow
1. **Talos SA Issuer**: The Talos control plane is configured via `KubeServiceAccountConfig` with an external `issuerURL` pointing to Azure Blob Storage:
   - `talos-1`: `https://gjtalossa.blob.core.windows.net/oidc/talos-1`
   - `talos-2`: `https://gjtalossa.blob.core.windows.net/oidc/talos-2`
2. **Public Discovery Documents**: The Azure Blob Storage container `oidc` publicly hosts the `.well-known/openid-configuration` and `openid/v1/jwks` containing each cluster's active public RSA signing keys.
3. **Entra Federated Credential**: Azure Entra ID App Registration (`e1d55ddd-3453-4a91-9842-aa7d7dc620a3`) has a **Federated Identity Credential**:
   - **Issuer**: `https://gjtalossa.blob.core.windows.net/oidc/talos-1` (and `talos-2`)
   - **Subject**: `system:serviceaccount:external-secrets:external-secrets`
   - **Audience**: `api://AzureADTokenExchange`
4. **Token Exchange**: When ESO connects to Azure Key Vault, it requests a projected ServiceAccount token from `kube-apiserver` and sends it to Entra ID STS (`login.microsoftonline.com`). Entra ID verifies the token signature against the public JWKS on Azure Blob Storage and returns an Azure AD access token.
5. **Key Vault Retrieval**: ESO uses the access token to fetch secrets directly from `gjtaloskv` and writes them into native Kubernetes Secrets.

---

## Directory Structure

```text
infrastructure/external-secrets/
├── README.md                      # Operational and architecture guide
├── namespace.yaml                 # Dedicated 'external-secrets' namespace
├── helmrepository.yaml            # Official ESO Helm repository (charts.external-secrets.io)
├── helmrelease.yaml               # HelmRelease (v2.14.0, Workload Identity annotations)
├── cluster-secret-store.yaml      # ClusterSecretStore 'azure-keyvault' (WorkloadIdentity)
├── cluster-secrets.yaml           # ExternalSecret syncing admin email to 'flux-system'
└── kustomization.yaml             # Kustomize entrypoint bundling all manifests
```

---

## Secrets Managed in Azure Key Vault

The following secrets must exist in Azure Key Vault (`https://gjtaloskv.vault.azure.net/`):

| Secret Name in Key Vault | Target Kubernetes Secret | Target Namespace | Expiration | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`headlamp-oidc-client-secret`** | `headlamp-oidc` (`OIDC_CLIENT_SECRET`) | `headlamp` | **Oct 23, 2028** | Client secret required by Headlamp backend for the `/oidc-callback` authorization code exchange with Microsoft Entra ID. |
| **`headlamp-admin-email`** | `cluster-secrets` (`OIDC_ADMIN_EMAIL`) | `flux-system` | Never | Admin email address injected dynamically into Kubernetes RBAC (`oidc-admin` ClusterRoleBinding) so personal emails never appear in Git. |

---

## Secret Lifecycle, Expiration & Failure Runbook

> [!WARNING]
> **Client Secret Expiration Notice**:
> The Microsoft Entra ID Client Secret (`headlamp-oidc-client-secret`) is valid until **October 23, 2028**.
> If authentication suddenly fails around or after this date, consult the diagnostics below.

### How to Diagnose an Expired or Broken Secret

1. **Check External Secrets Operator status**:
   ```bash
   kubectl get externalsecrets -A
   ```
   If Key Vault cannot be contacted or the secret name is wrong, `STATUS` displays `SecretSyncedError` and `READY` is `False`.
2. **Check Headlamp Backend logs**:
   ```bash
   kubectl logs -n headlamp -l app.kubernetes.io/name=headlamp --tail=50
   ```
   If the Entra ID client secret has expired, Microsoft returns:
   `AADSTS7000222: The provided client secret keys are expired. Visit the Azure portal to create new keys for your app...`
3. **Emergency Recovery (Breakglass)**:
   If Entra ID login fails due to an expired secret, log into Headlamp immediately using the breakglass token:
   ```bash
   kubectl get secret -n headlamp headlamp-breakglass-token -o jsonpath='{.data.token}' | base64 --decode
   echo ""
   ```
4. **Renewal Procedure (When October 2028 arrives)**:
   1. Open **Microsoft Entra ID** ➔ **App registrations** ➔ `e1d55ddd-3453-4a91-9842-aa7d7dc620a3`.
   2. Navigate to **Certificates & secrets** ➔ **+ New client secret**.
   3. Copy the new secret **Value**.
   4. Open **Azure Key Vault** (`gjtaloskv`) ➔ **Secrets** ➔ `headlamp-oidc-client-secret` ➔ **+ New version**.
   5. Paste the new secret value and click **Create**.
   6. ESO automatically detects and updates the Kubernetes Secret (or run `kubectl annotate externalsecret -n headlamp headlamp-oidc force-sync=$(date +%s) --overwrite`).
   7. Restart the Headlamp pod: `kubectl rollout restart deployment/headlamp -n headlamp`.

---

## Integration with Flux CD (Dynamic Variable Substitution)

To guarantee that private user identities and emails never touch Git, this cluster uses Flux's post-build variable substitution powered by External Secrets:

1. **Secret Synchronization**:
   [`cluster-secrets.yaml`](cluster-secrets.yaml) synchronizes `headlamp-admin-email` from Key Vault into Secret `cluster-secrets` in the `flux-system` namespace:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: cluster-secrets
     namespace: flux-system
   spec:
     secretStoreRef:
       name: azure-keyvault
       kind: ClusterSecretStore
     target:
       name: cluster-secrets
     data:
       - secretKey: OIDC_ADMIN_EMAIL
         remoteRef:
           key: headlamp-admin-email
   ```

2. **Flux Kustomization PostBuild Substitution**:
   In `K8s/clusters/k8s-talos-1/infrastructure.yaml` and `k8s-talos-2/infrastructure.yaml`:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: infrastructure
     namespace: flux-system
   spec:
     postBuild:
       substitute:
         CLUSTER_NAME: talos-1
       substituteFrom:
         - kind: Secret
           name: cluster-secrets
           optional: true
   ```

3. **Manifest Injection**:
   In [`K8s/infrastructure/headlamp/oidc-rbac.yaml`](../headlamp/oidc-rbac.yaml):
   ```yaml
   subjects:
     - kind: User
       name: "${OIDC_ADMIN_EMAIL:=admin@example.com}"
       apiGroup: rbac.authorization.k8s.io
   ```
   At deployment time, Flux reads `OIDC_ADMIN_EMAIL` from `Secret/cluster-secrets` and binds `cluster-admin` privileges to the real administrator email.

---

## Operational Verification & Troubleshooting

### 1. Check Operator Pods
```bash
kubectl get pods -n external-secrets
```
Expected output:
```text
NAME                                                READY   STATUS    RESTARTS   AGE
external-secrets-76ccc4969-zxk8b                    1/1     Running   0          5m
external-secrets-cert-controller-6f58665688-dww57   1/1     Running   0          5m
external-secrets-webhook-745bbf55b6-hbr4d           1/1     Running   0          5m
```

### 2. Check ClusterSecretStore Status
```bash
kubectl get clustersecretstore azure-keyvault
```
Expected output:
```text
NAME             AGE   STATUS   CAPABILITIES   READY
azure-keyvault   5m    Valid    ReadWrite      True
```
If `READY` is `False`, inspect details:
```bash
kubectl describe clustersecretstore azure-keyvault
```

### 3. Check ExternalSecret Synchronization
```bash
kubectl get externalsecrets -A
```
Expected output once Key Vault secrets are populated:
```text
NAMESPACE     NAME              STORETYPE            STORE            REFRESH INTERVAL   STATUS         READY   LAST SYNC
flux-system   cluster-secrets   ClusterSecretStore   azure-keyvault   1h                 SecretSynced   True    1m
headlamp      headlamp-oidc     ClusterSecretStore   azure-keyvault   1h                 SecretSynced   True    1m
```

### 4. Verify Generated Kubernetes Secrets
```bash
# Verify headlamp-oidc secret
kubectl get secret -n headlamp headlamp-oidc -o yaml

# Verify cluster-secrets secret in flux-system
kubectl get secret -n flux-system cluster-secrets -o yaml
```

### 5. View Operator Logs
```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f
```


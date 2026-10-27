# Flux Pushover Notifications

Real-time push notifications sent directly to your phone and desktop via **Pushover** whenever Flux encounters a reconciliation error.

---

## Architecture

- **`Provider` (`pushover`)**: Uses Flux's `generic` webhook provider. Pointed to Pushover's REST API (`https://api.pushover.net/1/messages.json`).
- **`Alert` (`pushover-alerts`)**: Filters for `error` severity events across:
  - All `Kustomization` resources in `flux-system`
  - All `HelmRelease` resources cluster-wide (`*`)
  - All `GitRepository` and `HelmRepository` sources
- **Dynamic Cluster Identification**: The notification title is dynamically formatted as `[${CLUSTER_NAME}] Flux Reconciliation Failure` via Flux variable substitution so you know immediately which home cluster raised the alert.
- **`ExternalSecret` (`pushover-credentials`)**: Connects to Azure Key Vault (`gjtaloskv`) via passwordless Workload Identity to fetch your `pushover-token` and `pushover-user-key`, templating the API URL without storing credentials in Git.

---

## Azure Key Vault Configuration

Add the following two secrets in **Azure Key Vault** (`gjtaloskv`):

| Secret Name | Value | Purpose |
| :--- | :--- | :--- |
| **`pushover-token`** | *Application API Token* | Generated in Pushover dashboard under "Your Applications" |
| **`pushover-user-key`** | *User / Group Key* | 30-character key on your Pushover dashboard homepage |

---

## Directory Structure

```
├── provider.yaml         # Flux Provider (type: generic)
├── alert.yaml            # Flux Alert targeting error events
├── external-secret.yaml  # ESO templating Pushover API URL from Key Vault
├── kustomization.yaml    # Kustomize aggregation
└── README.md             # Documentation
```

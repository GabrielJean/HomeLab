# Tailscale Kubernetes Operator

Integrates the Kubernetes cluster with Tailnet connectivity, providing Tailscale Ingress, Egress, and Funnel capabilities without requiring public cloud load balancers or open firewall ports.

---

## Architecture

- **Helm Chart**: `tailscale-operator` (`1.104.4`) from `https://pkgs.tailscale.com/helmcharts`.
- **Namespace**: `tailscale` (privileged PSS enabled for host networking and raw network capabilities).
- **Authentication**: ExternalSecret (`operator-oauth` in `K8s/infrastructure/configs/tailscale/`) syncing Tailscale OAuth credentials directly from Azure Key Vault (`gjtaloskv`) via `azure-keyvault` `ClusterSecretStore`:
  - `tailscale-k8s-client-id` -> `client_id`
  - `tailscale-k8s-secret` -> `client_secret`
- **RBAC & Tags**: Operator runs with `tag:k8s-operator` and manages child proxies tagged `tag:k8s`.
- **Public Exposure**: Workloads with annotation `tailscale.com/funnel: "true"` on a Tailscale Ingress are exposed to the public internet via Tailscale Funnel.
- **Site-to-Site LAN VPN**: Standalone `hostNetwork: true` router deployed via `K8s/infrastructure/configs/tailscale/` (see [`configs/tailscale/README.md`](../../configs/tailscale/README.md)).

---

## Directory Structure

```
├── helmrelease.yaml      # Operator HelmRelease
├── helmrepository.yaml   # Official Tailscale Helm chart repo
├── kustomization.yaml    # Kustomize manifest definitions
├── namespace.yaml        # 'tailscale' namespace with privileged PSS labels
└── README.md             # Documentation
```

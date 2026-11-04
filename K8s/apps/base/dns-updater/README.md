# Azure DNS Dynamic DNS (DDNS) Updater

Kubernetes CronJob that automatically detects your home WAN public IP (`http://ifconfig.me`) and synchronizes it with Azure DNS for your game servers and hostnames.

---

## Architecture

- **Execution Model**: Runs as a lightweight Kubernetes `CronJob` every 15 minutes (`*/15 * * * *`).
- **Zero Image Builds**: Uses the official upstream `mcr.microsoft.com/azure-cli:2.91.0` image, mounting `update_dns.sh` from a dedicated script in [`scripts/`](scripts/) via Kustomize `configMapGenerator` with executable permissions (`0755`).
- **Automatic Hash Tracking**: Whenever `update_dns.sh` or configuration parameters change, Kustomize recalculates the ConfigMap hash and updates the CronJob's `jobTemplate`, ensuring subsequent runs immediately use the new script and configs without stale cache.
- **Cluster Assignment**: Runs **exclusively on `k8s-talos-1`** (Home 1) to track the primary home ISP IP address without conflicting with other sites.
- **Zero Secrets in Git**: Authenticates to Azure DNS via Service Principal `k8s-app` (`AZURE_APP_ID: e1d55ddd-3453-4a91-9842-aa7d7dc620a3`), pulling client secrets securely from Azure Key Vault via `ExternalSecrets`.

---

## Managed DNS Records

- **Main `A` Record**: `gaming.gwebs.ca` (TTL 300s)
- **`CNAME` Aliases**:
  - `satisfactory.gwebs.ca` -> `gaming.gwebs.ca`
  - `astroneer.gwebs.ca` -> `gaming.gwebs.ca`
  - `zomboid.gwebs.ca` -> `gaming.gwebs.ca`

---

## Directory Structure

```
├── scripts/              # Shell scripts mounted into containers
│   └── update_dns.sh     # Azure DNS synchronization script
├── namespace.yaml        # 'dns-updater' namespace
├── external-secret.yaml  # Syncs AZURE_SECRET from Azure Key Vault
├── cronjob.yaml          # Scheduled CronJob (runs every 15 minutes)
├── kustomization.yaml    # Kustomize aggregation & configMapGenerator
└── README.md             # Component documentation
```

---

## Manual Execution / Testing

To immediately trigger a manual run without waiting for the 15-minute cron schedule:

```bash
kubectl create job --from=cronjob/dns-updater manual-sync-1 -n dns-updater
kubectl logs -n dns-updater job/manual-sync-1 -f
```


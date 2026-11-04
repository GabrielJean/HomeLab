# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is an open-source, autonomous AI agent framework developed by Nous Research. It features persistent memory across sessions, self-evolving skill creation, multi-platform gateway messaging, and an OpenAI-compatible API server.

---

## Architecture

- **Workload Type**: Single-replica Kubernetes `Deployment` with `Recreate` strategy.
- **Topology**: Deployed on `k8s-talos-1` (Home 1) as a central agentic workload.
- **Storage**: Persistent local volume via `local-path` storage class (10Gi) mounted to `/opt/data` to store configurations, session history, memory databases, and learned skills.
- **Security Context**: Runs with `fsGroup: 1000` (`HERMES_UID: 1000`, `HERMES_GID: 1000`) for non-root volume access.
- **Web Dashboard**: Runs the supervised web interface on port 9119 (`HERMES_DASHBOARD=1`).
- **Gateway & API Server**: OpenAI-compatible API server on port 8642 (`API_SERVER_ENABLED=true`).
- **Secrets & Model Provider**: Integrated with Azure Key Vault via External Secrets Operator (`ClusterSecretStore: azure-keyvault`) for secretless GitOps with Azure AI Foundry.
- **Ingress & TLS**: Gateway API `HTTPRoute` attached to `traefik-gateway` in the `traefik` namespace, serving HTTPS on `https://hermes.${CLUSTER_DOMAIN:=talos-1}.gwebs.ca` using cluster wildcard TLS certificates.
- **Health Probes**: Integrated startup, liveness, and readiness probes checking the `/health` endpoint on the gateway port 8642.

---

## Directory Structure

```text
├── namespace.yaml        # 'hermes' namespace
├── external-secret.yaml  # Syncs Azure Foundry URL & API key from Azure Key Vault
├── pvc.yaml              # 10Gi local-path PersistentVolumeClaim
├── deployment.yaml       # Application Deployment with auto-config init and environment settings
├── service.yaml          # Service exposing dashboard (9119) and gateway API (8642)
├── httproute.yaml        # Traefik Gateway API HTTPRoute for dashboard access
├── kustomization.yaml    # Kustomize manifest list
└── README.md             # Documentation
```

---

## Azure Foundry Configuration

Hermes is configured to pull credentials dynamically from Azure Key Vault (`gjtaloskv`) via `external-secret.yaml`:

| Azure Key Vault Secret Name | In-Cluster Secret Key | Description |
| :--- | :--- | :--- |
| **`hermes-azure-foundry-api-key`** | `AZURE_OPENAI_API_KEY` | API key from Azure AI Foundry / Azure OpenAI Keys and Endpoints. |
| **`hermes-azure-foundry-url`** | `AZURE_OPENAI_ENDPOINT` | Target endpoint (e.g. `https://<resource>.openai.azure.com/openai/v1`). |

On container startup, Hermes automatically sets:
- `model.provider: azure-foundry`
- `model.base_url: $AZURE_OPENAI_ENDPOINT`
- `model.default: ${HERMES_MODEL:-gpt-5.6-terra}`
- Registered aliases (switchable via `/model <alias>`):
  - `terra` -> `gpt-5.6-terra`
  - `sol` -> `gpt-5.6-sol`
  - `luna` -> `gpt-5.6-luna`

---

## Access & Operations

### Web Dashboard
- **URL**: `https://hermes.talos-1.gwebs.ca`
- **Initial Username**: `admin`
- **Initial Password**: `admin`

Credentials can be updated or overridden in `deployment.yaml` via `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`.

### In-Cluster API Server
Other workloads or chat interfaces (e.g. Open WebUI, LibreChat) can communicate directly with the Hermes agent via the Kubernetes ClusterIP service:
- **Base URL**: `http://hermes.hermes.svc.cluster.local:8642/v1`
- **Model**: `hermes-agent`

# Discord Bots (JokeBot & MusicBot)

Consolidated deployment running both **JokeBot** and **MusicBot** as companion containers in a single Kubernetes pod, migrating and replacing the legacy single-container `joke-de-jean` Docker Compose stack.

---

## Architecture

- **Workload Type**: Multi-container Kubernetes `Deployment` with `Recreate` strategy (prevents duplicate Discord gateway connections and mounts single RWO volume safely).
- **Containers**:
  - `jokebot`: `ghcr.io/gabrieljean/jokebot:1.0.0` (Humor, roasting, compliments, TTS, Reddit jokes).
  - `musicbot`: `ghcr.io/gabrieljean/musicbot:1.0.0` (Discord music playback).
- **Secrets Management**: Integrated via `ExternalSecret` referencing the `azure-keyvault` ClusterSecretStore (`gjtaloskv`).
  - `jokebot-discord-token` -> `JOKEBOT_DISCORD_TOKEN`
  - `xai-api-key` -> `XAI_API_KEY`
  - `musicbot-discord-token` -> `MUSICBOT_DISCORD_TOKEN`
- **Storage**: Single 2Gi PersistentVolumeClaim (`discordbots-data`) using `local-path`. Each container is partitioned into its own isolated folder on the volume via `subPath`:
  ```
  discordbots-data (PVC root)
  ├── jokebot/      -> mounted to /app/data inside jokebot container
  │   ├── bot_jokebot.log
  │   └── command_history.json
  └── musicbot/     -> mounted to /app/data inside musicbot container
      ├── bot_musicbot.log
      └── command_history.json
  ```

---

## Directory Structure

```
├── namespace.yaml        # 'discordbots' namespace
├── external-secret.yaml  # Syncs Discord tokens & xAI API key from Azure Key Vault
├── pvc.yaml              # Shared local-path volume for bot history and logs
├── deployment.yaml       # Multi-container Deployment (jokebot + musicbot)
├── kustomization.yaml    # Kustomize manifest definitions
└── README.md             # Documentation
```

# 🏠 HomeServer

Personal homelab platform for Proxmox-hosted VMs, host configuration, and services running across Docker and Kubernetes with unified ingress and TLS.

---

## 🚀 Quickstart

1. **Install tooling** – Ansible ≥ 2.14, Docker CLI, kubectl, and Azure CLI.
2. **Configure secrets** – Store host/app secrets inside the `.env` files that live next to every compose project. Ansible inventory is encrypted via Vault ([`Ansible/inventories/home/inventory.ini`](Ansible/inventories/home/inventory.ini)).
3. **Configure hosts + apps** – `cd Ansible && ansible-playbook playbooks/pve-1-docker-apps.yml --vault-id @prompt` (repeat for `playbooks/pve-2-docker-apps.yml`, `playbooks/pve-plex.yml`, etc.). Plays install Docker when missing, copy the `Docker/<app>` folder, and run `docker compose up -d` with optional `restart`/`pull_latest` flags.
4. **Kubernetes + ingress** – Manifests for Traefik and MetalLB live in `K8s/ingress/*`. Apply them with the kubeconfigs under `K8s/kubeconfigs/`.

> 🔁 Day-two operations: rerun the relevant Ansible playbook whenever compose projects change. Tasks copy only when files differ and restart stacks asynchronously to minimize downtime.

---

## 🧭 Architecture Overview

- 🖥️ Platform: Proxmox (pve-1, pve-2) hosting VMs for Docker workloads, DNS, Plex, NAS, and a Kubernetes cluster (RKE2).
- 🧱 Platform layout: Proxmox hosts the VMs, networking, storage, GPU/USB passthrough, and startup order used by the environment.
- 🔧 Configuration: Ansible installs Docker and deploys per-host app stacks; baseline metrics via cAdvisor on all app nodes.
- 🌐 Networking & Ingress: Traefik v3 reverse proxy terminates TLS and routes to services. Let’s Encrypt DNS-01 via Azure DNS; domains under docker-1.example.com and docker-2.example.com.
- 💾 Storage: App data on host under `/Apps/*`; media via CIFS mounts from NAS to containers (e.g., `//nas/Medias`). Plex uses host networking and NVIDIA GPU.
- 📊 Observability: Prometheus + Grafana; exporters via cAdvisor and Traefik metrics. Healthchecks for external monitoring.
- 🚀 CI/CD: GitHub workflows for deployment automation and updates.
- 🔐 Secrets: Environment-driven (`.env`) for cloud DNS, CIFS credentials, VPN, and OAuth/OpenAI integrations.

---

## 📂 Repository Layout

| Path | Purpose | Highlights |
|------|---------|------------|
| `Ansible/` | Playbooks mapping VMs to compose stacks with shared roles for reachability checks and Docker compose rollouts. | `playbooks/*`, `roles/docker_apps/*`, `ansible.cfg` |
| `Docker/<service>/` | Self-contained compose bundles with `.env`, configs, and helper scripts per application. | Traefik, AdGuard Home, Plex, Home Assistant, monitoring, Portainer, Open WebUI, etc. |
| `K8s/` | RKE2 ingress manifests, MetalLB pools, and kubeconfig helpers. | `ingress/traefik`, `ingress/metallb`, `kubeconfigs/` |
| `Scripts/` | Utility scripts for day-to-day ops (SMART checks, UPS control, and helper binaries). | `smart.sh`, `ups.sh`, `tf` |
| `etc/` & `crontab/` | Host-level configs (Samba, smartd, sanoid) and scheduled job definitions commit-tracked for reproducibility. | `etc/samba/smb.conf`, `etc/sanoid/sanoid.conf` |

---

## 🔁 Deployment Flow

1. **Host bootstrap (Ansible)** – Inventory groups match VM names. Plays compute the `docker_apps_by_host` map, ensure Docker is present (via `roles/docker_apps/tasks/install_docker.yml`), copy the matching compose directory, and start `docker compose up` asynchronously (`roles/docker_apps/tasks/deploy_app.yml`). cAdvisor is auto-added to every host list for baseline metrics.
2. **Services (Docker)** – Every application folder contains its `docker-compose.yml`, `.env`, and any extra configs (e.g., `Docker/dns-update/update_dns.sh`, `Docker/homeassistant/README-zigbee-usb.md`). Because the folder is copied wholesale, treat it as the source of truth.
3. **Kubernetes ingress** – `K8s/ingress/traefik` houses the cluster-facing Traefik deployment plus values for the LANs, while `K8s/ingress/metallb` defines the L2 pools feeding RKE services. Choose Kubernetes Traefik vs Docker Traefik depending on workload placement.

---

## 📦 Docker App Catalog

The `Docker/` tree mirrors production services. Highlights:

- **Edge & networking** – `traefik/`, `dns-update/`, `adguardhome/`, `upsnap/`.
- **Observability** – `monitoring/` (Prometheus/Grafana stack), `cadvisor/`, `healthchecks/`.
- **Media & automation** – `plex/`, `plexapps/`, `homeassistant/`, `satisfactory/`.
- **Dashboards & tools** – `homepage-1/`, `homepage-2/`, `code-server/`, `open-webui/`, `gitea/`, `pdf/`, `portainer/`.
- **Misc utilities** – `joke-de-jean/`, `teamspeak/`, `scrutiny/`, etc.

Add a new service by creating `Docker/<service>` with its compose stack, referencing it inside the right Ansible playbook, and rerunning the play.

---

## 🔐 Secrets & Access

- **Ansible Vault** – Hostnames, IPs, and credentials in `inventories/home/inventory.ini` remain encrypted. Use `ansible-vault view inventories/home/inventory.ini` or `--vault-id` when running playbooks.
- **Compose secrets** – `.env` files sit beside each `docker-compose.yml` and are copied during playbook runs. Keep them outside version control and rotate as needed.

---

## 🧪 Operations Cheatsheet

Update Docker stacks on pve-1:

```sh
cd Ansible
ansible-playbook playbooks/pve-1-docker-apps.yml --vault-id @prompt
```

Rememberable shortcuts (Makefile):

```sh
cd Ansible
make pve-ubuntu-base
make pve-1-docker-apps
make updates
```

Tip: swap vault mode if you prefer:

```sh
cd Ansible
make pve-ubuntu-base VAULT='--vault-id @prompt'
```

CI note: GitHub Actions SSH keys

- `CI_PRIVATE_KEY` must be an *unencrypted* private key (no passphrase) and must include the full `BEGIN ... PRIVATE KEY` / `END ... PRIVATE KEY` block.
- If you store it in GitHub Secrets as a single line, use literal `\n` sequences; the workflow will expand them into real newlines.

Kubernetes ingress refresh:

```sh
kubectl apply -k K8s/ingress/traefik
kubectl apply -k K8s/ingress/metallb
```

Use the `restart` / `pull_latest` toggles inside each playbook entry for targeted restarts without touching other services.

---

## 🧩 Components

### 🧰 Proxmox VMs

| Node  | Role/VMs                                                                 |
|------:|---------------------------------------------------------------------------|
| pve-1 | Docker-1, DNS-1, Plex-1 (GPU), NAS-1 (ZFS/raw disks), Satisfactory, k8s-master-1, k8s-worker-1 |
| pve-2 | Docker-2 (USB passthrough), DNS-2, k8s-worker-2                           |

### 🐳 Docker App Stacks (Ansible → Docker/*)

| Category       | Services                                                                                          |
|----------------|---------------------------------------------------------------------------------------------------|
| Reverse Proxy  | Traefik v3 (Azure DNS ACME), dashboard via traefik.docker-1.example.com / traefik.docker-2.example.com |
| Management     | Portainer                                                                                         |
| Dashboards     | Homepage (two instances, one per site)                                                            |
| Monitoring     | Prometheus, Grafana, cAdvisor                                                                     |
| Media          | Plex (host net + GPU), Overseerr, Sonarr, Radarr, Jackett, Transmission/qBittorrent               |
| Automation/IoT | Home Assistant (host net, privileged, Zigbee USB passthrough on pve-2)                            |
| Network        | AdGuard Home (DNS-1/DNS-2), Upsnap                                                                 |
| Dev/Tools      | Gitea, code-server, Stirling-PDF, Healthchecks, Open WebUI (OAuth + Azure OpenAI)                 |

### ☸️ Kubernetes (RKE2)

- Master on pve-1; workers across pve-1/pve-2.
- Ingress: Traefik manifests under `K8s/ingress/traefik`.
- L2 Load Balancing: MetalLB configuration under `K8s/ingress/metallb`.
- Workloads can be fronted either by Kubernetes Traefik or the Docker Traefik, depending on routing strategy.

---

## 🛠️ Tools & Technologies

| Layer          | Tools                                                                                       |
|----------------|----------------------------------------------------------------------------------------------|
| Infra          | Proxmox                                                                                    |
| Config Mgmt    | Ansible (host bootstrap, per-host app maps, conditional restart/pull)                       |
| Containers     | Docker Compose (per-app in Docker/*)                                                        |
| Ingress & TLS  | Traefik v3 (Let’s Encrypt via Azure DNS; HTTP→HTTPS redirects)                              |
| Observability  | Prometheus, Grafana, cAdvisor                                                               |
| CI/CD          | GitHub Actions (deployment workflows, updates)                                              |

---

## 🌍 Domains & Routing

- Core zones: docker-1.example.com, docker-2.example.com (and app subdomains).
- TLS: Certificates via ACME DNS-01 (Azure DNS), persisted under `/Apps/Traefik/letsencrypt`.

---

## 🔁 High-level Data Flows

```text
Client ──TLS──► Traefik ──► Docker services (or K8s ingress) ──► App containers

Media apps ──CIFS──► NAS-1 share (//nas/Medias)

Exporters (cAdvisor/Traefik) ──► Prometheus ──► Grafana
```


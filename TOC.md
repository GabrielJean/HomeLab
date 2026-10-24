# Table of Contents

A master directory and index of all documentation files in this repository.

---

## ☸️ Kubernetes Infrastructure & Bootstrapping (`K8s/`)

### Core Architecture & Bootstrap Guides
- **[`K8s/Bootstrap.md`](K8s/Bootstrap.md)** — **End-to-End Kubernetes Clusters Bootstrap Guide**
  - Full 8-step walkthrough: Omni SaaS machine setup, Proxmox VM, Talos Linux installation, kubeconfig fetch, Azure Workload Identity Federation (Path 2), Azure Key Vault secrets, ESO CRD installation, Flux GitOps bootstrap, verification, and runbooks.
- **[`K8s/PLAN.md`](K8s/PLAN.md)** — **Kubernetes Migration Plan & Architecture**
  - Architectural blueprint and phased migration roadmap from legacy Docker Compose to Talos Linux.
- **[`K8s/Omni/README.md`](K8s/Omni/README.md)** — **Sidero Omni Operations & Media Presets**
  - Omni SaaS cluster templates, machine classes, declarative media presets, extension management, and etcd backups.
- **[`K8s/clusters/README.md`](K8s/clusters/README.md)** — **Multi-Cluster GitOps Architecture**
  - Independent Flux pull-sync topology, cluster overlays (`k8s-talos-1`, `k8s-talos-2`), and secretless variable substitution via `postBuild.substituteFrom`.

### Platform Infrastructure Components (`K8s/infrastructure/`)
- **[`K8s/infrastructure/external-secrets/README.md`](K8s/infrastructure/external-secrets/README.md)** — **External Secrets Operator (Azure Key Vault)**
  - Secretless Microsoft Entra Workload Identity Federation (Path 2), trust chain diagram, Azure Key Vault secret registry, Flux dynamic injection, and expiration runbook (Oct 23, 2028).
- **[`K8s/infrastructure/headlamp/README.md`](K8s/infrastructure/headlamp/README.md)** — **Headlamp Kubernetes Dashboard**
  - Web UI deployment, Flux GitOps plugin initContainer, Microsoft Entra ID (Azure AD) OIDC SSO, Gateway API `HTTPRoute`, and emergency breakglass token recovery.
- **[`K8s/infrastructure/traefik/README.md`](K8s/infrastructure/traefik/README.md)** — **Traefik Ingress & Gateway API Controller**
  - Traefik v3 chart deployment, Gateway API implementation, HostPort 80/443 entrypoints, cross-namespace routing, and automatic HTTPS redirection.
- **[`K8s/infrastructure/gateway-api/README.md`](K8s/infrastructure/gateway-api/README.md)** — **Kubernetes Gateway API Standard**
  - Official Gateway API standard CRDs (v1.2.0) and listener specifications.
- **[`K8s/infrastructure/metrics-server/README.md`](K8s/infrastructure/metrics-server/README.md)** — **Kubernetes Metrics Server**
  - In-cluster metrics aggregator for pod/node resource utilization and `kubectl top`.
- **[`K8s/infrastructure/storage/local-path/README.md`](K8s/infrastructure/storage/local-path/README.md)** — **Local Path Provisioner**
  - Rancher local-path host storage provisioner under `/var/local-path-provisioner`.

---

## 🐳 Docker Stacks & Host Workloads (`Docker/`)

- **[`Docker/homeassistant/README-zigbee-usb.md`](Docker/homeassistant/README-zigbee-usb.md)** — **Home Assistant Zigbee Coordinator Mapping**
  - Hardware passthrough, serial device rules, and container device mapping for Zigbee USB coordinators.
- **[`Docker/plex/scripts/README.md`](Docker/plex/scripts/README.md)** — **Plex Maintenance & Operations Scripts**
  - Automation scripts for database maintenance, cache clearing, and metadata synchronization.

---

## 🏛️ Archives & Retired Configurations (`Archives/`)

- **[`Archives/Terraform/modules/proxmox_vm/README.md`](Archives/Terraform/modules/proxmox_vm/README.md)** — **Terraform Proxmox VM Module**
  - Retired Infrastructure-as-Code Terraform module for provisioning Proxmox virtual machines.

---

## 📖 Global Repository Guide

- **[`README.md`](README.md)** — **HomeLab Overview & Monorepo Tour**
  - High-level environment philosophy, architecture diagram, technology stack, directory tour, CI/CD design, and safety guidelines.


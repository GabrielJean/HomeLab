# Kubernetes Migration Plan

## Table Of Contents

- [Purpose](#purpose)
- [Current Environment Summary](#current-environment-summary)
- [Proposed Target Architecture](#proposed-target-architecture)
- [Networking And Ingress](#networking-and-ingress)
- [Authentication And Authorization](#authentication-and-authorization)
- [Secrets Management](#secrets-management)
- [Storage And Backup](#storage-and-backup)
- [GitOps Repository Layout](#gitops-repository-layout)
- [Migration Sequence](#migration-sequence)
- [Workloads Remaining Outside Kubernetes Initially](#workloads-remaining-outside-kubernetes-initially)
- [Validation And Exit Criteria](#validation-and-exit-criteria)
- [Decisions To Confirm Before Implementation](#decisions-to-confirm-before-implementation)

## Purpose

Migrate suitable homelab Docker Compose workloads to Kubernetes while keeping the platform simple, reproducible, and recoverable. The initial design prioritizes a single-admin, non-HA environment with a clear path to future growth.

This plan replaces Docker Compose application deployment through Ansible with Flux-managed GitOps. Ansible remains responsible for infrastructure that Kubernetes should not manage, including Proxmox provisioning, NAS configuration, Tailscale routing, and host maintenance.

## Current Environment Summary

- Proxmox hosts: `pve-1` and `pve-2`.
- Docker workloads are deployed by Ansible to dedicated service VMs including Docker, DNS, Plex, gaming, and NAS hosts.
- Most application state currently uses host-local `/Apps/...` bind mounts.
- Media is available from a NAS SMB share at `//192.168.10.12/Medias`.
- Traefik currently exposes HTTP(S) services and obtains certificates through Let's Encrypt DNS-01 validation against Azure DNS.
- Microsoft Entra ID and Azure resources are already part of the environment.
- Tailscale provides private connectivity and routing between LAN segments.

## Proposed Target Architecture

### Cluster Shape

Start with one simple Kubernetes cluster across the two Proxmox hosts:

| Node | Location | Role | Initial scheduling |
| --- | --- | --- | --- |
| `k8s-cp-1` | `pve-1` | Talos control plane and etcd | Schedulable for workloads |
| `k8s-worker-1` | `pve-2` | Talos worker | Schedulable for workloads |

The initial Kubernetes API is not highly available. If `k8s-cp-1` or `pve-1` fails, the API, Flux reconciliation, and new scheduling stop until the control plane is restored. Existing workloads on `pve-2` may continue to run.

Daily Proxmox Backup Server VM backups provide the baseline VM recovery path. Add frequent encrypted etcd snapshots stored outside `k8s-cp-1` so Kubernetes state has a lower RPO than the daily VM backup. Application data still requires its own backup and restore procedures.

### Future API HA Option

True API HA is deferred, not ruled out. It requires three Talos control-plane/etcd members across three independent physical failure domains; placing additional control-plane VMs only on `pve-1` and `pve-2` cannot survive failure of either host.

If a third physical node becomes available, use one control-plane node on each Proxmox host and a third, control-plane-only member on the independent hardware. It should have separate power and networking where possible.

The preferred API endpoint for that future topology is `kube-vip` in BGP mode behind a stable DNS name such as `api.k8s.gwebs.ca`. BGP is needed because L2/ARP failover cannot span the routed sites. An equivalently redundant L4 endpoint is required if BGP is unavailable.

Until that topology exists, prioritize short and tested API recovery rather than adding partial or asymmetric etcd quorum designs.

### Availability Strategy: Recoverable Stateful Services

The homelab is predominantly stateful. App configuration, SQLite databases, Git repositories, metrics, Plex metadata, Home Assistant data, download state, game saves, and device integrations are all persistent state. Generic replica counts do not make these applications highly available and can corrupt state when two active replicas write to incompatible local or shared storage.

The initial availability target is **fast, tested recovery**, not active-active application deployment:

| Layer | Initial design |
| --- | --- |
| Cluster control plane | One Talos control-plane node with frequent encrypted etcd snapshots, daily PBS VM backups, and documented restoration |
| Application replicas | One active replica for most workloads |
| Application placement | Explicit node affinity for local PVCs, GPUs, USB devices, and other hardware-bound workloads |
| Configuration recovery | Flux rebuilds manifests, routing, policies, and non-secret configuration from Git |
| Secret recovery | Azure Key Vault is the runtime authority; SOPS protects bootstrap secrets |
| Data recovery | Application-aware backup plus volume backup to NAS and encrypted offsite storage |
| Host failure response | Restore or reschedule onto the other Proxmox host after restoring required local state |

Target redundancy where it provides the largest practical benefit. DNS should remain independently available on both sites; two AdGuard instances or equivalent resolvers provide more useful resilience than attempting active-active replicas for SQLite-backed application stacks.

Do not introduce Ceph, Longhorn replica volumes, multi-site synchronous storage, or active-active database designs merely to claim HA. With only two Proxmox failure domains, they add quorum, split-brain, latency, fencing, and recovery complexity without providing a complete failure-domain solution.

Control-plane API availability does not make the application data plane highly available. Stateful workloads still follow the recovery-oriented design described in this plan.

### Kubernetes Distribution

**Decision: Talos Linux**

Talos is the recommended distribution because it is immutable, API-managed, minimal, and purpose-built for Kubernetes. It avoids maintaining general-purpose Ubuntu servers solely to host Kubernetes, while retaining a documented upgrade and recovery model.

Alternatives considered:

| Option | Assessment |
| --- | --- |
| Talos Linux | Recommended. Strong declarative and security model for dedicated Proxmox Kubernetes VMs. |
| RKE2 | Mature and appropriate if Rancher becomes mandatory, but heavier than necessary for the initial cluster. |
| K3s | A reasonable lightweight baseline, but less opinionated about immutable node management than Talos. |
| KubeSolo | Not recommended. It is designed for permanently isolated, resource-constrained, single-node devices; it does not fit a two-host cluster with future growth goals. |

### GitOps

**Decision: Flux CD**

Flux continuously reconciles Git into the cluster. Git becomes the desired state for application and platform configuration; administrators do not make routine changes through a dashboard.

GitHub Actions changes responsibility from remote deployment to validation:

- Render Helm and Kustomize resources.
- Validate Kubernetes schemas with `kubeconform` or an equivalent tool.
- Validate policies and manifests.
- Optionally verify referenced container images.
- Merge to `main`; Flux performs reconciliation.

Argo CD remains a valid alternative if a rich GitOps user interface becomes important. Flux is preferred because it has a smaller operational footprint and matches the single-admin, Git-first workflow.

### Management And Observability

- Use **Headlamp** as the Kubernetes dashboard.
- Use **Grafana** for metrics and dashboards.
- Use `kubectl` and K9s for direct administration and troubleshooting.
- Do not use Rancher initially; it adds a fleet-management layer that is not currently needed.
- Do not use Portainer as a deployment mechanism; Docker socket-based operational patterns do not transfer cleanly to Kubernetes, and GitOps must remain authoritative.

## Networking And Ingress

### Core Networking

Use Cilium as the CNI and enable the following capabilities:

- Kubernetes networking and network policies.
- L2 announcements for LAN `LoadBalancer` service addresses.
- Gateway API implementation for HTTP(S) traffic.

This avoids the deprecated community NGINX Ingress Controller and eliminates the need to operate a separate MetalLB installation for the initial design.

### Ingress And Certificates

Use the following components:

| Responsibility | Component |
| --- | --- |
| External HTTP(S) entry point | Cilium Gateway API |
| HTTP routing | `Gateway` and `HTTPRoute` resources |
| TLS certificate issuance and renewal | cert-manager |
| ACME DNS-01 challenge | Azure DNS solver for cert-manager |
| DNS record automation | external-dns, introduced after ingress is stable |

This preserves the existing Azure DNS certificate workflow while moving certificate state from Traefik's host-local ACME file into Kubernetes `Secret` resources managed by cert-manager.

Keep Docker endpoints online during migration. Introduce Kubernetes-specific DNS names or repoint one existing service name only after its Kubernetes replacement has been verified.

## Authentication And Authorization

### Kubernetes API Access

Use Microsoft Entra ID OIDC authentication for Kubernetes API users:

- Configure Kubernetes API server OIDC options through Talos machine configuration.
- Create an Entra security group for administrators, such as `homelab-k8s-admins`.
- Bind that group to `cluster-admin` for the first phase.
- Use `kubelogin` from local kubeconfig files for device-code or browser login.

Talos node administration is separate from Kubernetes API authentication. Protect and retain Talos administrative client credentials offline for disaster recovery.

### Dashboard Access

Protect Headlamp with Entra OIDC, using either Headlamp's OIDC support or an `oauth2-proxy` front end. The dashboard is for visibility and controlled operations, not primary deployment.

## Secrets Management

### Initial Model

Use a hybrid secrets model:

| Secret category | Source and mechanism |
| --- | --- |
| Runtime application secrets | Azure Key Vault synchronized by External Secrets Operator |
| Azure Key Vault bootstrap credential | SOPS-encrypted Kubernetes secret in Git |
| Flux and infrastructure bootstrap secrets | SOPS-encrypted Kubernetes secrets in Git where necessary |
| Recovery material | Stored outside Git and outside the cluster |

Azure Key Vault is the source of truth for application secrets. External Secrets Operator creates Kubernetes `Secret` objects for workloads from the Key Vault values.

The first iteration may use a narrowly scoped Azure application credential because a self-managed Kubernetes cluster needs additional public OIDC issuer/JWKS hosting to use Azure workload identity federation. Introduce workload identity federation later after the cluster's OIDC discovery design is complete.

## Storage And Backup

### Storage Classes

Use three storage categories:

| Storage type | Intended use | Initial implementation |
| --- | --- | --- |
| Node-local persistent storage | App configs, databases, Grafana, Gitea, and low-to-medium critical state | Local-path provisioner or OpenEBS LocalPV |
| Shared NAS storage | Media and other multi-reader content | Kubernetes SMB CSI driver backed by the existing NAS |
| Offsite backup storage | Encrypted recovery copies | Azure Blob Storage or another object-storage target |

Do not use Azure Files as the primary application storage solution. The current NAS is closer to the workloads, already contains media, and avoids adding cloud latency and operating cost for primary state.

This is a recovery-oriented storage design. Local Persistent Volumes are single-node by design; the recovery procedure restores them to a selected node rather than assuming Kubernetes can move their data automatically.

### Data Rules

- Local Persistent Volumes are tied to the node that hosts their data. Define node affinity explicitly for each stateful workload.
- Use the SMB CSI driver for the existing `Medias` share rather than copying media into Kubernetes volumes.
- Do not use `hostPath` as a general application storage abstraction.
- Preserve application-native backup procedures for databases and configuration where available.
- Use scheduled Talos/etcd snapshots, volume backups with Velero/Kopia or an equivalent tool, and a tested restore procedure.
- Proxmox snapshots are useful infrastructure recovery support but are not the only data backup method.
- Prefer application-aware backups for databases, Gitea repositories, Plex metadata, Home Assistant, Arr services, torrent state, and game saves.
- Treat the NAS as a dependency with its own backup and recovery plan; SMB CSI provides shared access, not NAS high availability.
- Encrypt and copy backup data to an independent target such as Azure Blob Storage.

## GitOps Repository Layout

Use this `K8s/` directory as the GitOps root:

```text
K8s/
  clusters/
    homelab/
      flux-system/
      infrastructure.yaml
      apps.yaml
  infrastructure/
    cilium/
    cert-manager/
    external-secrets/
    gateway/
    monitoring/
    storage/
  apps/
    homepage/
    stirling-pdf/
    open-webui/
    gitea/
    grafana/
  platform/
    namespaces/
    rbac/
    policies/
    secrets/
  talos/
    patches/
    controlplane.yaml
    worker.yaml
```

The exact file structure may evolve, but the ownership boundary should remain clear:

- `talos/` describes machine configuration.
- `infrastructure/` describes cluster-wide operators and services.
- `platform/` describes shared policy, namespaces, RBAC, and secret definitions.
- `apps/` describes individual applications.
- `clusters/homelab/` composes the desired state for this cluster.

## Migration Sequence

### Phase 0: Discovery And Prerequisites

1. Size the Kubernetes VMs for expected workload memory, CPU, disk, and GPU requirements.
2. Select Pod and Service CIDRs that do not overlap existing LAN networks or Tailscale-routed subnets.
3. Reserve LAN IP addresses for Kubernetes nodes and Gateway/LoadBalancer services.
4. Configure frequent encrypted etcd snapshots to a target outside the control-plane VM and retain daily PBS VM backups.
5. Define per-application recovery point objective (RPO), recovery time objective (RTO), backup target, retention, and restore validation before migration.
6. Inventory every Docker `.env`, `/Apps` directory, database, SMB mount, device mapping, exposed port, and current DNS name.
7. Classify each workload as single-active, hardware-bound, NAS-backed, or requiring application-native backup.

### Phase 1: Cluster Foundation

1. Create the Talos control-plane VM on `pve-1` and worker VM on `pve-2`.
2. Bootstrap the cluster, configure encrypted etcd snapshots, and retain encrypted recovery copies of Talos and Kubernetes credentials.
3. Test control-plane recovery from an etcd snapshot and from a PBS VM restore in an isolated or planned recovery scenario.
4. Install Cilium and configure L2 LoadBalancer address pools and Gateway API.
5. Bootstrap Flux from this repository.
6. Deploy cert-manager, Azure DNS credentials, and a test certificate.
7. Deploy External Secrets Operator and connect it to Azure Key Vault.
8. Deploy local persistent storage and SMB CSI storage.
9. Configure Entra OIDC authentication, Kubernetes RBAC, and Headlamp access.
10. Deploy metrics, logs, alerts, and backups.

### Phase 2: Lower-Risk Application Migration

Migrate lower-coupling HTTP workloads first. These are still stateful where they retain configuration or user data, so each receives a PVC and backup/restore design before cutover:

- Stirling-PDF.
- FinGlass.
- StockBot.
- Joke de Jean.
- Termix.
- Open WebUI.
- Homepage.

For each application:

1. Convert image, environment, volumes, ports, and health checks to Kubernetes resources or a maintained Helm chart.
2. Use `Deployment`, `Service`, `HTTPRoute`, `ConfigMap`, `ExternalSecret`, and `PersistentVolumeClaim` resources as appropriate.
3. Verify certificate issuance, routing, restart behavior, persistent data, and rollback before DNS cutover.
4. Test a backup and restore of the application's persistent state.
5. Retain the Docker Compose instance until the Kubernetes replacement passes validation.

### Phase 3: Stateful Application Migration

Migrate Prometheus/Grafana, then Gitea, only after storage backups and restores have been tested.

- Define retained data duration and storage size for Prometheus.
- Export and test Grafana dashboard and database recovery.
- Create and test Gitea backup/restore procedures before cutover.

### Phase 4: Media Companion Workloads

Migrate the standard media companion applications:

- Overseerr.
- Radarr.
- Sonarr.
- Jackett.
- FlareSolverr.

Mount the NAS media share through SMB CSI and validate file ownership, permissions, imports, and rename behavior before moving active download workflows.

### Phase 5: Specialized Workloads

Evaluate these only after the platform is proven:

| Workload | Migration concerns |
| --- | --- |
| Plex | NVIDIA GPU access, media SMB mount, host-network behavior, and node-local config |
| Gluetun plus Transmission/qBittorrent | TUN device, `NET_ADMIN`, shared network namespace, VPN kill-switch behavior, and exposed ports |
| Home Assistant | Host networking, privileged mode, direct Zigbee USB access, and node pinning |
| Game servers | UDP ports, fixed external ports, high memory allocation, save data, and node-local recovery |

## Workloads Remaining Outside Kubernetes Initially

Keep these on dedicated Docker or VM hosts until their requirements are deliberately designed and tested:

- AdGuard Home, because it owns host DNS/DHCP and related privileged network ports.
- Home Assistant, because it needs host networking, privileged access, and Zigbee USB passthrough.
- Plex, until NVIDIA GPU support, storage, and network behavior are validated.
- Gluetun plus qBittorrent/Transmission, until privileged VPN networking is proven.
- Satisfactory and Project Zomboid, until UDP exposure, resource isolation, and save recovery are proven.

Docker-specific components are replaced rather than migrated:

- Docker-provider Traefik becomes Gateway API plus cert-manager.
- Docker cAdvisor collection becomes Kubernetes-native metrics collection.
- Docker-socket Portainer becomes Headlamp, Grafana, and Kubernetes CLI tooling.

## Validation And Exit Criteria

The platform foundation is complete when all of the following are true:

- Flux reconciles a Git commit into the cluster without manual deployment steps.
- An etcd snapshot restore and a PBS-backed control-plane VM recovery procedure are documented and tested.
- An Entra-authenticated administrator can access the Kubernetes API and Headlamp.
- A Gateway API route has a valid Azure DNS-issued TLS certificate.
- External Secrets Operator retrieves an Azure Key Vault secret successfully.
- Local and SMB-backed PersistentVolumeClaims both work and have documented restore procedures.
- A backup and restore drill succeeds for at least one application from every storage/recovery class in use.
- Metrics, logs, alerts, and cluster health dashboards are available.

Each migrated application is complete only when its Kubernetes deployment has passed routing, persistence, restart, backup, monitoring, and rollback checks before the Docker Compose source is retired.

## Decisions To Confirm Before Implementation

- Confirm the first cluster is one two-node cluster, not two independent single-node clusters.
- Confirm Talos Linux as the Kubernetes distribution.
- Confirm Flux CD as the GitOps reconciler.
- Confirm Azure Key Vault plus External Secrets Operator with SOPS bootstrap secrets.
- Confirm Cilium Gateway API, cert-manager, and Azure DNS as the ingress/certificate stack.
- Confirm the local storage implementation: local-path provisioner or OpenEBS LocalPV.
- Confirm the backup target and retention policy.
- Confirm per-application RPO/RTO targets and the first workloads to receive restore testing.
- Defer or select the future API HA topology: third physical failure domain plus BGP-backed `kube-vip` or an equivalent redundant L4 endpoint.
- Confirm the initial DNS naming and cutover approach for Kubernetes services.

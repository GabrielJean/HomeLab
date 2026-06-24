# Docker to Kubernetes app migration plan

## Scope

This plan focuses on converting the applications currently defined under [`Docker/`](Docker) into Kubernetes-ready workloads. It does **not** design the cluster itself. The emphasis is on what each app will need when moved from Compose into Kubernetes, including stateful apps, host-integrated services, media workloads, and game servers.

## What was analyzed

Source definitions reviewed include the Compose files under [`Docker/`](Docker), plus supporting files such as [`Docker/update.sh`](Docker/update.sh), [`Docker/homeassistant/README-zigbee-usb.md`](Docker/homeassistant/README-zigbee-usb.md), [`Docker/monitoring/prometheus.yml`](Docker/monitoring/prometheus.yml), [`Docker/dns-update/Dockerfile`](Docker/dns-update/Dockerfile), [`Docker/dns-update/update_dns.sh`](Docker/dns-update/update_dns.sh), [`Docker/n8n/Dockerfile`](Docker/n8n/Dockerfile), and [`Docker/n8n/task-runners.json`](Docker/n8n/task-runners.json).

## App classification

### Good early migration candidates

- [`Docker/FinGlass/docker-compose.yml`](Docker/FinGlass/docker-compose.yml): app with persistent app data and HTTP ingress
- [`Docker/gmap/docker-compose.yml`](Docker/gmap/docker-compose.yml): app with persistent run data and HTTP ingress
- [`Docker/joke-de-jean/docker-compose.yml`](Docker/joke-de-jean/docker-compose.yml): simple worker app with persistent data
- [`Docker/open-webui/docker-compose.yml`](Docker/open-webui/docker-compose.yml): web app with secrets and persistent data
- [`Docker/pdf/docker-compose.yml`](Docker/pdf/docker-compose.yml): web app with healthcheck and mostly stateless behavior
- [`Docker/termix/docker-compose.yml`](Docker/termix/docker-compose.yml): HTTP app with persistent data
- [`Docker/monitoring/docker-compose.yml`](Docker/monitoring/docker-compose.yml): Prometheus and Grafana, stateful but straightforward
- [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml): multi-workload app with storage and internal service dependency

### Stateful but moderate complexity

- [`Docker/gitea/docker-compose.yml`](Docker/gitea/docker-compose.yml): data directory plus SSH and HTTP exposure
- [`Docker/homepage-1/docker-compose.yml`](Docker/homepage-1/docker-compose.yml): config files plus optional Docker socket integration
- [`Docker/homepage-2/docker-compose.yml`](Docker/homepage-2/docker-compose.yml): same as homepage-1
- [`Docker/portainer/docker-compose.yml`](Docker/portainer/docker-compose.yml): persistent data and Docker socket dependency
- [`Docker/astroneer/docker-compose.yml`](Docker/astroneer/docker-compose.yml): game server with multiple persistent volumes
- [`Docker/satisfactory/docker-compose.yml`](Docker/satisfactory/docker-compose.yml): game server with persistent config and resource requirements
- [`Docker/zomboid/docker-compose.yml`](Docker/zomboid/docker-compose.yml): game server with env file and persistent server data

### Special-case host-integrated apps

- [`Docker/adguardhome/docker-compose.yml`](Docker/adguardhome/docker-compose.yml): host networking, DNS, DHCP, low ports
- [`Docker/homeassistant/docker-compose.yml`](Docker/homeassistant/docker-compose.yml): host networking, privileged mode, USB device pass-through
- [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml): host networking and likely L2 wake-on-LAN behavior
- [`Docker/cadvisor/docker-compose.yml`](Docker/cadvisor/docker-compose.yml): host filesystem mounts, device access, privileged behavior
- [`Docker/traefik/docker-compose.yml`](Docker/traefik/docker-compose.yml): current ingress controller and certificate automation, but tightly coupled to Docker provider
- [`Docker/dns-update/docker-compose.yml`](Docker/dns-update/docker-compose.yml): controller-like background reconciler for Azure DNS

### Highest-complexity or least portable apps

- [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml): host networking, GPU, CIFS media share, heavy state
- [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml): mixed collection of apps, several share CIFS media storage, some require VPN or elevated networking

## Cross-cutting migration patterns

## Recommended storage strategy

Treat storage as three separate classes instead of one generic Kubernetes pattern.

### Class 1: App-owned persistent state

Use `PersistentVolumeClaim`-backed storage for each app's own writable data, such as:

- `/Apps/FinGlass:/app/data`
- `/Apps/Gitea:/data`
- `/Apps/open-webui/:/app/backend/data`
- `/Apps/n8n/data:/home/node/.n8n`
- `/Apps/n8n/files:/files`
- `/Apps/Monitoring/Prometheus:/prometheus`
- `/Apps/Monitoring/Grafana:/var/lib/grafana`
- `/Apps/HomeAssistant:/config`
- `/Apps/satisfactory:/config`
- `/Apps/zomboid/...`

Recommended rule:

- use one `PersistentVolumeClaim` per app data domain
- prefer `ReadWriteOnce` for normal app state
- use `StatefulSet` only when stable identity and storage attachment matter
- otherwise use `Deployment` plus mounted PVC

### Class 2: Shared media or NAS-backed storage

Do **not** treat NAS-backed media the same as local app state.

Affected workloads include [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml) and [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml).

Recommended rule:

- app config still gets its own PVC
- shared media library should use a dedicated NAS-backed `PersistentVolume`
- prefer SMB CSI or a statically defined PV for the `//192.168.10.12/Medias` share
- use `ReadWriteMany` only for shared media access where multiple apps need it
- validate `uid` and `gid` behavior currently encoded in the CIFS mount options

### Class 3: Config-only files

Do not burn persistent volumes on files that are really configuration.

Examples include:

- [`Docker/homepage-1/settings.yaml`](Docker/homepage-1/settings.yaml)
- [`Docker/homepage-1/services.yaml`](Docker/homepage-1/services.yaml)
- [`Docker/homepage-1/widgets.yaml`](Docker/homepage-1/widgets.yaml)
- [`Docker/homepage-1/bookmarks.yaml`](Docker/homepage-1/bookmarks.yaml)
- [`Docker/homepage-2/settings.yaml`](Docker/homepage-2/settings.yaml)
- [`Docker/monitoring/prometheus.yml`](Docker/monitoring/prometheus.yml)
- [`Docker/n8n/task-runners.json`](Docker/n8n/task-runners.json)

Recommended rule:

- use `ConfigMap` for non-secret config files
- use `Secret` for credential-bearing files and environment values
- mount them read-only into the pod filesystem

### Workload-by-workload storage handling

- FinGlass, gmap, termix, open-webui, joke-de-jean: single app PVC each
- pdf: start with no PVC unless persistent OCR, logs, or config are enabled later
- Gitea: dedicated PVC for `/data`, treated as critical state with backup-first migration
- monitoring: separate PVCs for Prometheus TSDB and Grafana data
- n8n: separate PVCs for workflow state and file storage
- homepage-1 and homepage-2: ConfigMaps for YAML files, PVC only if runtime data remains necessary
- Home Assistant: PVC for `/config`, but pin workload to the USB-capable node
- game servers: PVCs per world or config area, favor `StatefulSet` and graceful shutdown
- Plex and media apps: one PVC per app config plus a shared NAS-backed media volume
- AdGuard Home and Upsnap: PVCs for their writable application state, but only after networking placement is solved

### Data migration approach

For each stateful app, do the migration in this order:

1. create the target PVC or PV and confirm mount semantics
2. copy existing data from the `/Apps` path into the new volume
3. run the pod against the copied data in isolation
4. verify file ownership, startup, and write behavior
5. cut over traffic only after app-level validation
6. keep the original Docker data as rollback until Kubernetes is proven

### Storage policy summary

- default app state: dynamic PVC, usually `ReadWriteOnce`
- shared media: NAS-backed PV, likely `ReadWriteMany`
- config files: `ConfigMap`
- secrets and credentials: `Secret`
- avoid `hostPath` except where hardware or host integration forces it

## Cross-cutting migration patterns

### Pattern 1: Convert Traefik labels into Kubernetes ingress definitions

Most HTTP apps rely on Traefik labels in Compose. In Kubernetes, convert these into:

- `Ingress` objects or ingress-controller-specific CRDs
- `Service` per app
- TLS annotations and secret references
- host rules equivalent to the current label rules

Apps affected:

- FinGlass
- Gitea
- gmap
- homepage-1
- homepage-2
- monitoring stack
- n8n
- open-webui
- pdf
- plexapps web UIs
- portainer
- termix
- upsnap
- traefik dashboard if retained

### Pattern 2: Replace bind mounts and named volumes with PVC-backed storage classes

Most stateful apps bind mount host paths under `/Apps`. In Kubernetes, convert these to:

- `PersistentVolumeClaim` for app-owned persistent state
- optionally `StatefulSet` where stable identity and persistent attachment matter
- `Deployment` plus PVC where only persistence matters

Typical mappings:

- `/Apps/...:/data` or `/config` becomes PVC mount
- inline config files become `ConfigMap`
- secrets in env become `Secret`

### Pattern 3: Handle external NAS and CIFS separately from app-local state

Apps using the `medias` CIFS volume need a different pattern from local app data.

Affected apps:

- [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml)
- [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml)

Recommended treatment:

- app config data gets its own PVC
- shared media library gets a dedicated RWX storage strategy, likely SMB CSI or a pre-provisioned PV backed by the NAS share
- validate file ownership mapping currently done through `uid` and `gid`

### Pattern 4: Separate HTTP routing from host networking needs

Some apps expose HTTP behind Traefik today but also rely on host networking or direct UDP/TCP ports.

Migration implication:

- web-only access should use `Service` and `Ingress`
- raw game traffic or DNS traffic will likely need `LoadBalancer`, `NodePort`, or host networking depending on protocol
- low-level network appliances may not be good generic Kubernetes tenants

### Pattern 5: Convert Compose `env_file` and inline env into ConfigMaps and Secrets

Sensitive values observed across the stack include:

- Azure credentials in DNS updater and Traefik
- OpenAI and Microsoft OAuth secrets in open-webui
- VPN credentials in plexapps
- CIFS credentials in Plex and plexapps
- n8n auth token and domain settings
- game-server settings and env files where appropriate

Recommended split:

- non-secret runtime config into `ConfigMap`
- passwords, API keys, tokens, VPN creds, CIFS creds into `Secret`

### Pattern 6: Replace Compose `depends_on` with Kubernetes readiness and service discovery

Compose dependency sequencing appears in [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml). In Kubernetes:

- use separate Services for internal traffic
- use readiness probes
- rely on DNS service discovery instead of startup ordering

### Pattern 7: Bring health checks into probes

Observed explicit health checks:

- [`Docker/pdf/docker-compose.yml`](Docker/pdf/docker-compose.yml)
- [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml)

These should become:

- `startupProbe` for slow starters
- `readinessProbe` for traffic gating
- `livenessProbe` only where safe

For apps without health checks, probes should be added during migration if a stable endpoint exists.

## Kubernetes workload guidance by app

## 1. AdGuard Home

Source: [`Docker/adguardhome/docker-compose.yml`](Docker/adguardhome/docker-compose.yml)

### Characteristics

- Host network mode
- DNS on TCP and UDP 53
- DHCP-related ports 67 and 68
- Persistent work and config directories

### Recommended Kubernetes shape

- Treat as a special-case infrastructure workload
- Prefer dedicated nodes if moved at all
- likely `Deployment` or `StatefulSet` with `hostNetwork: true`
- host port exposure or `LoadBalancer` with mixed TCP and UDP if supported
- PVCs for `/opt/adguardhome/work` and `/opt/adguardhome/conf`

### Migration checklist

- Identify whether Kubernetes will truly own DNS and DHCP responsibilities
- Decide whether DHCP will remain outside Kubernetes
- Validate cluster CNI and load balancer support for mixed TCP and UDP low ports
- Convert persistent paths into PVCs
- Add security context carefully because low ports and host networking are involved
- Add probes for admin UI and DNS process if supported
- Plan maintenance window because DNS cutover is sensitive

## 2. Astroneer

Source: [`Docker/astroneer/docker-compose.yml`](Docker/astroneer/docker-compose.yml)

### Characteristics

- Custom image build path present
- TCP and UDP game ports
- three persistent volumes: game data, steamcmd, backup

### Recommended Kubernetes shape

- `StatefulSet` preferred for stable persistent attachment
- one `Service` for game traffic, possibly `LoadBalancer` or `NodePort`
- PVCs for each data area or one combined PVC if simpler operationally

### Migration checklist

- Decide whether the image will continue to be built in-repo or published externally first
- Convert env vars into ConfigMap and Secret where needed
- Map TCP and UDP exposure with a Kubernetes Service that supports both
- Create PVCs for `/astroneer`, `/steamcmd`, and `/backup`
- Define a graceful shutdown policy for save integrity
- Add resource requests and limits after first baseline

## 3. cAdvisor

Source: [`Docker/cadvisor/docker-compose.yml`](Docker/cadvisor/docker-compose.yml)

### Characteristics

- Privileged container
- host rootfs and runtime mounts
- device access to `/dev/kmsg`

### Recommended Kubernetes shape

- `DaemonSet` if needed across nodes
- only if host-level container metrics are still required in the future cluster

### Migration checklist

- Decide whether cAdvisor is still needed versus kubelet metrics and node exporters
- If kept, convert to DaemonSet with hostPath mounts
- add tolerations if metrics are needed on all nodes
- restrict via dedicated namespace and minimal RBAC if required
- avoid treating this as a normal application migration

## 4. DNS updater

Sources: [`Docker/dns-update/docker-compose.yml`](Docker/dns-update/docker-compose.yml), [`Docker/dns-update/Dockerfile`](Docker/dns-update/Dockerfile), [`Docker/dns-update/update_dns.sh`](Docker/dns-update/update_dns.sh)

### Characteristics

- Custom image
- long-running reconciliation loop
- Azure authentication and DNS mutation

### Recommended Kubernetes shape

- `Deployment` with single replica
- ConfigMap for static settings
- Secret for Azure credentials

### Migration checklist

- Publish the custom image to a registry accessible by the future cluster
- Split env file values into ConfigMap and Secret
- mount no persistent storage unless logging requirements demand it
- add liveness and readiness probes if a safe endpoint can be introduced; otherwise rely on restart policy initially
- consider rewriting later as a CronJob or controller only if behavior should change

## 5. FinGlass

Source: [`Docker/FinGlass/docker-compose.yml`](Docker/FinGlass/docker-compose.yml)

### Characteristics

- Persistent app data
- HTTP app exposed via Traefik labels

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- PVC for `/app/data`

### Migration checklist

- Convert app storage to PVC
- translate Traefik labels into ingress host rules and TLS
- add readiness and liveness probes for port 8000
- define resource requests
- externalize app settings into ConfigMap or Secret if needed

## 6. Gitea

Source: [`Docker/gitea/docker-compose.yml`](Docker/gitea/docker-compose.yml)

### Characteristics

- Persistent `/data`
- HTTP on 3000
- SSH on 222
- timezone mounts
n### Recommended Kubernetes shape

- `StatefulSet` preferred
- `Service` for web traffic
- separate `Service` for SSH
- `Ingress` for web UI
- PVC for `/data`

### Migration checklist

- Move `/data` to PVC
- replace timezone bind mounts with node time defaults or omit unless required
- expose web and SSH separately
- confirm whether SSH should be a LoadBalancer, NodePort, or internal-only service
- add probes for web endpoint
- plan backup and restore validation before cutover

## 7. gmap

Source: [`Docker/gmap/docker-compose.yml`](Docker/gmap/docker-compose.yml)

### Characteristics

- Persistent run data
- HTTP app on container port 5000

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- PVC for `/app/data_runs`

### Migration checklist

- move data directory to PVC
- convert ingress labels to Ingress
- add probes for the Flask or app HTTP endpoint
- document storage growth expectations

## 8. Home Assistant

Sources: [`Docker/homeassistant/docker-compose.yml`](Docker/homeassistant/docker-compose.yml), [`Docker/homeassistant/README-zigbee-usb.md`](Docker/homeassistant/README-zigbee-usb.md)

### Characteristics

- Host networking
- privileged mode
- USB device pass-through for Zigbee
- persistent config

### Recommended Kubernetes shape

- special-case workload only
- likely a pinned `Deployment` with `hostNetwork: true`, privileged security context, and node affinity to the USB-attached node
- PVC for `/config`

### Migration checklist

- decide whether Home Assistant belongs in Kubernetes at all
- identify the exact node that will host the Zigbee dongle
- define node affinity and anti-rescheduling policy so the pod stays near the USB device
- convert `/config` to PVC
- model device access using hostPath `/dev/ttyUSB-zigbee` or device plugin strategy
- preserve privileged behavior only if strictly required
- verify multicast, discovery, and host-network integrations on the chosen CNI
- document operational runbook for USB recovery similar to the current Markdown guide

## 9. Homepage 1

Source: [`Docker/homepage-1/docker-compose.yml`](Docker/homepage-1/docker-compose.yml)

### Characteristics

- several local config files
- optional Docker socket mount
- persistent data directory on one instance

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- ConfigMap from YAML files
- PVC only if `/app/data` remains needed

### Migration checklist

- convert config YAML files into ConfigMaps
- decide whether Docker socket integration should be removed because it does not translate to Kubernetes cleanly
- if runtime data is needed, add PVC
- convert ingress labels to Ingress
- if two homepages are meant for two environments, treat them as separate instances with shared template pattern

## 10. Homepage 2

Source: [`Docker/homepage-2/docker-compose.yml`](Docker/homepage-2/docker-compose.yml)

### Characteristics

- same pattern as homepage-1 without explicit persistent app data
- Docker socket mount present

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- ConfigMap from YAML files

### Migration checklist

- convert YAML configs into ConfigMaps
- replace Docker socket dependent widgets or remove them
- convert ingress labels to Ingress
- add probes for port 3000

## 11. Joke de Jean

Source: [`Docker/joke-de-jean/docker-compose.yml`](Docker/joke-de-jean/docker-compose.yml)

### Characteristics

- background worker style container
- persistent local data
- simple env flag

### Recommended Kubernetes shape

- `Deployment`
- PVC for data

### Migration checklist

- define whether single replica is required to avoid duplicate bot processing
- convert env flag into ConfigMap
- move data directory to PVC
- add probes only if the container exposes a usable health endpoint
- document failure semantics and restart tolerance

## 12. Monitoring stack

Sources: [`Docker/monitoring/docker-compose.yml`](Docker/monitoring/docker-compose.yml), [`Docker/monitoring/prometheus.yml`](Docker/monitoring/prometheus.yml)

### Characteristics

- Prometheus config file plus persistent TSDB
- Grafana persistent data
- static scrape targets today, including commented future k8s nodes

### Recommended Kubernetes shape

- Prometheus as `StatefulSet` or `Deployment` plus PVC
- Grafana as `Deployment` plus PVC
- separate Services and Ingresses
- ConfigMap for `prometheus.yml`

### Migration checklist

- move Prometheus TSDB to PVC
- move Grafana data to PVC
- convert `prometheus.yml` to ConfigMap
- review static scrape targets and plan future cluster monitoring approach
- add probes for Prometheus and Grafana
- replace inline Grafana admin password with Secret

## 13. n8n

Sources: [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml), [`Docker/n8n/Dockerfile`](Docker/n8n/Dockerfile), [`Docker/n8n/task-runners.json`](Docker/n8n/task-runners.json)

### Characteristics

- main app plus custom task-runner workload
- persistent workflow and file storage
- internal broker port between workloads
- custom-built runner image

### Recommended Kubernetes shape

- main n8n as `Deployment` or `StatefulSet` if stable persistence handling is preferred
- task runners as separate `Deployment`
- internal `Service` for runner broker connectivity
- `Ingress` for web UI
- PVCs for `.n8n` data and `/files`
- ConfigMap for runner JSON if kept externalized

### Migration checklist

- publish the custom runner image
- create separate workloads for n8n and task runners
- replace `depends_on` with Service-based discovery and probes
- move `.n8n` data and `/files` to PVCs
- split runtime config into ConfigMap and Secret
- expose port 5678 externally through Ingress and keep broker port internal-only
- define pod security because the current app runs as root
- add probes for both n8n and runner health ports if available

## 14. Open WebUI

Source: [`Docker/open-webui/docker-compose.yml`](Docker/open-webui/docker-compose.yml)

### Characteristics

- secrets-heavy config
- persistent backend data
- web ingress

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- PVC for backend data
- Secret for OAuth and API keys

### Migration checklist

- move `/app/backend/data` to PVC
- convert all API keys and OAuth values into Secret
- keep non-secret env such as base URL in ConfigMap
- translate ingress labels to Ingress
- add probes on port 8080

## 15. PDF

Source: [`Docker/pdf/docker-compose.yml`](Docker/pdf/docker-compose.yml)

### Characteristics

- explicit healthcheck
- currently no persistent storage enabled
- web ingress

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- optional PVC only if enabling persistent config, logs, or OCR data later

### Migration checklist

- translate the Compose healthcheck into startup and readiness probes
- move env vars into ConfigMap
- decide whether the commented persistent paths should remain disabled
- convert ingress labels to Ingress

## 16. Plex

Source: [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml)

### Characteristics

- host networking
- NVIDIA GPU reservation
- persistent config
- external CIFS media share

### Recommended Kubernetes shape

- special-case stateful workload
- `Deployment` or `StatefulSet` pinned to a GPU-capable node
- host networking may still be required depending on discovery needs
- PVC for config
- NAS-backed RWX volume for media share

### Migration checklist

- confirm GPU support path in the future cluster using NVIDIA device plugin or equivalent
- define node affinity for the GPU node
- move `/config` to PVC
- provision the media share via SMB CSI or static PV, preserving ownership expectations
- verify whether host networking is mandatory for Plex discovery and DLNA behavior
- add tolerations or dedicated node placement if this remains a heavy media workload
- test transcoding and library refresh before cutover

## 17. Plex apps bundle

Source: [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml)

### Characteristics

- mixture of Overseerr, Jackett, FlareSolverr, Radarr, Sonarr, Transmission with OpenVPN, qBittorrent VPN
- multiple apps rely on shared media storage
- some apps need VPN or elevated network/device permissions

### Recommended Kubernetes shape

- split into separate workloads per app rather than a monolith
- standard web apps as `Deployment` plus `Service` plus `Ingress`
- media automation apps get config PVC plus shared media RWX mount
- VPN-bound apps are special case and should be migrated late

### Migration checklist

- decompose into per-app manifests and migration sequence
- create individual PVCs for app configs: Overseerr, Jackett, Radarr, Sonarr, qBittorrent
- provide shared media PV or PVC backed by NAS for `/medias`
- convert web UIs to Services and Ingresses
- evaluate whether Transmission OpenVPN and qBittorrent VPN should stay outside Kubernetes initially because of `NET_ADMIN`, `/dev/net/tun`, and VPN side effects
- if VPN apps are migrated, plan dedicated security context, egress validation, and node-level networking tests
- externalize OVPN profile and credentials into Secret or mounted secret file

## 18. Portainer

Source: [`Docker/portainer/docker-compose.yml`](Docker/portainer/docker-compose.yml)

### Characteristics

- persistent data
- Docker socket mount
- multiple exposed ports

### Recommended Kubernetes shape

- not a priority app migration target
- if retained, use Portainer in Kubernetes-native mode rather than Docker-socket mode

### Migration checklist

- decide whether Portainer is still needed once apps move to Kubernetes
- if yes, deploy it in a Kubernetes-supported pattern instead of mounting Docker socket
- move Portainer data to PVC
- expose only required ports and prefer ingress for UI
- treat this as management tooling, not a standard app migration

## 19. Satisfactory

Source: [`Docker/satisfactory/docker-compose.yml`](Docker/satisfactory/docker-compose.yml)

### Characteristics

- UDP and TCP game ports
- persistent config
- explicit high memory expectations

### Recommended Kubernetes shape

- `StatefulSet`
- game `Service` with UDP and TCP handling
- PVC for `/config`

### Migration checklist

- convert `/config` to PVC
- expose required TCP and UDP ports through an appropriate Service type
- carry over memory requests and limits based on current Compose values
- define graceful stop behavior to protect world data
- pin to suitable nodes if CPU or memory pressure is significant

## 20. Termix

Source: [`Docker/termix/docker-compose.yml`](Docker/termix/docker-compose.yml)

### Characteristics

- root user today
- persistent data
- ingressed web app

### Recommended Kubernetes shape

- `Deployment`
- `Service`
- `Ingress`
- PVC for `/app/data`

### Migration checklist

- move data directory to PVC
- translate ingress labels to Ingress
- assess whether root execution is truly required and reduce privileges if possible
- add probes on port 8080

## 21. Traefik

Source: [`Docker/traefik/docker-compose.yml`](Docker/traefik/docker-compose.yml)

### Characteristics

- uses Docker provider today
- ACME DNS challenge with Azure credentials
- exposes web, websecure, and dashboard ports

### Recommended Kubernetes shape

- this is cluster infrastructure, not just an app conversion
- for planning purposes, assume labels are replaced by Kubernetes ingress resources and an ingress controller will be selected later

### Migration checklist

- do not directly port the Docker-provider model
- convert app-specific Traefik labels into generic ingress requirements
- if Traefik remains the chosen controller later, use Kubernetes CRDs or standard Ingress backed by Traefik provider for Kubernetes
- store Azure ACME credentials as Secrets
- plan certificate storage separate from application migrations

## 22. Upsnap

Source: [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml)

### Characteristics

- host networking
- wake-on-LAN style behavior likely tied to LAN broadcast
- persistent pocketbase data
- health endpoint available

### Recommended Kubernetes shape

- special-case workload
- likely `Deployment` with `hostNetwork: true`
- pinned to a node with correct LAN reachability
- PVC for `/app/pb_data`

### Migration checklist

- verify whether wake-on-LAN broadcast packets work from pods in the future network model
- decide whether host networking is mandatory
- move data to PVC
- convert healthcheck to readiness and liveness probes
- expose UI via ingress only if reachable without Docker-label assumptions

## 23. Zomboid

Source: [`Docker/zomboid/docker-compose.yml`](Docker/zomboid/docker-compose.yml)

### Characteristics

- UDP and TCP game ports
- env file usage
- two persistent directories
- graceful stop time configured

### Recommended Kubernetes shape

- `StatefulSet`
- `Service` for game ports
- PVCs for server files and server data

### Migration checklist

- split `.env` content into ConfigMap and Secret as appropriate
- convert both persistent directories into PVCs
- implement termination grace period matching the current Compose behavior
- expose required UDP and TCP ports through an appropriate Service type
- validate world save integrity during pod restart tests

## Additional non-storage considerations

### Networking and exposure model

Decide early how each app will be exposed in Kubernetes:

- `Ingress` for normal HTTP and HTTPS apps
- `ClusterIP` Services for internal-only traffic
- `LoadBalancer` or `NodePort` for raw TCP and UDP services
- `hostNetwork: true` only for exceptional workloads

This is especially important for [`Docker/adguardhome/docker-compose.yml`](Docker/adguardhome/docker-compose.yml), [`Docker/homeassistant/docker-compose.yml`](Docker/homeassistant/docker-compose.yml), [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml), [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml), [`Docker/astroneer/docker-compose.yml`](Docker/astroneer/docker-compose.yml), [`Docker/satisfactory/docker-compose.yml`](Docker/satisfactory/docker-compose.yml), and [`Docker/zomboid/docker-compose.yml`](Docker/zomboid/docker-compose.yml).

### Secrets and configuration hygiene

Standardize how secrets are handled before converting many apps:

- put non-secret runtime configuration in `ConfigMap`
- put passwords, API keys, tokens, cloud credentials, VPN credentials, and CIFS credentials in `Secret`
- avoid embedding credentials directly in manifests

This affects apps such as [`Docker/open-webui/docker-compose.yml`](Docker/open-webui/docker-compose.yml), [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml), [`Docker/dns-update/update_dns.sh`](Docker/dns-update/update_dns.sh), [`Docker/traefik/docker-compose.yml`](Docker/traefik/docker-compose.yml), and [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml).

### Health checks and startup behavior

Kubernetes needs explicit probe definitions instead of relying only on restart policies.

Plan probe behavior for:

- `startupProbe` for slow-starting apps
- `readinessProbe` for traffic gating
- `livenessProbe` only where safe and low-risk

Known good starting points already exist in [`Docker/pdf/docker-compose.yml`](Docker/pdf/docker-compose.yml) and [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml).

### Security context and privilege requirements

Several apps currently rely on elevated privileges, root execution, or device and host access.

Review and minimize use of:

- privileged containers
- root users
- `hostPath`
- `NET_ADMIN`
- `/dev/net/tun`
- direct device mounts
- GPU access

This is critical for [`Docker/homeassistant/docker-compose.yml`](Docker/homeassistant/docker-compose.yml), [`Docker/cadvisor/docker-compose.yml`](Docker/cadvisor/docker-compose.yml), [`Docker/plexapps/docker-compose.yml`](Docker/plexapps/docker-compose.yml), [`Docker/termix/docker-compose.yml`](Docker/termix/docker-compose.yml), and [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml).

### Node placement and hardware affinity

Some apps cannot be freely scheduled on any node.

Plan node affinity, taints, or dedicated nodes for:

- USB-attached workloads such as [`Docker/homeassistant/docker-compose.yml`](Docker/homeassistant/docker-compose.yml)
- GPU workloads such as [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml)
- network-sensitive workloads such as [`Docker/adguardhome/docker-compose.yml`](Docker/adguardhome/docker-compose.yml)
- broadcast-sensitive workloads such as [`Docker/upsnap/docker-compose.yml`](Docker/upsnap/docker-compose.yml)

### Image build and registry strategy

Resolve how custom images will be built and published before implementation.

This matters for [`Docker/dns-update/Dockerfile`](Docker/dns-update/Dockerfile), [`Docker/n8n/Dockerfile`](Docker/n8n/Dockerfile), and the build flow referenced in [`Docker/astroneer/docker-compose.yml`](Docker/astroneer/docker-compose.yml).

Define:

- image registry location
- tag strategy
- update workflow
- whether mutable tags such as `latest` will be replaced with versioned tags

### Backup, restore, and rollback

For every stateful app, define:

- what data must be backed up
- how restore will be validated
- how rollback to Docker remains possible during migration

This is highest priority for Gitea, n8n, Home Assistant, Prometheus, Grafana, Plex, and the game servers.

### Resource planning and scheduling safety

Compose does not fully express the Kubernetes scheduling model.

Define per app:

- CPU requests and limits
- memory requests and limits
- termination grace periods
- expected startup time and restart behavior

This is especially important for [`Docker/satisfactory/docker-compose.yml`](Docker/satisfactory/docker-compose.yml), [`Docker/plex/docker-compose.yml`](Docker/plex/docker-compose.yml), [`Docker/n8n/docker-compose.yml`](Docker/n8n/docker-compose.yml), and [`Docker/open-webui/docker-compose.yml`](Docker/open-webui/docker-compose.yml).

### Platform versus application boundary

Separate normal applications from cluster infrastructure and host-level tooling.

Do not treat everything in [`Docker/`](Docker) as the same migration shape. In particular:

- [`Docker/traefik/docker-compose.yml`](Docker/traefik/docker-compose.yml) is cluster ingress infrastructure
- [`Docker/cadvisor/docker-compose.yml`](Docker/cadvisor/docker-compose.yml) is node-level observability
- [`Docker/adguardhome/docker-compose.yml`](Docker/adguardhome/docker-compose.yml) is a network appliance style workload
- [`Docker/portainer/docker-compose.yml`](Docker/portainer/docker-compose.yml) is management tooling

## Migration order

### Wave 1: straightforward HTTP apps

- FinGlass
- gmap
- open-webui
- pdf
- termix
- joke-de-jean

### Wave 2: stateful web and ops apps

- monitoring stack
- n8n
- Gitea
- homepage-1
- homepage-2

### Wave 3: game servers

- Astroneer
- Satisfactory
- Zomboid

### Wave 4: host-integrated or privileged apps

- Upsnap
- AdGuard Home
- Home Assistant
- cAdvisor
- Portainer

### Wave 5: heavy media and VPN workloads

- Plex
- Overseerr
- Jackett
- FlareSolverr
- Radarr
- Sonarr
- Transmission OpenVPN
- qBittorrent VPN

## Prerequisites the future implementation phase must satisfy

- a default `StorageClass` for app-local PVCs
- a NAS strategy for shared media data and any RWX requirements
- an ingress strategy, with TLS and DNS automation model chosen later
- a secret management approach for API keys, cloud credentials, VPN creds, and CIFS creds
- a way to expose mixed TCP and UDP services for game servers and DNS-style services
- a node placement strategy for USB, GPU, and host-network workloads
- backup and restore procedures for every migrated stateful app

## Major risks to track

- host-network workloads may not behave well under a generic cluster design
- USB and GPU dependencies will force node affinity and operational constraints
- VPN-based torrent clients are poor early migration candidates due to elevated network requirements
- CIFS media volumes need careful permission mapping and throughput validation
- app data migration must be tested before cutover for Gitea, n8n, monitoring, Home Assistant, Plex, and game servers
- Compose labels currently encode routing intent that must be translated consistently into ingress definitions

## Minimal execution plan for the future implementation mode

1. Define reusable conversion templates for web apps, stateful apps, and game servers
2. Migrate Wave 1 apps first to validate storage, ingress, secrets, and probes
3. Migrate Wave 2 apps and validate backup and restore procedures
4. Migrate game servers with explicit TCP and UDP service testing
5. Handle host-integrated apps only after node placement and privileged workload rules exist
6. Migrate Plex and VPN-based media stack last after storage and networking patterns are proven

# Tailscale Infrastructure Configurations

This directory defines the configuration and operational workloads for Tailnet connectivity in the cluster:
1. **Azure Key Vault ExternalSecrets**: OAuth credentials for the Tailscale Operator and auth keys for the Site-to-Site Gateway.
2. **Standalone Site-to-Site (LAN-to-LAN) HostNetwork Gateway**: Bidirectional cross-site VPN router directly on Talos Linux nodes, replacing legacy Ubuntu router VMs (`Ansible/playbooks/tailscale-routers.yml`).

---

## Site-to-Site LAN VPN Architecture

The Site-to-Site VPN connects Home 1 (`192.168.10.0/24`) and Home 2 (`192.168.15.0/24`) transparently with **source IP preservation** and zero double-NAT.

### Topology

| Parameter | Home 1 (`k8s-talos-1`) | Home 2 (`k8s-talos-2`) |
| :--- | :--- | :--- |
| **Site / Host** | Home 1 (`pve-1`) | Home 2 (`pve-2`) |
| **Local LAN Subnet** | `192.168.10.0/24` | `192.168.15.0/24` |
| **Default Router / Gateway** | `192.168.10.1` | `192.168.15.1` |
| **Talos Gateway Node IP** | `192.168.10.15` | `192.168.15.15` |
| **Node Selector Label** | `tailscale-s2s-gateway: "true"` | `tailscale-s2s-gateway: "true"` |
| **Advertised Subnet (`TS_ROUTES`)** | `192.168.10.0/24` | `192.168.15.0/24` |
| **Tailscale Hostname** | `k8s-talos-1-s2s-router` | `k8s-talos-2-s2s-router` |
| **DHCP Option 121 Route** | `192.168.15.0/24 via 192.168.10.15` | `192.168.10.0/24 via 192.168.15.15` |

---

## Architectural Principles

1. **Standalone `hostNetwork: true` Deployment (No Operator `Connector` CRD)**:
   - While the Tailscale Operator manages Ingresses and Funnels within the cluster, its `Connector` CRD runs in the isolated Pod network without host routing.
   - Non-Tailscale LAN clients route cross-site packets directly to the Talos physical node IP (`192.168.10.15` or `192.168.15.15`) via DHCP Option 121.
   - The standalone Deployment runs with `hostNetwork: true` and `TS_USERSPACE=false`. This mounts `/dev/net/tun` and establishes `tailscale0`, kernel routing table `52`, and `iptables` TCP MSS clamping (`ts-forward`) directly in the Talos host kernel.

2. **Preserved Source IPs (`--snat-subnet-routes=false`)**:
   - `TS_EXTRA_ARGS="--snat-subnet-routes=false --accept-dns=false ..."` disables subnet SNAT. LAN clients communicate peer-to-peer while seeing genuine client source IPs.
   - `--accept-dns=false` prevents MagicDNS from overriding the Talos node host `/etc/resolv.conf`.

3. **Talos Host Kernel Configuration**:
   - `net.ipv4.ip_forward: "1"`: Enables kernel forwarding between `eth0` and `tailscale0`.
   - `net.ipv4.conf.all.rp_filter: "2"`: Enables loose reverse path filtering so asymmetric cross-site traffic is not dropped by the kernel.
   - Applied via Omni cluster patch `K8s/Omni/clusters/patches/tailscale-gateway.yaml`.

4. **Pod Security Standards (Talos Requirement)**:
   - The `tailscale` namespace is labeled with `pod-security.kubernetes.io/enforce: privileged` in `K8s/infrastructure/controllers/tailscale/namespace.yaml` to permit `hostNetwork: true`, `hostPath` for `/dev/net/tun`, and `NET_ADMIN`/`NET_RAW` capabilities.

5. **Azure Key Vault Secrets Reuse (`operator-oauth`)**:
   - Reuses the existing Tailscale OAuth credentials already stored in Azure Key Vault (`gjtaloskv`):
     - `tailscale-k8s-client-id` -> `client_id`
     - `tailscale-k8s-secret` -> `client_secret` / `TS_AUTHKEY`
   - Tailscale v1.54+ accepts OAuth client secrets (`tskey-client-...`) directly into `TS_AUTHKEY` alongside `--advertise-tags=tag:k8s-operator`. No new or separate secrets need to be added to Azure Key Vault!
   - Tailscale machine state (`tailscale-s2s-state`) is persisted across pod restarts in a Kubernetes Secret via `TS_KUBE_SECRET`.

---

## Azure Key Vault Credentials

The gateway reuses the existing `operator-oauth` secret synchronized from Azure Key Vault (`gjtaloskv`) by External Secrets Operator:

| Secret in Azure Key Vault | Target Secret in K8s | Key in Target Secret | Used By |
| :--- | :--- | :--- | :--- |
| `tailscale-k8s-secret` | `operator-oauth` | `client_secret` / `TS_AUTHKEY` | Tailscale Operator & S2S Gateway |
| `tailscale-k8s-client-id` | `operator-oauth` | `client_id` | Tailscale Operator |

Because `operator-oauth` is already active in your cluster, **no manual secrets or keys need to be created in Azure Key Vault**.

---

## Runtime Verification Commands

### 1. Verify Deployment & Pod Status
```bash
kubectl --context admin@k8s-talos-1 -n tailscale get deploy,pod -l app=tailscale-lan-s2s
kubectl --context admin@k8s-talos-2 -n tailscale get deploy,pod -l app=tailscale-lan-s2s
```

### 2. Verify Tailscale Status Inside Container
```bash
kubectl --context admin@k8s-talos-1 -n tailscale exec deploy/tailscale-lan-s2s-gateway -- tailscale status
```

### 3. Verify Host Routing Table on Talos Node
```bash
# Verify table 52 contains the remote subnet route
talosctl -n 192.168.10.15 get routes
```

### 4. Test Cross-Site Connectivity
```bash
# From Home 1 node to Home 2 node API server:
kubectl --context admin@k8s-talos-1 -n headlamp exec deploy/headlamp -- nc -zv 192.168.15.15 6443

# From Home 2 node to Home 1 node API server:
kubectl --context admin@k8s-talos-2 -n headlamp exec deploy/headlamp -- nc -zv 192.168.10.15 6443
```


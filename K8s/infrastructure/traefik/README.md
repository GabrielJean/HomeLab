# Traefik Ingress Controller

Traefik acts as the external HTTP(S) entrypoint and reverse proxy for each Talos cluster.

## Architecture

- **Helm Managed**: Deployed via official Traefik Helm chart through Flux `HelmRelease`.
- **HostPort Binding**: Binds directly to ports `80` and `443` on the node host (`talos-1`: `192.168.10.15`, `talos-2`: `192.168.20.15`) via CNI portmap, eliminating the need for MetalLB or external cloud load balancers.
- **HTTP -> HTTPS Redirect**: All traffic hitting port `80` automatically redirects to `443` (`websecure`).
- **IngressClass**: Deployed as the default `traefik` IngressClass across the cluster.
- **CRD & Standard Ingress**: Traefik watches standard Kubernetes `Ingress` resources and Traefik `IngressRoute` CRDs.

## Directory Structure

```
├── namespace.yaml        # 'traefik' namespace with privileged PSA for hostPort
├── helmrepository.yaml   # Traefik official Helm repository
├── helmrelease.yaml      # Traefik HelmRelease with single-node values
├── kustomization.yaml    # Kustomize aggregation
└── README.md             # Documentation
```


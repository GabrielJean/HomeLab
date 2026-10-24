# Kubernetes Gateway API

Standard Channel Custom Resource Definitions (CRDs) for the Kubernetes Gateway API (`gateway.networking.k8s.io`):
- `GatewayClass`
- `Gateway`
- `HTTPRoute`
- `GRPCRoute`
- `ReferenceGrant`

## Architecture

The Gateway API is the modern successor to Kubernetes Ingress:
- **Role-Oriented**: Platform operators manage `GatewayClass` and `Gateway` listeners (ports, TLS), while application developers manage `HTTPRoute` objects attached to the Gateway.
- **Controller**: Traefik acts as the Gateway controller via its `kubernetesGateway` provider (`controllerName: traefik.io/gateway-controller`).
- **Coexistence**: Traefik handles standard `Ingress`, `IngressRoute` CRDs, and `Gateway API` concurrently.

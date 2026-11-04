# Kubernetes Gateway API

Standard & Experimental Channel Custom Resource Definitions (CRDs) for the Kubernetes Gateway API (`gateway.networking.k8s.io`):
- `GatewayClass` (v1)
- `Gateway` (v1)
- `HTTPRoute` (v1)
- `GRPCRoute` (v1)
- `TLSRoute` (v1)
- `TCPRoute` (v1)
- `ReferenceGrant` (v1)

## Architecture

The Gateway API is the modern successor to Kubernetes Ingress:
- **Role-Oriented**: Platform operators manage `GatewayClass` and `Gateway` listeners (ports, TLS), while application developers manage `HTTPRoute` objects attached to the Gateway.
- **Controller**: Traefik acts as the Gateway controller via its `kubernetesGateway` provider (`controllerName: traefik.io/gateway-controller`).
- **Coexistence**: Traefik handles standard `Ingress`, `IngressRoute` CRDs, and `Gateway API` concurrently.

## Example: Routing an Application with `HTTPRoute`

Developers can expose services without touching global listener or TLS configurations:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - "myapp.talos-1.gwebs.ca"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app-service
          port: 8080
```



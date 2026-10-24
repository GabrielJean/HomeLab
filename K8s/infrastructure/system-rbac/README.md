# System & Control Plane RBAC

System-level and control plane Role-Based Access Control (RBAC) bindings for the Homelab Kubernetes clusters.

---

## What is this for? Do you still need it?

**Yes.** In Kubernetes 1.30+ and modern Talos Linux clusters, Kubelets enforce **Webhook Authorization** (`--authorization-mode=Webhook`):

1. **Why it exists**:
   When Kubernetes components (such as `kube-apiserver`, `kubectl exec`, `kubectl logs`, or Talos's internal static pod controller) communicate with a node's Kubelet on HTTPS port 10250, they present a client certificate with the identity:
   `User: apiserver-kubelet-client`

2. **The Webhook Authorization Check**:
   Kubelet does not assume the API server is trusted by default. Instead, it queries the API server via a `SubjectAccessReview` asking:
   > *"Is user `apiserver-kubelet-client` permitted to perform `get` on `nodes/pods` or `nodes/proxy`?"*

3. **What happens without this binding**:
   Without binding `apiserver-kubelet-client` to `system:kubelet-api-admin`, the API server denies the check, and Kubelet responds with:
   `Authorization error (user=apiserver-kubelet-client, verb=get, resource=nodes, subresource=pods)`
   This can cause Talos machine status checks to fail, block `kubectl logs` / `kubectl exec`, or disrupt health controllers.

---

## Manifests

| File | Resource | Purpose |
| :--- | :--- | :--- |
| [`apiserver-kubelet.yaml`](apiserver-kubelet.yaml) | `ClusterRoleBinding/apiserver-kubelet-admin` | Authorizes `apiserver-kubelet-client` with `system:kubelet-api-admin` ClusterRole |
| [`kustomization.yaml`](kustomization.yaml) | `Kustomization` | Bundles system RBAC manifests for Flux GitOps |

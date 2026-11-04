# Kubernetes Metrics Server

Deploys the standard Kubernetes [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) into `kube-system` via Flux CD HelmRelease.

## Overview
- **Role**: Collects resource metrics from Kubelets and exposes them through the `metrics.k8s.io` API.
- **Consumers**: Headlamp (CPU & memory graphs), Horizontal Pod Autoscaler (HPA), and `kubectl top nodes` / `kubectl top pods`.
- **Talos Linux Compatibility**: Configured with `--kubelet-insecure-tls` to allow scraping Kubelet endpoints without requiring manual CSR approvals.

#!/usr/bin/env bash
# ==============================================================================
# Script: bootstrap-cluster.sh
# Purpose: Clean, idempotent GitOps bootstrap for a Talos Kubernetes cluster
# ==============================================================================
set -euo pipefail

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
    echo "Usage: $0 <cluster-name> [kubectl-context]"
    echo "Examples:"
    echo "  $0 k8s-talos-1"
    echo "  $0 k8s-talos-2 admin@k8s-talos-2"
    exit 1
fi

CONTEXT="${2:-admin@$CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/K8s/clusters/$CLUSTER_NAME"

if [ ! -d "$CLUSTER_DIR" ]; then
    echo "Error: Cluster directory not found: $CLUSTER_DIR"
    exit 1
fi

echo "=================================================================="
echo " Bootstrapping GitOps on cluster: $CLUSTER_NAME"
echo " Target Context: $CONTEXT"
echo " Manifest Source: $CLUSTER_DIR"
echo "=================================================================="

# 1. Install Flux namespace, CRDs, and controllers
echo "--> [1/4] Applying Flux components and CRDs..."
kubectl --context "$CONTEXT" apply -f "$CLUSTER_DIR/flux-system/gotk-components.yaml"

# 2. Wait for Flux CRDs to be registered and established
echo "--> [2/4] Waiting for Flux CRDs to become established..."
kubectl --context "$CONTEXT" wait --for=condition=Established --timeout=90s \
    crd/gitrepositories.source.toolkit.fluxcd.io \
    crd/kustomizations.kustomize.toolkit.fluxcd.io \
    crd/helmreleases.helm.toolkit.fluxcd.io \
    crd/helmrepositories.source.toolkit.fluxcd.io

# 3. Wait for controllers to become ready
echo "--> [3/4] Waiting for Flux controllers to become available..."
kubectl --context "$CONTEXT" wait --for=condition=Available --timeout=120s \
    deployment/source-controller \
    deployment/kustomize-controller \
    deployment/helm-controller \
    -n flux-system

# 4. Apply cluster root GitOps definitions (GitRepository, Kustomizations)
echo "--> [4/4] Applying cluster GitOps definitions..."
kubectl --context "$CONTEXT" apply -k "$CLUSTER_DIR"

echo "=================================================================="
echo "✔ GitOps bootstrap successful for $CLUSTER_NAME!"
echo "Flux is now reconciling all infrastructure and apps autonomously."
echo "Track status with: flux --context $CONTEXT get all"
echo "=================================================================="

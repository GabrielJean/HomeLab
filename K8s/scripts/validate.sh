#!/usr/bin/env bash
# ==============================================================================
# Script: validate.sh
# Purpose: Pre-commit / CI validation for Kustomize manifests and HelmRelease schemas
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Validating Kustomize build for k8s-talos-1..."
kubectl kustomize "$REPO_ROOT/K8s/clusters/k8s-talos-1" > /dev/null
echo "✔ k8s-talos-1 build OK"

echo "==> Validating Kustomize build for k8s-talos-2..."
kubectl kustomize "$REPO_ROOT/K8s/clusters/k8s-talos-2" > /dev/null
echo "✔ k8s-talos-2 build OK"

echo "==> Validating Traefik HelmRelease schema..."
python3 -c "
import urllib.request, tarfile, io, json, yaml, jsonschema

url = 'https://traefik.github.io/charts/traefik/traefik-42.1.3.tgz'
resp = urllib.request.urlopen(url)
tar = tarfile.open(fileobj=io.BytesIO(resp.read()), mode='r:gz')
schema = json.load(tar.extractfile('traefik/values.schema.json'))

with open('$REPO_ROOT/K8s/infrastructure/traefik/helmrelease.yaml') as f:
    hr = yaml.safe_load(f)

jsonschema.validate(instance=hr['spec']['values'], schema=schema)
print('✔ Traefik HelmRelease values match schema OK')
"

echo "=================================================================="
echo "✔ All validations passed successfully!"
echo "=================================================================="

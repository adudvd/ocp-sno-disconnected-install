#!/usr/bin/env bash
# Day-2 configuration for the disconnected SNO cluster.
set -euo pipefail
source "$(dirname "$0")/env.sh"
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CR="${MIRROR_WORKSPACE}/working-dir/cluster-resources"

oc get nodes -o wide
oc get clusterversion

# 1. Disable internet catalogs
oc apply -f "${REPO_DIR}/manifests/06-operatorhub-disable-defaults.yaml"

# 2. Apply everything oc-mirror v2 generated (IDMS, ITMS, CatalogSource,
#    ClusterCatalog, signature ConfigMaps, UpdateService)
oc apply -f "${CR}/"

# 3. Trust the registry CA for image streams / builds
oc create configmap registry-ca -n openshift-config \
  --from-file="${REGISTRY_HOST}..${REGISTRY_PORT}=/etc/pki/ca-trust/source/anchors/mirror-registry-rootCA.pem" \
  --dry-run=client -o yaml | oc apply -f -
oc patch image.config.openshift.io/cluster --type merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"registry-ca"}}}'

# 4. Wait for MachineConfigPool to settle (IDMS changes roll out via MCO)
oc wait mcp/master --for=condition=Updated --timeout=30m

oc get catalogsource -n openshift-marketplace
oc get packagemanifests | head
oc get co

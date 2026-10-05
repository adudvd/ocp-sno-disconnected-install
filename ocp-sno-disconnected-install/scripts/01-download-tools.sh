#!/usr/bin/env bash
# Run on a CONNECTED RHEL 9 host. Downloads all binaries needed to carry into
# the disconnected network. Output: ./bundle/
set -euo pipefail
source "$(dirname "$0")/env.sh"

BASE="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OCP_VERSION}"
# Also downloadable from the OpenShift console "Downloads" page.
MR="https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest"
OUT="./bundle"
mkdir -p "${OUT}"

curl -fL -o "${OUT}/openshift-client-linux.tar.gz"  "${BASE}/openshift-client-linux-amd64-rhel9-${OCP_VERSION}.tar.gz" \
  || curl -fL -o "${OUT}/openshift-client-linux.tar.gz" "${BASE}/openshift-client-linux.tar.gz"
curl -fL -o "${OUT}/openshift-install-linux.tar.gz" "${BASE}/openshift-install-linux.tar.gz"
curl -fL -o "${OUT}/oc-mirror.rhel9.tar.gz"         "${BASE}/oc-mirror.rhel9.tar.gz"
curl -fL -o "${OUT}/mirror-registry-amd64.tar.gz"   "${MR}/mirror-registry-amd64.tar.gz"
curl -fL -o "${OUT}/sha256sum.txt"                  "${BASE}/sha256sum.txt"

( cd "${OUT}" && grep -E 'openshift-(client|install)-linux|oc-mirror.rhel9' sha256sum.txt | sha256sum -c --ignore-missing ) || true

echo "Downloaded to ${OUT}:"; ls -lh "${OUT}"

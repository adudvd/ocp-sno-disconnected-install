#!/usr/bin/env bash
# Run on the DISCONNECTED bastion as root (or a sudo user).
# Installs "mirror registry for Red Hat OpenShift" (a single-node Quay).
set -euo pipefail
source "$(dirname "$0")/env.sh"

: "${QUAY_INIT_PASSWORD:?export QUAY_INIT_PASSWORD (min 8 chars) before running}"

sudo mkdir -p "${QUAY_ROOT}" "${QUAY_STORAGE}"
mkdir -p ./mirror-registry && tar -xzf ./bundle/mirror-registry-amd64.tar.gz -C ./mirror-registry
cd ./mirror-registry

sudo ./mirror-registry install \
  --quayHostname "${REGISTRY}" \
  --quayRoot "${QUAY_ROOT}" \
  --quayStorage "${QUAY_STORAGE}" \
  --initUser init \
  --initPassword "${QUAY_INIT_PASSWORD}"

# Open the registry port
sudo firewall-cmd --add-port="${REGISTRY_PORT}/tcp" --permanent && sudo firewall-cmd --reload || true

# Locate the generated root CA (path differs between mirror-registry releases:
# <quayRoot>/quay-config/rootCA.pem in current docs, <quayRoot>/quay-rootCA/rootCA.pem in older ones)
ROOT_CA=$(sudo find "${QUAY_ROOT}" -maxdepth 2 -name rootCA.pem | head -1)
echo "Root CA: ${ROOT_CA}"
sudo cp "${ROOT_CA}" ./mirror-registry-rootCA.pem && sudo chown "$(id -u):$(id -g)" ./mirror-registry-rootCA.pem

# Trust the generated root CA system-wide (needed by podman/oc-mirror/openshift-install)
sudo cp "${ROOT_CA}" /etc/pki/ca-trust/source/anchors/mirror-registry-rootCA.pem
sudo update-ca-trust extract

# Log in so credentials land in ${XDG_RUNTIME_DIR}/containers/auth.json
podman login -u init -p "${QUAY_INIT_PASSWORD}" "${REGISTRY}"
curl -fsS "https://${REGISTRY}/health/instance" && echo
echo "Mirror registry ready: https://${REGISTRY}  (user: init)"
echo "Root CA copied to ./mirror-registry/mirror-registry-rootCA.pem -> paste into install-config.yaml additionalTrustBundle"

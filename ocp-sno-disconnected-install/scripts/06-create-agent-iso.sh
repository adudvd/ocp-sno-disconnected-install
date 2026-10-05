#!/usr/bin/env bash
# Run on the DISCONNECTED bastion. Builds the bootable agent ISO for SNO.
set -euo pipefail
source "$(dirname "$0")/env.sh"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Use an openshift-install binary that matches the MIRRORED payload exactly.
# Extracting it from the mirror guarantees the ICSP/IDMS mapping is baked in.
RELEASE_DIGEST=$(oc adm release info "${REGISTRY}/openshift/release-images:${OCP_VERSION}-${ARCH}" -o jsonpath='{.digest}')
oc adm release extract --command=openshift-install --to "${REPO_DIR}/bin" \
  --idms-file="${MIRROR_WORKSPACE}/working-dir/cluster-resources/idms-oc-mirror.yaml" \
  "${REGISTRY}/openshift/release-images@${RELEASE_DIGEST}"
INSTALLER="${REPO_DIR}/bin/openshift-install"
"${INSTALLER}" version

mkdir -p "${INSTALL_DIR}"
cp "${REPO_DIR}/configs/install-config.yaml" "${INSTALL_DIR}/"
cp "${REPO_DIR}/configs/agent-config.yaml"   "${INSTALL_DIR}/"
# Keep backups: the installer consumes these files
cp "${INSTALL_DIR}/install-config.yaml" "${INSTALL_DIR}/install-config.yaml.bak"
cp "${INSTALL_DIR}/agent-config.yaml"   "${INSTALL_DIR}/agent-config.yaml.bak"

# Optional extra manifests applied at install time (e.g. disable default catalogs)
mkdir -p "${INSTALL_DIR}/openshift"
cp "${REPO_DIR}/manifests/06-operatorhub-disable-defaults.yaml" "${INSTALL_DIR}/openshift/"

"${INSTALLER}" agent create image --dir "${INSTALL_DIR}" --log-level info
ls -lh "${INSTALL_DIR}"/agent.*.iso
echo "Boot the SNO node from this ISO (virtual media / USB / VM CD-ROM)."

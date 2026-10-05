#!/usr/bin/env bash
# Run on the bastion after booting the node from the agent ISO.
set -euo pipefail
source "$(dirname "$0")/env.sh"
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/bin/openshift-install"
"${INSTALLER}" agent wait-for bootstrap-complete --dir "${INSTALL_DIR}" --log-level info
"${INSTALLER}" agent wait-for install-complete   --dir "${INSTALL_DIR}" --log-level info
echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig"

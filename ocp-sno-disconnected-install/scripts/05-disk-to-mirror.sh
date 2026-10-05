#!/usr/bin/env bash
# Run on the DISCONNECTED bastion after copying ${MIRROR_WORKSPACE} across.
set -euo pipefail
source "$(dirname "$0")/env.sh"
# Needs an auth.json containing the local registry login (03-install-mirror-registry.sh did podman login).
oc mirror -c "$(dirname "$0")/../configs/imageset-config.yaml" \
  --from "file://${MIRROR_WORKSPACE}" \
  "docker://${REGISTRY}" --v2

echo "Generated cluster resources:"
ls -1 "${MIRROR_WORKSPACE}/working-dir/cluster-resources/"

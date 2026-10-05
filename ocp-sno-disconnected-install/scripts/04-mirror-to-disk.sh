#!/usr/bin/env bash
# Run on the CONNECTED host. Produces mirror_000001.tar (+ more) in ${MIRROR_WORKSPACE}.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "${MIRROR_WORKSPACE}" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers"
# oc-mirror reads registry credentials from the containers auth file
cp "${RH_PULL_SECRET}" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json"

oc mirror -c "$(dirname "$0")/../configs/imageset-config.yaml" \
  "file://${MIRROR_WORKSPACE}" --v2

echo "Copy ${MIRROR_WORKSPACE} (the mirror_*.tar files and working-dir) to the disconnected bastion."

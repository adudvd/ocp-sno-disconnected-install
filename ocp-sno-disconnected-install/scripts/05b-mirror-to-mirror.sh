#!/usr/bin/env bash
# ALTERNATIVE to 04+05 when the bastion can reach both the internet and the
# local registry (partially disconnected). auth.json must contain BOTH the
# Red Hat pull secret and the local registry credentials.
set -euo pipefail
source "$(dirname "$0")/env.sh"
oc mirror -c "$(dirname "$0")/../configs/imageset-config.yaml" \
  --workspace "file://${MIRROR_WORKSPACE}" \
  "docker://${REGISTRY}" --v2

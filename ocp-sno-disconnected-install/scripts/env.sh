#!/usr/bin/env bash
# Shared settings for all scripts. Edit these values, then: source scripts/env.sh
export OCP_VERSION="4.22.11"
export OCP_CHANNEL="stable-4.22"
export ARCH="x86_64"                       # x86_64 | aarch64

export REGISTRY_HOST="registry.example.lab" # FQDN of the bastion running mirror-registry
export REGISTRY_PORT="8443"
export REGISTRY="${REGISTRY_HOST}:${REGISTRY_PORT}"
export QUAY_ROOT="/opt/quay"                # mirror-registry install/config dir
export QUAY_STORAGE="/opt/quay/storage"     # image blob storage (needs 500 GB+)

export MIRROR_WORKSPACE="/data/oc-mirror"   # oc-mirror v2 workspace / archive dir
export INSTALL_DIR="${HOME}/sno-install"    # openshift-install asset dir
export BIN_DIR="/usr/local/bin"

# Red Hat pull secret (download from console.redhat.com/openshift/install/pull-secret).
# Only needed on the CONNECTED side for mirror-to-disk. Never commit it.
export RH_PULL_SECRET="${HOME}/pull-secret.json"

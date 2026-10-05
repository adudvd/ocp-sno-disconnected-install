#!/usr/bin/env bash
# Run on each host (connected and disconnected bastion) with the ./bundle dir.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd ./bundle
sudo tar -xzf openshift-client-linux.tar.gz -C "${BIN_DIR}" oc kubectl
sudo tar -xzf openshift-install-linux.tar.gz -C "${BIN_DIR}" openshift-install
sudo tar -xzf oc-mirror.rhel9.tar.gz -C "${BIN_DIR}" oc-mirror
sudo chmod +x "${BIN_DIR}"/{oc,kubectl,openshift-install,oc-mirror}
sudo dnf install -y podman nmstate jq bind-utils httpd-tools
oc version --client
openshift-install version
oc mirror --v2 --help >/dev/null && echo "oc-mirror v2 OK"

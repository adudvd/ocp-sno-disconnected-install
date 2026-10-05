# OpenShift 4.22.11 Single Node (SNO): Disconnected Install

Everything needed to install a **single-node OpenShift Container Platform 4.22.11** cluster in an air-gapped network, using the **mirror registry for Red Hat OpenShift**, **oc-mirror v2** and the **Agent-based Installer**.

**Full step-by-step guide: [docs/INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md)**

## Repository layout

```
.
├── docs/INSTALL-GUIDE.md          # complete procedure
├── configs/
│   ├── imageset-config.yaml       # oc-mirror v2: OCP 4.22.11 + operators
│   ├── install-config.yaml        # SNO, disconnected mirror, trust bundle
│   └── agent-config.yaml          # node, static IP (NMState), root disk
├── manifests/                     # IDMS, ITMS, CatalogSource, ClusterCatalog,
│                                  # OperatorHub, registry CA, image config, LVMS
├── scripts/                       # 01..08 automation + env.sh
└── dns/                           # BIND zones and dnsmasq example
```

## Quick start

```bash
# Connected host
vi scripts/env.sh
./scripts/01-download-tools.sh && ./scripts/02-install-tools.sh
./scripts/04-mirror-to-disk.sh                # needs your Red Hat pull secret
# carry the repo, ./bundle and /data/oc-mirror into the disconnected network

# Disconnected bastion
./scripts/02-install-tools.sh
QUAY_INIT_PASSWORD='<password>' ./scripts/03-install-mirror-registry.sh
./scripts/05-disk-to-mirror.sh
vi configs/install-config.yaml configs/agent-config.yaml
./scripts/06-create-agent-iso.sh              # -> ~/sno-install/agent.x86_64.iso
# boot the node from the ISO
./scripts/07-monitor-install.sh
./scripts/08-post-install.sh
```

## Minimum SNO node

8 vCPU, 16 GB RAM, 120 GB disk (plus an optional empty disk for LVM storage).

## Security

This repository contains **placeholders only**. Never commit pull secrets, registry passwords, kubeconfig files, SSH private keys or `auth/` directories. The `.gitignore` blocks the common ones.

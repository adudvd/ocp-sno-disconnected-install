# Installing OpenShift 4.22.11 Single Node (SNO) in a Disconnected Environment

This guide installs a **single-node OpenShift Container Platform 4.22.11** cluster on a network with no internet access, using:

- **mirror registry for Red Hat OpenShift** (a small Quay instance) as the local registry,
- **oc-mirror plugin v2** to copy the release payload and operators,
- the **Agent-based Installer** to build a bootable ISO for the node.

All files referenced here live in this repository. Values such as `registry.example.lab`, `sno`, `192.168.10.20` are examples; change them in `scripts/env.sh`, `configs/*.yaml` and `dns/*`.

---

## Contents

1. [Architecture](#1-architecture)
2. [Requirements](#2-requirements)
3. [Network and DNS](#3-network-and-dns)
4. [Prepare tools (connected side)](#4-prepare-tools-connected-side)
5. [Install the mirror registry (disconnected side)](#5-install-the-mirror-registry)
6. [Mirror OpenShift 4.22.11 with oc-mirror v2](#6-mirror-openshift-42211-with-oc-mirror-v2)
7. [Prepare install-config.yaml and agent-config.yaml](#7-prepare-the-install-configuration)
8. [Build the agent ISO and install](#8-build-the-agent-iso-and-install)
9. [Post-install (day 2) configuration](#9-post-install-configuration)
10. [Updating the cluster later](#10-updating-the-cluster-later)
11. [Troubleshooting](#11-troubleshooting)
12. [File reference](#12-file-reference)

---

## 1. Architecture

```
          CONNECTED ZONE                    |              DISCONNECTED ZONE
                                            |
  +-------------------------+   USB / DVD   |   +----------------------------------+
  | Connected RHEL 9 host   |  ===========> |   | Bastion (RHEL 9)                 |
  | - oc, oc-mirror         |  mirror_*.tar |   | - mirror-registry (Quay) :8443   |
  | - Red Hat pull secret   |  + binaries   |   | - oc, oc-mirror, openshift-install|
  +-------------------------+               |   | - DNS (optional), NTP (optional) |
                                            |   +----------------+-----------------+
                                            |                    | 192.168.10.0/24
                                            |   +----------------v-----------------+
                                            |   | SNO node  sno-node01             |
                                            |   | 192.168.10.20  (boots agent ISO) |
                                            |   +----------------------------------+
```

Two mirroring workflows are supported:

| Workflow | When to use | Scripts |
|---|---|---|
| **Fully disconnected** (mirror-to-disk, then disk-to-mirror) | Air gap; data carried on removable media | `04-mirror-to-disk.sh` then `05-disk-to-mirror.sh` |
| **Partially disconnected** (mirror-to-mirror) | Bastion can reach internet **and** local registry | `05b-mirror-to-mirror.sh` |

---

## 2. Requirements

### 2.1 SNO node (minimum for 4.22)

| Resource | Minimum | Recommended |
|---|---|---|
| vCPU | 8 | 16+ |
| RAM | 16 GB | 32 GB+ |
| Install disk | 120 GB | 200 GB+ SSD/NVMe |
| Extra disk (optional, for LVMS storage) | - | 100 GB+ empty disk |
| NIC | 1 | 1 (static IP or DHCP reservation) |

Bare metal or VM (KVM/libvirt, vSphere, etc.). Firmware must be able to boot an ISO (BMC virtual media, USB, or VM CD-ROM).

### 2.2 Bastion / mirror registry host

- RHEL 8 or 9 (RHEL 9 recommended), with `podman` 3.4.2+ and OpenSSL
- 2+ vCPU, 8 GB RAM
- Disk: about 12 GB for the release payload only; 350 GB+ with operators; up to 1 TB suggested. The mirror archive (`mirror_*.tar`) needs the same space again.
- A **resolvable FQDN** (for example `registry.example.lab`)
- Port **8443/tcp** open to the SNO node

### 2.3 Connected host

- RHEL 9, internet access to `quay.io`, `registry.redhat.io`, `mirror.openshift.com`, `api.openshift.com`
- Red Hat **pull secret** from <https://console.redhat.com/openshift/install/pull-secret>
- Enough disk for the archive (same as above)

### 2.4 Software versions

| Component | Version |
|---|---|
| OpenShift Container Platform | **4.22.11** (channel `stable-4.22`) |
| oc / openshift-install | 4.22.11 |
| oc-mirror | 4.22.x, used with `--v2` |
| mirror registry for Red Hat OpenShift | latest 2.x |
| Operator catalog | `registry.redhat.io/redhat/redhat-operator-index:v4.22` |

---

## 3. Network and DNS

SNO needs these DNS records, all pointing to the node IP:

| Record | Type | Value |
|---|---|---|
| `api.sno.example.lab` | A | 192.168.10.20 |
| `api-int.sno.example.lab` | A | 192.168.10.20 |
| `*.apps.sno.example.lab` | A | 192.168.10.20 |
| `sno-node01.example.lab` | A + PTR | 192.168.10.20 |
| `registry.example.lab` | A + PTR | 192.168.10.10 |

Ready-made examples: `dns/example.lab.zone`, `dns/10.168.192.in-addr.arpa.zone` (BIND) and `dns/dnsmasq-sno.conf` (dnsmasq).

Verify from the bastion:

```bash
for n in api api-int test.apps; do dig +short $n.sno.example.lab; done
dig +short registry.example.lab
dig +short -x 192.168.10.20
```

Ports the node must reach on the bastion: **8443** (registry), **53** (DNS), **123/udp** (NTP if used).
Ports the bastion must reach on the node: **6443** (API), **443/80** (console/routes), **22** (SSH for debugging).

Time sync matters: a clock skew of more than a few seconds breaks certificate validation. Point `additionalNTPSources` in `agent-config.yaml` at a local NTP server.

---

## 4. Prepare tools (connected side)

```bash
git clone https://github.com/adudvd/ocp-sno-disconnected-install.git
cd ocp-sno-disconnected-install
vi scripts/env.sh                     # set version, registry host, paths

./scripts/01-download-tools.sh        # downloads into ./bundle
./scripts/02-install-tools.sh         # installs oc, kubectl, openshift-install, oc-mirror
```

Files downloaded (from `mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.22.11/`):

- `openshift-client-linux-amd64-rhel9-4.22.11.tar.gz` (`oc`, `kubectl`). The script falls back to `openshift-client-linux.tar.gz` if that name is absent.
- `openshift-install-linux.tar.gz`
- `oc-mirror.rhel9.tar.gz`
- `mirror-registry-amd64.tar.gz` (also on the OpenShift console **Downloads** page)

Copy the whole repository folder, including `./bundle`, to the disconnected bastion.

---

## 5. Install the mirror registry

On the **disconnected bastion**:

```bash
cd ocp-sno-disconnected-install
./scripts/02-install-tools.sh
export QUAY_INIT_PASSWORD='<choose-a-strong-password>'   # 8+ chars, no spaces
./scripts/03-install-mirror-registry.sh
```

What the script runs:

```bash
sudo ./mirror-registry install \
  --quayHostname registry.example.lab:8443 \
  --quayRoot /opt/quay \
  --quayStorage /opt/quay/storage \
  --initUser init \
  --initPassword "$QUAY_INIT_PASSWORD"
```

It then trusts the generated root CA system-wide and logs in with `podman login`, which writes the credentials to `${XDG_RUNTIME_DIR}/containers/auth.json`. oc-mirror reads that file.

Check it:

```bash
curl -s https://registry.example.lab:8443/health/instance
podman login registry.example.lab:8443
```

Web UI: `https://registry.example.lab:8443` (user `init`).

> Tip: Use your own certificate signed by the corporate CA with `--sslCert` / `--sslKey`; then put that CA in `additionalTrustBundle` instead.

---

## 6. Mirror OpenShift 4.22.11 with oc-mirror v2

The image set is defined in [`configs/imageset-config.yaml`](../configs/imageset-config.yaml):

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    architectures: [amd64]
    channels:
      - name: stable-4.22
        type: ocp
        minVersion: 4.22.11
        maxVersion: 4.22.11
    graph: true
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.22
      packages:
        - name: lvms-operator
        - name: local-storage-operator
        - ...
  additionalImages:
    - name: registry.redhat.io/ubi9/ubi:latest
```

Pinning `minVersion` and `maxVersion` to 4.22.11 mirrors only that release (about 12 to 20 GB). Add or remove operator packages as you need; each one adds to the download.

### 6.1 Fully disconnected: mirror-to-disk then disk-to-mirror

**Connected host:**

```bash
cp ~/pull-secret.json ${XDG_RUNTIME_DIR}/containers/auth.json
oc mirror -c configs/imageset-config.yaml file:///data/oc-mirror --v2
# or: ./scripts/04-mirror-to-disk.sh
```

Carry `/data/oc-mirror` (it contains `mirror_000001.tar` and the `working-dir`) to the bastion, at the same path.

**Disconnected bastion:**

```bash
oc mirror -c configs/imageset-config.yaml \
  --from file:///data/oc-mirror \
  docker://registry.example.lab:8443 --v2
# or: ./scripts/05-disk-to-mirror.sh
```

### 6.2 Partially disconnected: mirror-to-mirror

Merge the Red Hat pull secret and the local registry credentials into one `auth.json`, then:

```bash
oc mirror -c configs/imageset-config.yaml \
  --workspace file:///data/oc-mirror \
  docker://registry.example.lab:8443 --v2
```

### 6.3 Output

oc-mirror v2 writes cluster resources to `/data/oc-mirror/working-dir/cluster-resources/`:

| File | Purpose |
|---|---|
| `idms-oc-mirror.yaml` | `ImageDigestMirrorSet`: redirects digest pulls to the mirror |
| `itms-oc-mirror.yaml` | `ImageTagMirrorSet`: redirects tag pulls |
| `cs-redhat-operator-index-v4-22.yaml` | `CatalogSource` for OLM (classic) |
| `cc-redhat-operator-index-v4-22.yaml` | `ClusterCatalog` for OLM v1 |
| `signature-configmap.json/.yaml` | Release signatures for verification |
| `updateService.yaml` | `UpdateService` (because `graph: true`) |

Reference copies of these resources are in [`manifests/`](../manifests). **Always prefer the generated files**, since they list exactly the repositories you mirrored.

> oc-mirror v2 does not generate `ImageContentSourcePolicy`. In 4.22, IDMS/ITMS are the supported mirror resources.

---

## 7. Prepare the install configuration

### 7.1 install-config.yaml

Edit [`configs/install-config.yaml`](../configs/install-config.yaml). The SNO-specific and disconnected-specific parts:

```yaml
controlPlane:
  replicas: 1          # single node
compute:
  - name: worker
    replicas: 0
platform:
  none: {}
pullSecret: '{"auths":{"registry.example.lab:8443":{"auth":"<base64 user:password>"}}}'
additionalTrustBundlePolicy: Always
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  ...mirror registry root CA...
  -----END CERTIFICATE-----
imageDigestSources:
  - mirrors: [registry.example.lab:8443/openshift/release]
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  - mirrors: [registry.example.lab:8443/openshift/release-images]
    source: quay.io/openshift-release-dev/ocp-release
```

How to fill each value:

| Field | How to get it |
|---|---|
| `pullSecret` | `echo -n 'init:<password>' \| base64 -w0`. Only the **local** registry is needed. |
| `sshKey` | `cat ~/.ssh/id_ed25519.pub` (create with `ssh-keygen -t ed25519`) |
| `additionalTrustBundle` | Content of `mirror-registry/mirror-registry-rootCA.pem`, indented 2 spaces |
| `imageDigestSources` | The `imageDigestMirrors` entries from `idms-oc-mirror.yaml` for the release (operators are added after install) |
| `machineNetwork` | The subnet of the node IP |

Helper to indent the CA:

```bash
sed 's/^/  /' mirror-registry/mirror-registry-rootCA.pem
```

### 7.2 agent-config.yaml

Edit [`configs/agent-config.yaml`](../configs/agent-config.yaml):

- `rendezvousIP`: the node IP (for SNO the node is its own rendezvous host).
- `hosts[0].interfaces[].macAddress`: the real MAC of the node NIC.
- `rootDeviceHints`: the install disk (`/dev/sda`, `/dev/nvme0n1`, `/dev/vda`, or a `wwn`/`serialNumber`).
- `networkConfig`: NMState for a static IP; delete it to use DHCP.

Static networking needs `nmstatectl` on the bastion (`dnf install -y nmstate`), because the installer validates the NMState config.

---

## 8. Build the agent ISO and install

```bash
./scripts/06-create-agent-iso.sh
```

The script:

1. Extracts an `openshift-install` binary from the **mirrored** 4.22.11 payload (so the binary and payload match exactly):
   ```bash
   oc adm release extract --command=openshift-install --to ./bin \
     --idms-file=/data/oc-mirror/working-dir/cluster-resources/idms-oc-mirror.yaml \
     registry.example.lab:8443/openshift/release-images@<digest>
   ```
2. Copies `install-config.yaml` and `agent-config.yaml` into `~/sno-install` and keeps `.bak` copies, because the installer **deletes** them when it runs.
3. Adds `06-operatorhub-disable-defaults.yaml` as an extra manifest under `~/sno-install/openshift/`.
4. Runs `openshift-install agent create image --dir ~/sno-install`.

The result is `~/sno-install/agent.x86_64.iso`. In a disconnected network the installer takes the RHCOS base image from the mirrored release payload, so no internet access is needed.

Boot the node from the ISO (BMC virtual media, USB with `dd`, or a VM CD-ROM). Then watch the install:

```bash
./scripts/07-monitor-install.sh
# = openshift-install agent wait-for bootstrap-complete --dir ~/sno-install
#   openshift-install agent wait-for install-complete   --dir ~/sno-install
```

The node reboots once or twice. A typical install takes 45 to 90 minutes. When it finishes:

```bash
export KUBECONFIG=~/sno-install/auth/kubeconfig
oc get nodes
oc get clusterversion
cat ~/sno-install/auth/kubeadmin-password
# Console: https://console-openshift-console.apps.sno.example.lab
```

---

## 9. Post-install configuration

```bash
./scripts/08-post-install.sh
```

It does the following:

1. **Disables the default internet catalogs** (`manifests/06-operatorhub-disable-defaults.yaml`).
2. **Applies every resource oc-mirror generated** (`oc apply -f /data/oc-mirror/working-dir/cluster-resources/`): IDMS/ITMS for operator images, CatalogSource, ClusterCatalog, signature ConfigMaps, UpdateService.
3. **Trusts the registry CA for image streams and builds**: creates ConfigMap `registry-ca` in `openshift-config` with key `registry.example.lab..8443` (two dots before the port) and sets `image.config.openshift.io/cluster` `spec.additionalTrustedCA` (see `manifests/07` and `manifests/08`).
4. Waits for the `master` MachineConfigPool to finish rolling out the mirror config. On SNO this **reboots the node**.

Optional: persistent storage with LVMS (`manifests/09-lvms-storage.yaml`). It needs an empty second disk.

```bash
oc apply -f manifests/09-lvms-storage.yaml     # apply twice: the LVMCluster CRD appears after the operator installs
oc get storageclass
```

Optional: use the mirror registry's credentials for every pull by updating the global pull secret:

```bash
oc get secret/pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > ps.json
# edit ps.json to add or replace the registry entry, then:
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=ps.json
```

---

## 10. Updating the cluster later

1. On the connected side, raise `maxVersion` in `imageset-config.yaml` (for example 4.22.16) and run mirror-to-disk again. oc-mirror v2 uses its cache, so only new images are downloaded.
2. Carry the new archive across and run disk-to-mirror.
3. Apply the new `cluster-resources` (IDMS and signature ConfigMaps).
4. Update with the release digest:
   ```bash
   oc adm upgrade --allow-explicit-upgrade \
     --to-image registry.example.lab:8443/openshift/release-images@sha256:<digest>
   ```
   or point the cluster at the local OpenShift Update Service if you deployed it (`updateService.yaml`).

---

## 11. Troubleshooting

| Symptom | Check |
|---|---|
| `x509: certificate signed by unknown authority` | `additionalTrustBundle` is missing or not indented; the CA is not in `/etc/pki/ca-trust` on the bastion |
| ISO build fails on `networkConfig` | `nmstatectl` not installed on the bastion; YAML indentation in `agent-config.yaml` |
| Node boots but install does not start | SSH to `core@<node-ip>` and run `sudo journalctl -u agent.service -u assisted-service -f`; check DNS and that `rendezvousIP` equals the node IP |
| `ImagePullBackOff` for release images | `imageDigestSources` does not match the paths in `idms-oc-mirror.yaml`; registry unreachable on 8443 |
| Operators not visible in OperatorHub | Cluster resources from oc-mirror not applied; `oc get catalogsource -n openshift-marketplace`; pod logs in `openshift-marketplace` |
| Clock or certificate errors | NTP not reachable; set `additionalNTPSources` |
| Need logs from a failed install | `openshift-install agent gather bootstrap --dir ~/sno-install` (or from the node: `sudo /usr/local/bin/agent-gather -O > agent-gather.tar.xz`) |

Useful commands on the node during install:

```bash
ssh core@192.168.10.20
sudo journalctl -b -f
sudo crictl ps -a
sudo podman ps -a
```

---

## 12. File reference

| Path | Purpose |
|---|---|
| `configs/imageset-config.yaml` | oc-mirror v2 image set (OCP 4.22.11 + operators) |
| `configs/install-config.yaml` | SNO install config for a disconnected mirror |
| `configs/agent-config.yaml` | Agent-based installer host and network config |
| `manifests/01-idms-release.yaml` | IDMS for the release payload (reference) |
| `manifests/02-idms-operators.yaml` | IDMS for operator images (reference) |
| `manifests/03-itms-generic.yaml` | ITMS for tag-based images (reference) |
| `manifests/04-catalogsource-redhat-operators.yaml` | CatalogSource for the mirrored index |
| `manifests/05-clustercatalog-redhat-operators.yaml` | OLM v1 ClusterCatalog for the mirrored index |
| `manifests/06-operatorhub-disable-defaults.yaml` | Disables internet catalogs |
| `manifests/07-registry-ca-configmap.yaml` | Registry CA for image streams and builds |
| `manifests/08-image-config.yaml` | Cluster image config (trusted CA, allowed registries) |
| `manifests/09-lvms-storage.yaml` | Optional LVM storage for SNO |
| `scripts/env.sh` | Shared variables |
| `scripts/01..08-*.sh` | Step-by-step automation |
| `dns/*` | BIND and dnsmasq examples |

### Red Hat documentation (4.22)

- Disconnected environments, oc-mirror v2: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/disconnected_environments/about-installing-oc-mirror-v2>
- Creating a mirror registry with mirror registry for Red Hat OpenShift: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/disconnected_environments/installing-mirroring-creating-registry>
- Installing an on-premise cluster with the Agent-based Installer: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_an_on-premise_cluster_with_the_agent-based_installer/>
- Release notes 4.22: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/release_notes/ocp-4-22-release-notes>

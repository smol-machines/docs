---
title: Self-hosting smolvm
---

# Self-hosting smolvm

You can install smolvm on your own servers and operate local machines on each host. Standalone smolvm provides the engine, CLI, local state, and `smolvm serve` HTTP API.

It does not include a production fleet control plane. Scheduling across hosts, placement, failover, tenant management, global inventory, billing, and managed durability remain operator responsibilities.

Use smol cloud when you want smol machines to operate that layer.

## Host requirements

### Linux

Linux is the usual server host:

- x86_64 or aarch64 host and matching Linux guest architecture
- Hardware virtualization enabled in firmware and exposed to the operating system
- KVM available at `/dev/kvm`
- Enough CPU, memory, and disk for the machines and packed artifacts
- Network access to OCI and `.smolmachine` registries when pulls are required

The invoking service account needs permission to access `/dev/kvm` and the runtime's state directories. Keep that account separate from untrusted host users.

### Other supported hosts

macOS uses Hypervisor.framework and is suitable for local workstations. Native Windows x86_64 uses Windows Hypervisor Platform. Windows does not currently support VM branching, checkpoints, or GPU acceleration, so verify feature requirements before choosing it for a self-hosted node.

Guest and artifact architecture must match the host architecture.

## Install and verify a node

```bash
curl -sSL https://smolmachines.com/install.sh | bash
smolvm --version
smolvm machine run --net --image alpine -- uname -a
```

The final command needs `--net` so the in-guest image pull can reach the registry, even though the workload itself needs no egress.

For production installation, pin a tested release and verify its published SHA-256 checksum. Release archives are not currently signed or accompanied by provenance attestations.

## Per-host API

Start the local API on loopback:

```bash
smolvm serve start --listen 127.0.0.1:8080
```

The API has no authentication. Keep it on loopback or a protected Unix socket. If a remote controller must connect, add authenticated TLS, strict network policy, and host-level access controls in front of it.

See [Local API and smolvm serve](/docs/local/local-api-smolvm-serve) for the endpoint summary.

## What an operator must add

A multi-host deployment normally needs systems outside standalone smolvm for:

- Node registration and health
- Workload placement and admission control
- Authenticated API access and authorization
- Durable machine inventory and desired state
- Retries, failover, draining, and upgrades
- Image and pack distribution
- Network address management, ingress, and egress policy
- Durable volumes, backup, and restore
- Metrics, logs, alerting, and capacity planning
- Tenant and host-user isolation

Do not treat multiple exposed `smolvm serve` processes as a complete fleet architecture.

## Security model

The CLI and VMM run with the permissions of the invoking host user. The host OS, hypervisor, libkrun, smolvm, and that account are part of the trusted computing base.

Review every capability passed into a guest:

- Host directory mounts expose those directories to the workload
- SSH-agent forwarding lets the guest request signatures while connected
- Networking, published ports, and forwarded sockets expand reachability
- Secret injection places plaintext in the guest process environment

Use separate host service accounts or stronger OS confinement for hostile co-tenants. Do not mount the container runtime socket, host credentials, or sensitive host paths into untrusted machines.

## State, packing, and recovery

Persistent named machines keep disk changes across stop/start on the same host. A `.smolmachine` can capture stopped disk state for reuse on a compatible host.

Packing does not preserve live RAM or running processes. Standalone smolvm does not provide live migration between hosts or a general portable checkpoint/restore service. Build backup and recovery around stopped disk artifacts and any external durable storage your workload uses.

### An isolated data root

`SMOLVM_DATA_DIR` puts every piece of smolvm state under one directory: machine directories, the
agent rootfs, the disk templates and the server database. It works by pointing `HOME` at that
root before any path is computed, so everything derived from the home directory follows it. That
is what lets a node run machines under a system-owned root rather than an operator's home.

```bash
SMOLVM_DATA_DIR=/var/lib/smolvm smolvm machine ls
```

The agent rootfs is the one piece that may not follow. smolvm looks for it in `SMOLVM_AGENT_ROOTFS`
first, then beside the `smolvm` binary, and only then under the data directory that this variable
moves. The release tarball sets that variable and ships the rootfs next to the binary, so a tarball
install is unaffected. An install that relies on the data-directory copy is not: point
`SMOLVM_AGENT_ROOTFS` at the rootfs, or copy it into the new root. A machine that cannot find it
fails to start with `could not find agent rootfs at <path>; set SMOLVM_AGENT_ROOTFS or reinstall`.

`SMOLVM_DATA_DIR` is read on Linux only. On macOS it is ignored and state stays where the
installer put it.

Test host failure, node replacement, and version upgrades before using a self-hosted deployment for production workloads.

smol machines can provide custom managed solutions to customers with special needs.

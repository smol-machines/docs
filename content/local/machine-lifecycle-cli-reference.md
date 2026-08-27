---
title: Machine Lifecycle and CLI Reference
---

# Machine Lifecycle and CLI Reference

The `smolvm` CLI has two local lifecycle modes: ephemeral runs and persistent named machines. Commands remain nested under `smolvm machine`.

There is no `smolvm run` or `smolvm build` command.

## Ephemeral machines

`machine run` creates a VM, runs the guest command, and cleans up the VM when the command exits:

```bash
smolvm machine run --net --image alpine -- echo hello
```

Filesystem changes do not carry into the next run. Use this mode for one-off jobs, tests, and untrusted commands.

Networking is off by default; `--net` above lets the in-guest image pull reach
the registry, and a machine whose image is already cached can run without it.
Beyond the pull, enable networking only when the workload needs network access:

```bash
smolvm machine run \
  --net \
  --image alpine \
  --allow-host registry.npmjs.org \
  -- wget -q -O /dev/null https://registry.npmjs.org
```

`--allow-host` limits egress to the named host. Add multiple flags when the workload needs multiple hosts.

## Persistent machines

A persistent machine separates creation from execution:

```bash
smolvm machine create --name dev --image alpine --net
smolvm machine start --name dev
smolvm machine exec --name dev -- apk add python3
smolvm machine stop --name dev
smolvm machine start --name dev
smolvm machine exec --name dev -- python3 --version
```

Package installs, file writes, and configuration changes made through `machine exec` survive stop/start cycles. `machine stop` preserves disk state. `machine delete` removes the named machine.

## Core lifecycle commands

| Goal | Command |
|---|---|
| Run an ephemeral command | `smolvm machine run --image IMAGE -- COMMAND` |
| Create a persistent machine | `smolvm machine create --name NAME --image IMAGE` |
| Start a machine | `smolvm machine start --name NAME` |
| Execute a command | `smolvm machine exec --name NAME -- COMMAND` |
| Open a persistent shell | `smolvm machine shell --name NAME` |
| Stop without deleting state | `smolvm machine stop --name NAME` |
| Delete a machine | `smolvm machine delete --name NAME` |
| Check one machine | `smolvm machine status --name NAME` |
| List machines | `smolvm machine ls` |

If `--name` is omitted on commands that accept it, the default machine name is `default`.

## Selected management commands

### Stream command output

```bash
smolvm machine exec --stream --name dev -- python3 train.py
```

### Copy files

Use `machine:path` for the VM side:

```bash
smolvm machine cp ./script.py dev:/workspace/script.py
smolvm machine exec --name dev -- python3 /workspace/script.py
smolvm machine cp dev:/workspace/result.json ./result.json
```

`/workspace` persists across `exec` sessions and stop/start cycles. For files larger than the copy limit, mount a directory with `--volume`.

### Update a stopped machine

```bash
smolvm machine stop --name dev
smolvm machine update --name dev --cpus 6 --mem 12288
smolvm machine start --name dev
```

`machine update` changes configuration for the next start. The machine must be stopped first.

### Mount a host directory

```bash
smolvm machine run \
  --image python:3.12-alpine \
  --volume "$PWD:/app" \
  -- python3 /app/main.py
```

A mounted host directory is deliberately visible to the guest. Do not mount sensitive host paths into untrusted workloads.

## Common resource flags

| Flag | Meaning |
|---|---|
| `--image`, `-I` | OCI image, local image archive, stdin archive (`-`), or unpacked rootfs |
| `--name`, `-n` | Machine name |
| `--net` | Enable networking |
| `--allow-host` | Allow egress to a hostname |
| `--allow-cidr` | Allow egress to a CIDR |
| `--cpus` | vCPU count |
| `--mem` | Guest memory in MiB |
| `--volume`, `-v` | Mount `HOST_DIR:GUEST_DIR` |
| `--port`, `-p` | Forward `HOST_PORT:GUEST_PORT` |
| `--interactive`, `-i` | Keep stdin open |
| `--tty`, `-t` | Allocate a TTY |
| `--smolfile`, `-s` | Read configuration from a Smolfile |

Defaults are 4 vCPUs, 8192 MiB of guest memory, 20 GiB of storage, and a 2 GiB overlay. Memory is elastic: the host commits and reclaims memory according to guest use.

Run `smolvm machine COMMAND --help` against your installed version for the complete flag set.

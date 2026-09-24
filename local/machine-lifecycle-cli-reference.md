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
the registry. On the default backend the guest has no visible network interface and `ping` does
not work, even though TCP and UDP do — see [how networking behaves inside a
machine](#how-networking-behaves-inside-a-machine). An ephemeral run pulls every time unless you add `--oci-cache`,
which keeps the image on the host for later runs to start from without a pull.
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
| List machine names only | `smolvm machine ls --quiet` |
| Checkpoint a running machine | `smolvm machine checkpoint --name NAME -o PATH` |

If `--name` is omitted on commands that accept it, the default machine name is `default`.

## Selected management commands

### Stream command output

```bash
smolvm machine exec --stream --name dev -- python3 train.py
```

### List machines for a script

`machine ls` prints machine names in full; long names are not truncated. For
scripting, `--quiet` prints one name per line and nothing else, in the same
shape as `docker ps -q`:

```bash
smolvm machine ls --quiet | xargs -I{} smolvm machine stop --name {}
```

`--json` gives the full records when a script needs more than the name.

### Publish a port or a range of ports

`--port` takes a single port, a `HOST:GUEST` pair, or a range on either side:

```bash
smolvm machine run --net -p 8080 --image nginx -- nginx -g "daemon off;"
smolvm machine run --net -p 18080:80 --image nginx -- nginx -g "daemon off;"
smolvm machine run --net -p 3000-3009:3000-3009 --image node:22-alpine -- node server.js
```

A bare port or range uses the same numbers on both sides. Ranges map one to one, so the host and guest sides must cover the same number of ports; `3000-3009:4000-4001` is rejected. A range start must not exceed its end, and port 0 is not valid.

Publishing a port selects the virtio-net backend for the machine, because the default outbound-only backend cannot accept inbound connections.

### Publish a Unix socket

`machine create` takes two socket flags, both repeatable. `--expose-socket` makes a socket the
guest listens on reachable from the host, and `--mount-socket` puts a host socket inside the
guest so a guest process can reach a host service:

```bash
smolvm machine create --name api --image alpine \
  --expose-socket /run/app.sock \
  --mount-socket /run/host-db.sock:/run/db.sock
```

`--expose-socket` takes `GUEST_PATH[:HOST_PATH]`. Without a host path the socket appears at
`<machine-dir>/<basename>`, which `smolvm machine data-dir --name api` prints.
`--mount-socket` takes `HOST_PATH:GUEST_PATH` and needs both.

Two behaviours are worth knowing before you write a client against an exposed socket.

**The host end accepts before the guest is listening.** smolvm creates the host listener when the
machine starts, so a connect succeeds whether or not anything in the guest has bound its end yet.
A client that treats a successful connect as readiness proceeds to send into a socket with no
reader. Retry on the first request and its reply, not on the connect.

**Teardown removes the default path and leaves a pinned one.** The default socket lives inside
the machine's own directory, so deleting the machine takes it with it. A host path you named
yourself sits outside that directory and stays after the machine is gone; remove it yourself
before you reuse the path.

### Run the workload as a chosen user

`--user` takes a name from the image or a numeric `uid[:gid]`, in the same form
as `docker run --user`, and overrides the image's `USER`:

```bash
smolvm machine run --net --user 1000:1000 --image python:3.12-alpine \
  --volume "$PWD:/app" -- python3 /app/main.py
```

It is accepted on `machine run`, `machine create`, and `machine exec`. On
`create` it becomes the machine's configured user, and `exec` defaults to that,
falling back to the image's `USER` when the machine has none. Passing `--user`
to `exec` overrides both for that command.

The common reason to set it is a mounted host directory: the guest writes as
whatever account the workload runs under, so matching the mount's owner keeps
the files editable on the host afterwards.

Init commands are the exception. They provision the machine, so they run as root
regardless of `--user` or the image's `USER`.

### Copy files

Use `machine:path` for the VM side:

```bash
smolvm machine cp ./script.py dev:/workspace/script.py
smolvm machine exec --name dev -- python3 /workspace/script.py
smolvm machine cp dev:/workspace/result.json ./result.json
```

`/workspace` persists across `exec` sessions and stop/start cycles. For files larger than the copy limit, mount a directory with `--volume`.

### Checkpoint and restore a running machine

`machine checkpoint` captures a running machine, guest RAM and processes included, into one portable `.smolcheckpoint` file. The machine keeps running.

The machine has to have been started branchable, because a checkpoint reads the same copy-on-write guest memory a branch does. Start it with `--branchable`, which the engine also accepts as `--forkable`:

```bash
smolvm machine start --name dev --branchable
```

Then capture it:

```bash
smolvm machine checkpoint --name dev -o ./dev.smolcheckpoint
```

Restore it through `machine create`, which accepts a checkpoint wherever it accepts a pack:

```bash
smolvm machine create --name dev-restored --from ./dev.smolcheckpoint
smolvm machine start --name dev-restored
```

The restored machine resumes from the captured instant instead of booting. Because a live checkpoint carries the topology it was captured with, `--from` on a checkpoint rejects flags that would change it, including `--cpus`, `--mem`, `--storage`, and `--overlay`. Use `--staging-dir` on the capture when the default location has too little room for the temporary assets.

See [Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots) for what a checkpoint preserves and where it can be restored.

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

### Mount an S3 bucket

The same flag mounts S3-compatible object storage when the source is an `s3://` URL. The full form is `SOURCE:GUEST_PATH[:ro]`, and the guest path must be absolute:

```bash
smolvm machine run --net \
  --image python:3.12-alpine \
  --env AWS_ACCESS_KEY_ID=... \
  --env AWS_SECRET_ACCESS_KEY=... \
  --volume "s3://my-bucket/prefix:/data:ro" \
  -- python3 -c "import os; print(os.listdir('/data'))"
```

The bucket is mounted by the machine's agent from inside the guest, so the image needs no S3 or FUSE tooling. Credentials are read from the machine's environment, and `AWS_ENDPOINT_URL` points at an S3-compatible service such as R2 or MinIO. A bucket with no credentials is read anonymously.

Remote volumes need egress to reach the bucket, so an ephemeral run without `--net` is rejected rather than started. `machine run` and `machine create` accept an `s3://` source; `machine update` and `pack run` do not.

### Run a hypervisor inside the machine

`--nested` exposes the host's virtualization extensions to the guest so it can run KVM, which is
what lets smolvm, QEMU or another hypervisor run inside the machine:

```bash
smolvm machine run --nested --net --image ubuntu:24.04 -- sh -c "ls -l /dev/kvm"
```

It is off by default, because nesting turns work the guest would do natively into vmexits and a
nested guest runs far slower.

The host has to be able to offer the extensions in the first place, and smolvm checks before the
VM boots rather than failing inside the guest. On Apple silicon that means an M3 or newer and
macOS 15 or later; on Linux it means nested KVM is enabled, through `kvm_intel.nested=1` or
`kvm_amd nested=1`. A host that cannot returns an error naming the check result.

Running a Docker daemon in a machine does not need this flag. Containers share the guest kernel,
so [Docker in a Machine](/docs/guides/docker-in-a-machine) works without it.

## Common resource flags

| Flag | Meaning |
|---|---|
| `--image`, `-I` | OCI image, local image archive, stdin archive (`-`), or unpacked rootfs |
| `--name`, `-n` | Machine name |
| `--net` | Enable networking |
| `--allow-host` | Allow egress to a hostname |
| `--allow-cidr` | Allow egress to a CIDR |
| `--credential` | Bind a credential as `NAME=ENV_VAR@HOST[,HOST]`: the guest gets a placeholder in `ENV_VAR`; the host substitutes the real value only on HTTPS requests to the listed hosts |
| `--cpus` | vCPU count |
| `--mem` | Guest memory in MiB |
| `--volume`, `-v` | Mount a host directory or an S3 bucket: `SOURCE:GUEST_PATH[:ro]` |
| `--port`, `-p` | Forward `HOST_PORT:GUEST_PORT` |
| `--user`, `-u` | Run the workload as a name or `uid[:gid]` |
| `--interactive`, `-i` | Keep stdin open |
| `--tty`, `-t` | Allocate a TTY |
| `--smolfile`, `-s` | Read configuration from a Smolfile |
| `--block-io` | Host block I/O engine, `sync` or `async` |
| `--net-backend` | Networking implementation, `tsi` (default) or `virtio-net` |

`--block-io` takes `sync`, which services one request at a time on the virtio block worker, or `async`, which submits queued raw-disk reads through a restricted Linux io_uring. `async` is worth reaching for when a workload is disk heavy on a Linux host. It is a Linux-only engine, and asking for it anywhere else does not quietly fall back: the machine refuses to start with `async block I/O is currently supported on Linux hosts only; use --block-io sync`. `machine run`, `machine create` and `smolvm pack run` all accept the flag.

Defaults are 4 vCPUs, 8192 MiB of guest memory, 20 GiB of storage, and a 10 GiB overlay. Memory is elastic: the host commits and reclaims memory according to guest use.

## How networking behaves inside a machine

Networking is off until you pass `--net`. What you get then depends on the backend, and the
default one behaves in a way that surprises people the first time they look inside a machine.

The default backend, `tsi`, carries the guest's TCP and UDP connections directly rather than
emulating a network card. Outbound connections work, port forwarding works, and DNS works. But
there is no virtual interface for the guest to show you:

```console
$ smolvm machine exec --name web -- ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
2: dummy0: <BROADCAST,UP,LOWER_UP> mtu 1500 ...
```

`lo` and `dummy0` are the whole list. There is no `eth0`, the guest holds no IP address of its
own, and `ip route` shows only a placeholder route. None of that means networking is broken.

**`ping` does not work on this backend, and its failure is misleading.** ICMP is not TCP or UDP,
so `tsi` does not carry it:

```console
$ smolvm machine exec --name web -- ping -c1 8.8.8.8
ping: sendto: Network unreachable
```

The machine reached the internet perfectly well a moment later:

```console
$ smolvm machine exec --name web -- wget -qO- https://example.com
<!doctype html><html lang="en">...
```

So check connectivity with something that speaks TCP — `wget`, `curl`, or your own client — and
treat a missing interface and a failing `ping` as expected rather than as symptoms.

### When you need a real interface

Pass `--net-backend virtio-net` and the guest gets an ordinary network card, its own address, and
ICMP:

```console
$ smolvm machine create --name web --image alpine --net --net-backend virtio-net
$ smolvm machine start --name web
$ smolvm machine exec --name web -- ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: dummy0: <BROADCAST,NOARP> ...
3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
$ smolvm machine exec --name web -- ping -c1 8.8.8.8
1 packets transmitted, 1 packets received, 0% packet loss
```

Choose `virtio-net` when the workload inspects its own interfaces, needs ICMP, or runs software
that expects a routable address — a VPN client, a container runtime, or a network test suite.
Otherwise the default is the one to keep: it needs no interface configuration in the guest and
carries the traffic most workloads actually make.

Run `smolvm machine COMMAND --help` against your installed version for the complete flag set.

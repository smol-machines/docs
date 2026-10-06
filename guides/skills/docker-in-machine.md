---
title: "Docker in machine: run a Docker daemon inside a machine"
---

# Docker in machine: run a Docker daemon inside a machine

Runs a Docker daemon inside a smolvm machine and shows it working there, which is what tools that call Docker themselves need, such as a test suite that starts containers, an image build, or a coding agent that launches containers. Use when dockerd will not start inside a machine; when Docker worked on the first boot and broke after a stop and start; when deciding where Docker's data directory has to live; or when checking whether this is possible on a given platform at all. Do not use it to run OCI images, which smolvm boots natively without Docker, and do not attempt it on Windows, where the bundled guest kernel cannot support it.

Verified on **smolvm v1.22.2** on macOS arm64, 2026-10-03, and on **v1.18.2** on Linux aarch64, 2026-09-24; the Linux runs used
the Smolfile with `memory = 1024`, for a host reason given below. Done means `docker info` succeeds inside the guest, a nested container runs, and
Docker's data sits on the ext4 storage disk rather than the rootfs overlay.
The Linux runs used the scripts of their date; this version's preflight and cleanup scripts ran
on Linux aarch64 on v1.22.2 on 2026-10-03.

smolvm boots OCI images without Docker. This is only for software **inside** the machine that must
call Docker itself.

**On Windows, up to and including v1.22.2, `dockerd` does not start in a machine.** The Windows
guest kernel is built without bridge networking and POSIX message queues, so `dockerd` cannot
create its default network and, forced past that, containers still cannot be created.
`references/windows.md` has the evidence and the direct kernel probe, which gave the same answer on
v1.22.2.

## The trap this packet exists for

**`init` runs once, so the bind mounts are gone on the second boot** and have to be re-applied on
every start. The upstream example says so in its comments and re-applies them in its "Start
dockerd" recipe, which `scripts/start-dockerd.sh` is. Reproduced on both hosts on v1.14.2, v1.18.2
and v1.22.2, and on macOS on v1.16.1:

```
Init already completed, skipping 5 command(s)
NO_BIND_MOUNTS_AFTER_RESTART
DOCKERD_DOWN
```

Running `scripts/start-dockerd.sh` afterwards restored everything, and `docker images` still
listed `alpine:latest`, because the images are on `/storage`. **The failure mode is a daemon that
will not start, or one running on the wrong filesystem, not lost data.**

`smolvm machine create --help` describes `--init` as "Run command on every VM start" at v1.22.2;
`init` runs on the first start only, as [`smolfile.md`](https://github.com/smol-machines/smolvm/blob/main/docs/smolfile.md) says. More in
`references/traps.md`.

## Procedure

**1. Preflight.**

```bash
scripts/preflight.sh
```

`docker_in_machine=verified` on macOS and Linux, `unavailable` on Windows with the reason.

**2. Create and install.** `assets/docker.smolfile` is the upstream example's configuration,
shipped here because **the release tarball does not contain `examples/`**, so the `git clone` step
in the docs site's guide (smolmachines.com/docs) is not something a released install can follow.

```bash
scripts/create-docker-machine.sh              # name defaults to smolskill-docker
```

The `apk add docker` happens on the **first start**, not on create, and dominates the time.

**3. Start the daemon. Run this on every start, not only the first.**

```bash
scripts/start-dockerd.sh
```

It re-applies both bind mounts, clears a stale pid file, starts `dockerd` with the `overlay2`
driver and waits for `docker info` to answer:

```
 Server Version: 25.0.5
 Storage Driver: overlay2
 Docker Root Dir: /var/lib/docker
server_version=25.0.5
result=dockerd_up
```

**4. Prove it, on the right filesystem.**

```bash
scripts/verify-docker.sh
```

```
storage_driver=ok (overlay2)
docker_root_device=ok (/dev/vda)
pull=docker.io/library/alpine:latest
nested_container=ok (NESTED_OK)
host_network=ok (HOSTNET_OK)
host_socket=present (.../vms/<hash>/docker.sock)
result=docker_ok
```

`docker_root_device` is the check that matters. `docker info` succeeds while `/var/lib/docker`
sits on the rootfs overlay, and the failure that follows is confusing and much later.

**5. Use it, and clean up only when it is no longer wanted.** A machine someone asked for is the
deliverable: leave it running and give them its name. Their own code gets in with
`smolvm machine cp <file> smolskill-docker:/workspace/<file>` or a `-v` mount on create, and runs
with `smolvm machine exec --name smolskill-docker -- ...`; with no `docker` client on the host, code
that calls Docker runs inside the machine against this daemon. What this packet shows is the
daemon: `docker info`, a nested container and host networking.

```bash
scripts/cleanup.sh --purge
```

`cleanup.sh` waits up to 20 seconds, polling the machine list, and prints `waiting=up to 20s`
first: an ephemeral machine's entry retires after its run returns.

## Why Docker's data has to live on `/storage`

A hard requirement, not a preference. The smolvm rootfs overlay uses the initramfs (ramfs) as its
lower layer, ramfs has no file-handle support, and overlayfs then rejects it as an upper dir for
Docker's nested overlay. Both mounts are needed: `/var/lib/containerd` holds the snapshotter's
overlay state and fails the same way.

That is why the Smolfile declares `storage = 20`, and why every check here is against `/dev/vda`.

## The host-side socket

`docker_socket = true` bridges the guest's `/var/run/docker.sock` to a host path under the
machine's data directory:

```bash
D=$(smolvm machine data-dir --name smolskill-docker)
DOCKER_HOST=unix://$D/docker.sock docker ps      # needs a docker client on the host
```

The socket is created and `verify-docker.sh` asserts it exists. **Driving it from the host was not
verified**: neither host used here has a `docker` client.

## Security defaults, and why they are the defaults

- **`docker_socket = true` is the one line here that gives something outside the VM real
  authority.** A process on the host that can open that socket can start containers inside the
  machine, mount paths the machine can see and read anything they hold. Leave it off unless a host
  tool actually needs it, which is why nothing in this packet's own checks depends on it.
- **A Docker daemon inside the machine is root inside the machine, and that is the point.** The VM
  boundary is what makes it acceptable: treat root in the guest as untrusted, as the
  [security model](https://github.com/smol-machines/smolvm/blob/main/docs/security-model.md) says, and every forwarded mount, port and network
  permission becomes part of what the nested containers can reach.
- **`--network=host` inside the guest is the guest's network, not yours.** It is verified here
  because Testcontainers and Compose commonly need it, and it is contained by the VM rather than
  by Docker.
- **`net = true` is outbound access for the whole machine**, and it is required for this use case
  because `apk add docker` and every `docker pull` need it. Scope it with `--allow-host` where the
  set of registries is known.
- **The scripts wrap the public CLI only.** They edit no smolvm configuration and nothing under
  `~/.smolvm`, and cleanup deletes only names it recorded under the `smolskill-` prefix.

## Platform arms

- **macOS arm64**: v1.22.2 as shipped, every check passed, the restart trap and its recovery
  included.
- **Linux aarch64**: v1.18.2 and once on v1.22.2, with the Smolfile's memory at 1024 MiB: the Lima
  host could not boot larger guests inside the fixed 30 s readiness window, and the `install`
  packet's traps have the numbers. On a small or busy host, lower `memory` before suspecting
  Docker; 1024 MiB was enough for `dockerd` and a nested alpine container.
- **Linux x86_64**: not run anywhere for this use case.
- **Windows x86_64**: **does not run on v1.22.2**. A v1.14.2 run showed `dockerd` failing; on
  2026-10-03 on v1.22.2 (Windows 11 Home build 10.0.26200 UBR 9457) the direct kernel probe in a
  plain `alpine` guest gave `RTNETLINK answers: Not supported` for a bridge and `No such device` for
  `mqueue`. `references/windows.md` has both.

## Eval prompts, and what they produced

**1. "Give me a machine with a Docker daemon inside it, and show me Docker actually works in
it."**

On v1.18.2, both hosts identical:

```
docker_version=Docker version 25.0.5, build d260a54c81efcc3f00fe67dee78c94b16c2f8692
result=installed
server_version=25.0.5
result=dockerd_up
storage_driver=ok (overlay2)
docker_root_device=ok (/dev/vda)
nested_container=ok (NESTED_OK)
host_network=ok (HOSTNET_OK)
result=docker_ok
```

**2. "Docker worked yesterday and today `dockerd` will not start. Nothing changed."**

Reproduced on both hosts by stopping and starting the machine, with the lines shown under the
trap above; `scripts/start-dockerd.sh` then brought it back to `result=docker_ok` with
`alpine:latest` still listed.

**3. "Can I do this on Windows?"**

**No**, and the answer is short enough to give without running anything: the bundled guest kernel
has `CONFIG_BRIDGE` and `CONFIG_POSIX_MQUEUE` both off, so `dockerd` fails on
`error creating default "bridge" network: operation not supported`, and with `--bridge=none` the
daemon comes up healthy while every container fails on `/dev/mqueue`. That result is from an
earlier run on Windows 11 against v1.14.2, and the kernel probe on `references/windows.md` gave
the same two answers on v1.22.2.

## Re-verified on v1.22.2

Run 2026-10-03 PT against v1.22.2 from the published release, checksum checked, under an isolated
`HOME` on macOS 27.0.1 arm64, twice, the second time from a fresh `HOME`. On Lima `linux-kvm`
(Ubuntu 24.04 aarch64) guests above 2048 MiB timed out on 2026-10-03, so the Linux lines below are
a single run and the Linux stamp stays on its earlier release.

macOS: `result=docker_ok` with `docker_root_device=ok (/dev/vda)`, then after a stop and start
`Init already completed, skipping 5 command(s)`, `NO_BIND_MOUNTS_AFTER_RESTART`, `DOCKERD_DOWN`,
and `start-dockerd.sh` brought it back with `alpine:latest` still listed.

Linux aarch64 at `memory = 1024`: the same lines.

## What was not run

- **`dockerd` itself on Windows after v1.14.2.** The v1.22.2 answer is the kernel probe, not a
  daemon run.
- **Linux x86_64.** Not run for this use case on any host, then or now.
- **Driving the host-side `docker.sock` from a host `docker` client.** The socket is created and
  asserted; neither host here has a docker client to drive it with.
- **Compose and Testcontainers themselves.** The packet verifies `docker info`, a nested container
  and host networking, which is what those depend on, not the tools.

## Related packets

- `dev-env` for the `init`-runs-once semantics this is built on.
- `install` for the boot this assumes, `teardown` for the cleanup script.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can run a Docker daemon inside a smolvm machine.
# Read-only: starts no VM, writes no smolvm state.
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.22.2"

emit() { printf '%s=%s\n' "$1" "$2"; }

blocked=0
note() { printf 'note=%s\n' "$1"; }

# --- the binary --------------------------------------------------------------

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    emit smolvm_installed no
    emit smolvm_version ""
    blocked=1
else
    emit smolvm_installed yes
    version="$("$SMOLVM" --version 2>/dev/null | awk '{print $NF}')"
    emit smolvm_version "${version:-unknown}"
fi

emit verified_version "$VERIFIED_VERSION"
if [ -n "${version:-}" ] && [ "$version" != "unknown" ]; then
    if [ "$version" = "$VERIFIED_VERSION" ]; then
        emit version_status match
    else
        newest="$(printf '%s\n%s\n' "$version" "$VERIFIED_VERSION" | sort -V | tail -1)"
        if [ "$newest" = "$version" ]; then
            emit version_status newer
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; flags and messages move every release, so check the output against the binary before trusting a step here"
        else
            emit version_status older
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version"
        fi
    fi
else
    emit version_status unknown
fi

# --- platform ----------------------------------------------------------------

kernel="$(uname -s)"
arch="$(uname -m)"
case "$arch" in aarch64|arm64) arch=aarch64 ;; esac

case "$kernel" in
    Darwin)
        emit platform "darwin-$arch"
        emit accel hvf
        emit macos_version "$(sw_vers -productVersion)"
        hv="$(sysctl -n kern.hv_support 2>/dev/null)"
        if [ "$hv" = "1" ]; then emit accel_access ok; else emit accel_access denied; blocked=1; fi
        if [ "$arch" != "aarch64" ]; then
            emit hardware_verified no
            note "Intel Mac is not verified by this packet; the installer accepts it and nothing here was run on one"
        else
            emit hardware_verified yes
        fi
        # A VM's agent socket lives under the cache directory. macOS sockaddr_un
        # holds 104 bytes including the terminator.
        sock="$HOME/Library/Caches/smolvm/vms/0123456789abcdef/agent.sock"
        len=${#sock}
        emit socket_path_bytes "$len"
        if [ "$len" -gt 100 ]; then
            emit socket_path_status too_long
            blocked=1
            note "HOME is too deep: every VM start will fail with krun_start_enter -22, whose text blames disks and device options. Install under a shorter HOME."
        else
            emit socket_path_status ok
        fi
        emit unsupported "cuda"
        emit docker_in_machine verified
        ;;
    Linux)
        emit platform "linux-$arch"
        emit accel kvm
        emit socket_path_status n_a
        if [ ! -e /dev/kvm ]; then
            emit accel_access missing
            blocked=1
            note "/dev/kvm does not exist; this host has no KVM"
        elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            emit accel_access ok
        else
            emit accel_access denied
            blocked=1
            note "your user cannot open /dev/kvm. The installer warns and continues, so a successful install says nothing about whether a VM will start. Fix: sudo usermod -aG kvm \$USER, then run the next command through sg kvm -c '...' rather than logging out."
        fi
        emit docker_in_machine verified
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        emit docker_in_machine unavailable
        note "Docker in a machine cannot work on Windows: the bundled guest kernel has neither bridge networking nor POSIX message queues, so dockerd will not start and, forced past that, containers still fail. See references/windows.md."
        ;;
esac

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `assets/docker.smolfile`

```toml
# A machine that runs a Docker daemon inside itself, for workloads that must
# call Docker themselves: Testcontainers, Compose, image builds, agents that
# launch containers. smolvm boots OCI images without Docker, so this is only for
# software inside the machine that needs the daemon.
#
# The bind mounts below are in `init`, as in the upstream example, and `init`
# runs ONCE: they hold for the first boot only. scripts/start-dockerd.sh, the
# example's "Start dockerd" recipe, re-applies them on every start.
cpus = 2
memory = 2048
net = true

# Docker's data directory must live on /storage, not on the rootfs overlay.
# This is a hard requirement: the rootfs overlay uses the initramfs (ramfs) as
# its lower layer, ramfs has no file-handle support, and overlayfs then rejects
# it as an upper dir for Docker's nested overlay.
storage = 20

docker_socket = true

init = [
    "apk update -q",
    "apk add docker -q",
    "mkdir -p /storage/docker /var/lib/docker /storage/containerd /var/lib/containerd",
    "mount --bind /storage/docker /var/lib/docker",
    "mount --bind /storage/containerd /var/lib/containerd",
]
```

### `scripts/create-docker-machine.sh`

```bash
#!/usr/bin/env bash
# Create the machine and install Docker into it. The install happens on the
# first start, not on create.
#
# usage: create-docker-machine.sh [<name>] [<smolfile>]

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-smolskill-docker}"
SMOLFILE="${2:-$here/../assets/docker.smolfile}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

case "$NAME" in
    smolskill-*) ;;
    *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;;
esac

"$SMOLVM" machine create --name "$NAME" -s "$SMOLFILE" --net-backend virtio-net 2>&1 | sed 's/^/  /'
"$here/cleanup.sh" --record "$NAME"

start_out="$("$SMOLVM" machine start --name "$NAME" 2>&1)"
printf '%s\n' "$start_out" | sed 's/^/  /'

fail=0
if printf '%s' "$start_out" | grep -q "Machine '$NAME' running"; then
    printf 'machine_running=yes\n'
else
    printf 'machine_running=no\n'
    fail=1
fi

docker_version="$("$SMOLVM" machine exec --name "$NAME" -- docker --version 2>&1 | tr -d '\r')"
printf 'docker_version=%s\n' "$docker_version"
case "$docker_version" in
    "Docker version"*) ;;
    *) fail=1 ;;
esac

if [ "$fail" -eq 0 ]; then printf 'result=installed\n'; else printf 'result=failed\n'; fi
exit "$fail"
```

### `scripts/start-dockerd.sh`

```bash
#!/usr/bin/env bash
# Start dockerd inside the machine, re-applying the bind mounts first.
#
# usage: start-dockerd.sh [<name>]
#
# Run this on EVERY start, not only the first. `init` runs once, so on any start
# after the first the guest comes up with /var/lib/docker back on the rootfs
# overlay, and dockerd either refuses to start or starts on the wrong
# filesystem. This is the upstream example's "Start dockerd" recipe.

set -uo pipefail

NAME="${1:-smolskill-docker}"
SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

# shellcheck disable=SC2016  # $(seq ...) runs in the guest shell, not here
"$SMOLVM" machine exec --name "$NAME" -- sh -c '
  mkdir -p /storage/docker /var/lib/docker /storage/containerd /var/lib/containerd
  mountpoint -q /var/lib/docker     || mount --bind /storage/docker /var/lib/docker
  mountpoint -q /var/lib/containerd || mount --bind /storage/containerd /var/lib/containerd
  rm -f /var/run/docker.pid
  dockerd --storage-driver=overlay2 >/tmp/dockerd.log 2>&1 &
  # 60 s: dockerd answered docker info within a few seconds on both hosts here;
  # the margin covers a first start that has to create its storage layout.
  for i in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
  docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Docker Root Dir"
' 2>&1 | sed 's/^/  /'

# `docker info` succeeding is not the check that matters; see verify-docker.sh.
server="$("$SMOLVM" machine exec --name "$NAME" -- docker info --format '{{.ServerVersion}}' 2>&1 | tr -d '\r')"
printf 'server_version=%s\n' "$server"
case "$server" in
    [0-9]*) printf 'result=dockerd_up\n' ;;
    *)
        printf 'result=dockerd_down\n'
        printf 'daemon log:\n'
        "$SMOLVM" machine exec --name "$NAME" -- tail -20 /tmp/dockerd.log 2>&1 | sed 's/^/  /'
        exit 1
        ;;
esac
```

### `scripts/verify-docker.sh`

```bash
#!/usr/bin/env bash
# Prove Docker is usable AND on the right filesystem.
#
# usage: verify-docker.sh [<name>]
#
# The df assertion is the one that matters. `docker info` succeeds while
# /var/lib/docker sits on the rootfs overlay, and the failure that follows is
# confusing and much later: overlayfs rejects the ramfs-backed rootfs as an
# upper dir for Docker's nested overlay.

set -uo pipefail

NAME="${1:-smolskill-docker}"
SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf '%s=ok (%s)\n' "$1" "$2"
    else
        printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"
        fail=1
    fi
}
exec_in() { "$SMOLVM" machine exec --name "$NAME" -- "$@" 2>&1 | tr -d '\r'; }

check storage_driver "$(exec_in docker info --format '{{.Driver}}')" overlay2

# The backing device, not the path. Both readings print /var/lib/docker.
# shellcheck disable=SC2016  # the awk field reference belongs to the guest shell
check docker_root_device "$(exec_in sh -c 'df /var/lib/docker | tail -1 | awk "{print \$1}"')" /dev/vda

# Pull first, and separately. A `docker run` that pulls interleaves the pull's
# progress with the container's output, and the two streams arrive in a
# different order on different hosts, so the marker is not reliably the last
# line. Pulling first leaves the run's output alone without discarding the
# stderr that would explain a real failure.
printf 'pull=%s\n' "$(exec_in docker pull -q alpine | tail -1)"
check nested_container "$(exec_in docker run --rm alpine echo NESTED_OK)" NESTED_OK
check host_network     "$(exec_in docker run --rm --network=host alpine echo HOSTNET_OK)" HOSTNET_OK

# docker_socket = true bridges the guest's /var/run/docker.sock to a host path.
sock="$("$SMOLVM" machine data-dir --name "$NAME" 2>/dev/null)/docker.sock"
if [ -S "$sock" ]; then
    printf 'host_socket=present (%s)\n' "$sock"
else
    printf 'host_socket=absent (%s)\n' "$sock"
fi

if [ "$fail" -eq 0 ]; then printf 'result=docker_ok\n'; else printf 'result=FAILED\n'; fi
exit "$fail"
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Delete the machines this packet's scripts created, then prove the host is clean.
#
# Only machines recorded in the state file are deleted, with --cascade, so any
# machine branched from one of them goes too, whatever its name. Any other
# machine you or another session created by hand is never deleted. Scripts
# record a name by calling: cleanup.sh --record <name>
#
# usage: cleanup.sh [--record <name>] [--reap] [--purge]
#   --record <name>  add a machine name to the state file and exit
#   --reap           kill every VM process under this HOME; run without it first
#   --purge          also remove the state file once the list is empty

set -uo pipefail

PACKET="docker-in-machine"
PREFIX="smolskill-"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
STATE_FILE="$STATE_DIR/$PACKET.machines"

reap=0
purge=0
while [ $# -gt 0 ]; do
    case "$1" in
        --record)
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$2" >> "$STATE_FILE"
            exit 0
            ;;
        --reap)  reap=1 ;;
        --purge) purge=1 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

# With SMOLVM_DATA_DIR set, smolvm runs with HOME there on Linux, so its cache
# is under .cache in it.
case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            VMS_DIR="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"
if [ -n "${SMOLVM:-}" ]; then
    case "$(readlink "$SMOLVM" 2>/dev/null || printf '%s' "$SMOLVM")" in
        "$SMOLVM_PREFIX"/*) ;;
        *) printf 'note=%s is not under %s, so the process scan cannot see its forked VMs (all of its VMs on macOS); set SMOLVM_PREFIX to its directory\n' "$SMOLVM" "$SMOLVM_PREFIX" ;;
    esac
fi

# List this HOME's VM processes as "pid marker". The plain run path execs a
# `_boot-vm` child that carries its boot config; the pack-run path forks one that
# carries none. Linux names both `libkrun VM`, or `VM:<hostname>` when HOSTNAME
# is exported; on macOS the executable path and the parent chain scope the
# search. The teardown packet's traps have the why.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                case "$(cat "$p/comm" 2>/dev/null)" in "libkrun VM"|VM:*) ;; *) continue ;; esac
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep -f would match this script.
            procs="$(ps -axo pid=,ppid=,command= 2>/dev/null)"
            printf '%s\n' "$procs" | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # An orphan counts only if it is a run; a fork has its parent's command line.
                if [ "$ppid" = 1 ]; then
                    case "$rest" in
                        *" machine run "*|*" vm run "*|*" pack run "*)
                            printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                    esac
                else
                    parent="$(printf '%s\n' "$procs" | while read -r q qp qrest; do [ "$q" = "$ppid" ] && { printf '%s' "$qrest"; break; }; done)"
                    [ "$parent" = "$rest" ] && printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX"
                fi
            done
            ;;
    esac
}

# 1. Delete recorded machines. Without --force a delete prompts and defaults to
# No; --cascade removes branch children, which otherwise block it.
if [ -s "$STATE_FILE" ]; then
    while read -r name; do
        [ -n "$name" ] || continue
        case "$name" in "$PREFIX"*) ;; *)
            printf 'skipping %s: not created by this packet (no %s prefix)\n' "$name" "$PREFIX"
            continue ;;
        esac
        # Only names still listed: a second stop of a missing name leaves a
        # directory that reads as a leak. The list is read first because grep -q
        # under pipefail can fail the pipeline and skip a listed machine.
        listed="$("$SMOLVM" machine list </dev/null 2>/dev/null | awk 'NR>2{print $1}')"
        grep -qx -- "$name" <<<"$listed" || continue
        "$SMOLVM" machine stop   --name "$name" </dev/null >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade </dev/null 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 2. An ephemeral machine's entry retires after its run returns: poll, 20 s at most.
printf 'waiting=up to 20s for ephemeral entries to retire before asserting\n'
waited=0
listing="$("$SMOLVM" machine list 2>&1)"
while ! grep -q 'No machines found' <<<"$listing" && [ "$waited" -lt 20 ]; do
    sleep 1; waited=$((waited + 1))
    listing="$("$SMOLVM" machine list 2>&1)"
done
printf 'waited=%ss\n' "$waited"

# 3. Assert the value, not the exit code.
if grep -q 'No machines found' <<<"$listing"; then
    printf 'machines=clean\n'
    [ "$purge" -eq 1 ] && rm -f "$STATE_FILE"
else
    printf 'machines=remaining\n'
    printf '%s\n' "$listing" | sed 's/^/  /'
    printf 'note=this packet did not create these, so it will not delete them. By name:\n'
    printf '  smolvm machine stop --name <NAME> && smolvm machine delete --name <NAME> --force\n'
    printf '  add --cascade for a machine that was branched from another\n'
fi

# 4. Report VM processes under this HOME's state, such as a killed wrapper's.
# With --reap every one is killed, including a machine another packet kept.
found=0
while read -r pid cfg; do
    [ -n "$pid" ] || continue
    found=1
    printf 'vm_process=%s config=%s\n' "$pid" "$cfg"
    if [ "$reap" -eq 1 ]; then
        kill -9 "$pid" 2>/dev/null && printf '  killed %s\n' "$pid"
    fi
done <<EOF
$(list_vm_processes)
EOF

if [ "$found" -eq 0 ]; then
    printf 'vm_processes=none\n'
elif [ "$reap" -eq 0 ]; then
    printf 'rerun with --reap to kill them\n'
fi
```

## Docker in a machine traps

### The bind mounts do not survive a stop, and `init` will not re-apply them

**This is the trap that breaks the second session**, and it is the reason this packet has a
separate `start-dockerd.sh` rather than a Smolfile alone.

`init` runs **once**. On every start after the first the guest comes up with `/var/lib/docker`
back on the rootfs overlay. Observed on macOS arm64 and Linux aarch64, immediately after one stop
and start:

```
Init already completed, skipping 5 command(s)
NO_BIND_MOUNTS_AFTER_RESTART
DOCKERD_DOWN
```

**Mounts applied in `init` hold for the first boot only.** Re-apply them in the same command that
starts `dockerd`, as the upstream example's "Start dockerd" recipe does and
`scripts/start-dockerd.sh` does. After it ran, the same host reported `dockerd_up` and every check passed again.

**Your images do survive**, because they are on `/storage`. After the restart and the re-mount,
`docker images` still listed `alpine:latest`. So the failure mode is "dockerd will not start" or
"dockerd starts on the wrong filesystem", not data loss.

### `/var/lib/docker` must be on `/storage`, and `docker info` will not tell you it is not

A hard requirement, not a preference. The smolvm rootfs overlay uses the initramfs (ramfs) as its
lower layer, ramfs has no file-handle support, and overlayfs then rejects it as an upper dir for
Docker's nested overlay.

**`docker info` succeeds while `/var/lib/docker` sits on the overlay**, and the failure that
follows is confusing and much later. Assert the backing device:

```bash
smolvm machine exec --name <n> -- sh -c 'df /var/lib/docker | tail -1'
# /dev/vda 20623316 412 20606520 0% /storage
```

Both readings print `/var/lib/docker` as the mount point, so the path tells you nothing. The
device is the value that matters.

### Both bind mounts are needed, not just Docker's

`/var/lib/containerd` holds the snapshotter's overlay state and fails the same way if it is left
on the rootfs overlay. The upstream Smolfile mounts both and its own comments say container start
fails without the second one, with containerd's overlay mount rejected as `invalid argument`.

The `dockerd` start command in the docs site's guide (`guides/docker-in-a-machine.md` in
`smol-machines/docs`, at v1.14.6) bind-mounts only `/storage/docker`; `/storage/containerd` is
needed as well.

### A `docker run` that pulls interleaves two streams

The first run of an image prints the pull's progress alongside the container's own output, and the
two arrive in a different order on different hosts: on Linux aarch64 the marker was the last line,
on macOS arm64 it was not. A check that takes the last line passes on one host and fails on the
other. `scripts/verify-docker.sh` pulls first, separately, so the run's output stands alone
without discarding the stderr that would explain a real failure.

### `machine delete` asks for confirmation

Pass `--force` in a script. From v1.17.0 a delete without it on a non-terminal stdin exits 1;
before that it exited 0 and left a 20 GiB machine behind.

### Where the docs site's guide differs from this packet, at v1.14.6

The guide is `guides/docker-in-a-machine.md` in `smol-machines/docs`, published at
smolmachines.com/docs.

- Its `dockerd` command bind-mounts one path; the upstream Smolfile mounts two.
- It runs `machine create ... -s examples/docker-in-vm/docker.smolfile` after a `git clone` of the
  smolvm repo. **The release tarball does not contain `examples/`**, so this packet ships its own
  `assets/docker.smolfile`.
- It says bind mounts "do not survive a stop and start, so reapply that mount before starting
  `dockerd`", which was verified; its example applies them in `init`, which runs on the first start
  only.
- `smolvm machine create --help` describes `--init` as "Run command on every VM start", at v1.14.6
  and at v1.22.2. The docs site's `introduction/concepts/smolfile.md` says under "When init runs"
  that init runs once, on the first start, as does [`smolfile.md`](https://github.com/smol-machines/smolvm/blob/main/docs/smolfile.md) here.
- It has no platform note; on Windows the procedure cannot succeed. See `references/windows.md`.

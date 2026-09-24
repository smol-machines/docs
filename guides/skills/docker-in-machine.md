---
title: "Docker in machine: run a Docker daemon inside a machine"
---

# Docker in machine: run a Docker daemon inside a machine

Runs a Docker daemon inside a smolvm machine, for workloads that must call Docker themselves such as Testcontainers, Compose, image builds, or a coding agent that launches containers. Use when dockerd will not start inside a machine; when Docker worked on the first boot and broke after a stop and start; when deciding where Docker's data directory has to live; or when checking whether this is possible on a given platform at all. Do not use it to run OCI images, which smolvm boots natively without Docker, and do not attempt it on Windows, where the bundled guest kernel cannot support it.

Verified on **smolvm v1.16.1** on macOS arm64, 2026-09-15, and on **v1.14.6** on Linux aarch64,
2026-09-10. Done means `docker info` succeeds inside the guest, a nested container runs, and
Docker's data sits on the ext4 storage disk rather than the rootfs overlay.

smolvm boots OCI images without Docker. This is only for software **inside** the machine that must
call Docker itself.

**This use case does not exist on Windows, up to and including v1.14.6.** The bundled guest kernel
there has neither bridge networking nor POSIX message queues, so `dockerd` will not start and,
forced past that, containers still cannot be created. `references/windows.md` has the evidence, and
the direct kernel probe to re-check it on a newer build.

## The trap this packet exists for

**`init` runs once, so the bind mounts are gone on the second boot.** The upstream example puts
them in `init` alone, which is correct for exactly one boot. Reproduced on both hosts, and again on
macOS arm64 on v1.16.1 on 2026-09-15:

```
Init already completed, skipping 5 command(s)
NO_BIND_MOUNTS_AFTER_RESTART
DOCKERD_DOWN
```

Running `scripts/start-dockerd.sh` afterwards restored everything, and `docker images` still
listed `alpine:latest`, because the images are on `/storage`. **The failure mode is a daemon that
will not start, or one running on the wrong filesystem, not lost data.**

`smolvm machine create --help` still describes `--init` as running "on every VM start" at
v1.14.6, which is what makes the upstream example look correct. The docs have been corrected and
now say init runs once. More in `references/traps.md`.

## Procedure

**1. Preflight.**

```bash
scripts/preflight.sh
```

`docker_in_machine=verified` on macOS and Linux, `unavailable` on Windows with the reason.

**2. Create and install.** `assets/docker.smolfile` is the upstream example's configuration,
shipped here because **the release tarball does not contain `examples/`**, so the guide's
`git clone` step is not something a released install can follow.

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

**5. Clean up.**

```bash
scripts/cleanup.sh --purge
```

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
  boundary is what makes it acceptable: treat root in the guest as untrusted, and remember that
  every forwarded mount, port and network permission becomes part of what the nested containers
  can reach.
- **`--network=host` inside the guest is the guest's network, not yours.** It is verified here
  because Testcontainers and Compose commonly need it, and it is contained by the VM rather than
  by Docker.
- **`net = true` is outbound access for the whole machine**, and it is required for this use case
  because `apk add docker` and every `docker pull` need it. Scope it with `--allow-host` where the
  set of registries is known.
- **The scripts wrap the public CLI only.** They edit no smolvm configuration and nothing under
  `~/.smolvm`, and cleanup deletes only names it recorded under the `smolskill-` prefix.

## Platform arms

- **Linux aarch64**: the scripts were run here, which is the verified platform for this use case.
- **macOS arm64**: the scripts were run here too and every check passed, including the restart
  trap and its recovery. The material behind this packet had not exercised this use case on macOS.
- **Linux x86_64**: not run anywhere for this use case.
- **Windows x86_64**: **not possible**, on the evidence of one v1.14.2 run. A re-run on
  2026-09-11 against v1.14.6 **did not reach the question**: both attempts died pulling the image,
  so nothing was confirmed or refuted there. `references/windows.md` has both, and the direct
  kernel probe that answers it without a large pull.

## Eval prompts, and what they produced

Run on 2026-09-07 PT against v1.14.2 from the published release, under an isolated `HOME`, on
macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64). Output is verbatim.

**1. "Give me a machine where I can run Testcontainers, and show me Docker actually works in
it."**

Both hosts, identical:

```
docker_version=Docker version 25.0.5, build d260a54c81efcc3f00fe67dee78c94b16c2f8692
result=installed
 Server Version: 25.0.5
 Storage Driver: overlay2
 Docker Root Dir: /var/lib/docker
result=dockerd_up
storage_driver=ok (overlay2)
docker_root_device=ok (/dev/vda)
nested_container=ok (NESTED_OK)
host_network=ok (HOSTNET_OK)
result=docker_ok
```

**2. "Docker worked yesterday and today `dockerd` will not start. Nothing changed."**

Reproduced on both hosts by stopping and starting the machine, then checking before running
anything:

```
Init already completed, skipping 5 command(s)
NO_BIND_MOUNTS_AFTER_RESTART
DOCKERD_DOWN
```

`scripts/start-dockerd.sh` then brought it back to `result=docker_ok` on both, and the images
were still there:

```
$ smolvm machine exec --name smolskill-docker -- docker images --format '{{.Repository}}:{{.Tag}}'
alpine:latest
```

**3. "Can I do this on Windows?"**

**No**, and the answer is short enough to give without running anything: the bundled guest kernel
has `CONFIG_BRIDGE` and `CONFIG_POSIX_MQUEUE` both off, so `dockerd` fails on
`error creating default "bridge" network: operation not supported`, and with `--bridge=none` the
daemon comes up healthy while every container fails on `/dev/mqueue`. That result is from an
earlier run on Windows 11 against v1.14.2. The 2026-09-11 attempt on v1.14.6 died pulling the
image and confirmed nothing either way, so that answer still rests on the one run.

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 on macOS 26.6.2 arm64 **and Lima `linux-kvm` (Ubuntu 24.04
aarch64)**: `Docker version 25.0.5`, `Server Version: 25.0.5`, `storage_driver=ok (overlay2)`,
`docker_root_device=ok (/dev/vda)`, `nested_container=ok (NESTED_OK)`,
`host_network=ok (HOSTNET_OK)`, `result=docker_ok` on both. The Linux arm was not re-run on
v1.14.3; it is re-run here.

## What was not run

- **Windows on v1.14.6.** The 2026-09-11 attempt never got past the image pull, so the conclusion
  in `references/windows.md` is still the v1.14.2 one. That page carries a direct kernel probe that
  answers it from a plain `alpine` guest without the large pull.
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

VERIFIED_VERSION="1.14.6"

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
        emit unsupported "vulkan,cuda"
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
        emit unsupported "vulkan"
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
# The bind mounts below are in `init`, which is where the upstream example puts
# them, and `init` runs ONCE. They are correct for the first boot and gone on
# every boot after it, so scripts/start-dockerd.sh re-applies them before
# starting dockerd. Do not rely on this block alone.
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
# filesystem. The upstream example puts these mounts in `init` alone, which is
# correct for exactly one boot.

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
# Only machines recorded in the state file are deleted, so a machine you or
# another session created by hand is never touched. Scripts record a name by
# calling: cleanup.sh --record <name>
#
# usage: cleanup.sh [--record <name>] [--reap] [--purge]
#   --record <name>  add a machine name to the state file and exit
#   --reap           kill leftover VM processes (see the warning it prints)
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

case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      VMS_DIR="${SMOLVM_DATA_DIR:-$HOME/.cache/smolvm}/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"

# List this HOME's smolvm VM processes, as "pid marker".
#
# Two process shapes exist and a reaper has to catch both. The plain
# `machine run` path EXECS a child whose argv[1] is `_boot-vm` and whose argv[2]
# is its boot-config path. The pack-run path, which is `--oci-cache` or any
# `init`, FORKS without execing, so the child inherits the parent's argv and
# carries no boot-config at all. Matching `_boot-vm` alone is therefore blind to
# exactly the path whose child survives an interrupt
# (smol-machines/smolvm#1193): measured on v1.14.6, it reported "none" while two
# orphaned VMs held 234 MB each.
#
# On Linux both shapes rename themselves to `libkrun VM`, the one marker that
# covers both and that no shell can hold. macOS exposes no rename, so there the
# executable path scopes the search to this HOME and the parent chain separates
# a VM from the CLI that started it.
#
# `pgrep -f _boot-vm` is not an alternative: it matches any shell whose text
# contains that string, including this script.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                [ "$(cat "$p/comm" 2>/dev/null)" = "libkrun VM" ] || continue
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                # Forked shape: nothing in argv identifies it, so scope by the
                # binary it is running.
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep cannot return ppid and the full
            # command together, and pgrep -f matches this script's own text.
            own=" $(ps -axo pid=,command= 2>/dev/null | grep -F "$SMOLVM_PREFIX/smolvm-bin" | awk '{print $1}' | tr '\n' ' ') "
            ps -axo pid=,ppid=,command= 2>/dev/null | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # Forked shape: its parent is the CLI that started it, or init
                # once that CLI is gone.
                if [ "$ppid" = 1 ]; then
                    printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX"
                else
                    case "$own" in *" $ppid "*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;; esac
                fi
            done
            ;;
    esac
}

# 1. Delete recorded machines. --force is not optional: without it the command
# prompts, defaults to No, and leaves the machine in place while the script
# carries on. --cascade removes branch children, which otherwise block the
# delete.
if [ -s "$STATE_FILE" ]; then
    while read -r name; do
        [ -n "$name" ] || continue
        case "$name" in "$PREFIX"*) ;; *)
            printf 'skipping %s: not created by this packet (no %s prefix)\n' "$name" "$PREFIX"
            continue ;;
        esac
        "$SMOLVM" machine stop   --name "$name" >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 2. An ephemeral machine's entry retires after the run returns, not with it.
# Asserting an empty list immediately fails on a healthy host.
sleep 20

# 3. Assert the value, not the exit code.
listing="$("$SMOLVM" machine list 2>&1)"
if printf '%s' "$listing" | grep -q 'No machines found'; then
    printf 'machines=clean\n'
    [ "$purge" -eq 1 ] && rm -f "$STATE_FILE"
else
    printf 'machines=remaining\n'
    printf '%s\n' "$listing" | sed 's/^/  /'
    # These were not created by this packet, so nothing here will remove them.
    # Say what does, rather than leaving the reader to guess: delete prompts and
    # defaults to No without --force, and a branched machine also needs --cascade.
    printf 'note=this packet did not create these, so it will not delete them. By name:\n'
    printf '  smolvm machine stop --name <NAME> && smolvm machine delete --name <NAME> --force\n'
    printf '  add --cascade for a machine that was branched from another\n'
fi

# 4. Report VM processes an interrupt left behind. Ctrl-C does not stop a
# machine: the VM outlives the CLI and `machine list` cannot see it, so this is
# the only route to it. Only processes whose boot config lives under this HOME's
# smolvm state are listed, so a VM another session started is left alone.
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

**Putting the mounts in `init`, as the upstream example does, is correct for exactly one boot.**
Re-apply them in the same command that starts `dockerd`, which is what `scripts/start-dockerd.sh`
does. After it ran, the same host reported `dockerd_up` and every check passed again.

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

`guides/docker-in-a-machine.md` gives a `dockerd` start command that bind-mounts only
`/storage/docker`. That command is incomplete.

### A `docker run` that pulls interleaves two streams

The first run of an image prints the pull's progress alongside the container's own output, and the
two arrive in a different order on different hosts: on Linux aarch64 the marker was the last line,
on macOS arm64 it was not. A check that takes the last line passes on one host and fails on the
other. `scripts/verify-docker.sh` pulls first, separately, so the run's output stands alone
without discarding the stderr that would explain a real failure.

### `machine delete` prompts and defaults to No

Pass `--force` in a script, or the cleanup reports success and leaves a 20 GiB machine behind.

### What the guide and the CLI still get wrong for this use case, at v1.14.6

- `guides/docker-in-a-machine.md` bind-mounts only one path in its `dockerd` command, while the
  upstream Smolfile mounts two.
- The same guide shows `machine create ... -s examples/docker-in-vm/docker.smolfile` after a
  `git clone` of the smolvm repo. **The release tarball does not contain `examples/`**, so a user
  who installed from the release has to clone the repo to follow the guide at all. This packet
  ships its own `assets/docker.smolfile` for that reason.
- The same guide says bind mounts "do not survive a stop and start, so reapply that mount before
  starting `dockerd`", which is correct and verified. But the page's own example puts them in
  `init`, where they run once, and never connects the two facts.
- `smolvm machine create --help` describes `--init` as "Run command on every VM start" at
  v1.14.6. If that were true the example would be correct, and **it is the surviving copy of the
  wrong promise**: `introduction/concepts/smolfile.md` has been corrected and now documents under
  "When init runs" that init runs once, on the first start.
- The guide carries no platform note at all, and on Windows the procedure cannot succeed. See
  `references/windows.md`.

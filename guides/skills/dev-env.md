---
title: "Dev env: a persistent machine you re-enter"
---

# Dev env: a persistent machine you re-enter

Keeps a persistent smolvm machine with its dependencies already installed and re-enters it cheaply across sessions. Use when a project needs an isolated development environment that survives stop and start; when deciding what belongs in a Smolfile's init versus what has to run on every boot; when a package installed in a machine has vanished after a restart; or when exec answers "the container smolvm-<hash> is not running". Do not use it for untrusted code, which needs a machine that leaves nothing behind (see the sandbox packet), or for running a Docker daemon inside the machine (see docker-in-machine).

Verified on **smolvm v1.18.2** on macOS arm64 and Linux aarch64, 2026-09-24; the Linux run used
the Smolfile with `memory = 1024`, for the host reason in "Re-verified on v1.18.2". Done means a second `start` is fast, skips provisioning, and the packages installed in
the first session are still there.

The whole use case turns on one fact: **`init` runs once, not on every start.** The docs now say
so, under their own "When init runs" heading, but `smolvm machine create --help` still reads
"Run command on every VM start" at v1.18.2. The CLI is where the wrong promise survives, and
provisioning designed around it comes up missing on the second boot.

## Procedure

**1. Preflight.**

```bash
scripts/preflight.sh
```

Read-only. `restart_after_stop=verified` on macOS and Linux, and on Windows too as of v1.14.6.
The script covers macOS and Linux only, so its Windows note points at `references/windows.md`.

**2. Declare the machine.** `assets/dev.smolfile` is a working starting point, and the one
`verify-persistence.sh` is written against: it asserts the `app` user and the `/app` workdir that
file sets. `assets/python.smolfile` and `node.smolfile` are plainer examples without them.

```toml
image = "python:3.12-alpine"
net = true
cpus = 2
memory = 2048
volumes = ["./src:/app"]
init = ["sh -c \"id -un > /init-ran-as.txt\"", "adduser -D app"]
user = "app"
workdir = "/app"
```

**3. Create and bring it up.**

```bash
scripts/create-dev-machine.sh              # name defaults to smolskill-dev
scripts/create-dev-machine.sh smolskill-myproj ./my.smolfile
```

It creates the machine **with an explicit long-lived workload command**, records the name for
cleanup, starts it, waits for the workload container to answer with a value, and then reports what
actually happened rather than that nothing errored:

```
init_ran=yes
machine_running=yes
workload_ready_after_s=0
workload_ready=yes
init_ran_as=root
exec_user=app
workdir=/app
result=up
```

`init_ran_as=root` with `exec_user=app` is the correct outcome, not a bug: `init` provisions the
machine and runs as root regardless of `user`, while `exec` and `shell` run as `user`.

**4. Work in it.**

```bash
smolvm machine exec  --name smolskill-dev -- pip install --user requests
smolvm machine exec  --name smolskill-dev --user root -- sh -c 'mkdir -p /storage/keep'
smolvm machine shell --name smolskill-dev            # interactive, lands in workdir as `user`
```

**5. Prove it is worth keeping.**

```bash
scripts/verify-persistence.sh
```

It installs a package and records its **version**, seeds one file per filesystem, stops, starts,
and then asserts each value against what it recorded. A version comparison is the point: an import
that does not crash can be satisfied by a system copy and says nothing about your install.

**6. Clean up, when the machine is no longer wanted.** Not at the end of a setup: the machine is the
deliverable, so leave it stopped and tell the user its name.

```bash
scripts/cleanup.sh --purge
```

## What `init` and `user` actually do at v1.14.2

Observed, not inferred:

| question | observed |
|---|---|
| when does `init` run? | on the **first `start`**, not on `create`, and not again |
| second start | prints `Init already completed, skipping N command(s)` |
| which user runs `init`? | **root**, even with `user = "app"` set |
| which user runs `exec` and `shell`? | the Smolfile `user` |
| override per command | `machine exec --user root` works |
| is there `machine start --init`? | **no** |

## What survives a stop and start

| location | survives | why |
|---|---|---|
| pip `--user` packages | yes | under `$HOME`, on the overlay |
| `$HOME/...` files | yes | overlay |
| files written at `/` | yes | overlay |
| `/tmp` | **no** | `tmpfs` |
| `/storage/...` | yes | the ext4 disk itself |

The root filesystem is an overlay whose upper layer lives on the machine's ext4 disk, which is why
writes to `/` persist while `tmpfs` mounts do not.

## Traps

Full detail in `references/traps.md`. The three that cost the most:

- **`init` runs once.** `smolvm machine create --help` still says "Run command on every VM start"
  at v1.18.2 while `machine run --help` says the right thing, so the CLI contradicts itself in its
  own help output. The docs have been corrected and now say once. Anything that must be true on
  every boot, a bind mount above all, has to run in the command that needs it.
- **`exec` right after `start` can answer with a message rather than running.** If you see
  ``the container `smolvm-<hash>` is not running``, **check first whether the machine has a
  workload at all**: without a command, `create` uses the image's own CMD as the persistent
  workload, and for an interpreter image that exits at once, so there is no container to exec into
  and waiting will not help. Only when a long-lived workload is configured is this a readiness
  race, and then a short retry loop is the fix. Measured on a nested-virt aarch64 host on v1.14.6:
  1 exec in 20 failed that way with no command, 0 in 20 with an explicit long-lived one.
  **Re-measured on v1.16.1 on 2026-09-15 and it did not reproduce**: 0 of 20 with no command and
  0 of 20 with one, on macOS arm64 and on Lima aarch64 alike. **On v1.18.2 it is back on Linux**:
  1 of 20 with no command on Lima aarch64, 0 of 20 on macOS. Give a machine you intend to `exec`
  into a long-lived workload.
- **`machine shell` does not start a stopped machine**, despite its own help text saying it does.
  Still true on v1.18.2.
- **A machine that runs Tailscale or another carrier NAT VPN inside needs `--guest-subnet` at
  create.** Its default virtio-net link sits inside `100.64.0.0/10`, the VPN routes the gateway
  and resolver away, and every lookup fails. A Smolfile has no key for it at v1.18.2 and
  `machine update` cannot add it, so pass it on `create` next to `-s`:
  `smolvm machine create --name smolskill-dev -s dev.smolfile --guest-subnet 10.200.0.0/30`.

Two smaller ones: `create` is instant and proves nothing, because every failure lands on the first
`start`; and a host `volumes` mount is not writable by a non-root `user`, so build output has to go
somewhere else.

## Security defaults, and why they are the defaults

- **`user` in the Smolfile is what your workload runs as, and it is not root.** `init` running as
  root is the provisioning step, deliberately separated from the workload's identity. Keep them
  separate rather than setting `user = "root"` to make a mount writable: the mount carries host
  ownership, and running the workload as root to reach it hands root in the guest everything the
  mount exposes on the host.
- **A `volumes` mount is host authority handed to the guest**, so mount the narrowest directory
  that works and prefer `:ro` for anything the machine only reads. Treat root in the guest as
  untrusted: the VM boundary limits its direct access to the host, while every forwarded mount,
  port and network permission becomes part of the workload's authority.
- **`net = true` is outbound access for the whole machine.** A dev machine that only needs a
  package index does not need general egress; `--allow-host` scopes it.
- **These scripts wrap the public CLI only.** They edit no smolvm configuration and nothing under
  `~/.smolvm`, and cleanup deletes only names it recorded under the `smolskill-` prefix.

## Platform arms

- **Linux aarch64**: the scripts were run here on v1.18.2 with the Smolfile's memory at 1024 MiB,
  and on v1.14.6 at the Smolfile's 2048. **At 2048 on v1.18.2 the restart timed out**, for a host
  reason: see the re-verification section below.
- **macOS arm64**: the scripts were run here on v1.18.2 as shipped, and every check passed.
- **Linux x86_64**: verified in the material behind this packet, not re-run here.
- **Windows x86_64**: `references/windows.md`, **re-run on 2026-09-11 against v1.14.6** on
  Windows 11 Home build 10.0.26200.0 UBR 9445. Create, two stops and two starts, with a marker
  read back after each start: **a stopped machine starts again and its state survives**, where on
  v1.14.2 it did not. That page also carries the WHP device ceiling a Windows preflight needs:
  four `-v` mounts, three when a port is published.
- **`init` after a checkpoint restore**: not verified anywhere.

## Eval prompts, and what they produced

Run on 2026-09-07 PT against v1.14.2 from the published release, under an isolated `HOME`. Output
is verbatim.

**1. "Set me up a Python dev machine I can come back to, and prove the packages survive a
restart."**

macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64) gave identical results:

```
init_ran=yes
machine_running=yes
workload_ready_after_s=0
workload_ready=yes
init_ran_as=root
exec_user=app
workdir=/app
result=up

workload_ready_after_s=0
installed_version=2.34.2
  Starting machine 'smolskill-dev' with 1 mount(s)...
  Init already completed, skipping 3 command(s)
  Machine 'smolskill-dev' running (PID: 58513)
init_ran_once=ok (yes)
package_version=ok (2.34.2)
home_file=ok (SURVIVES)
storage_file=ok (SURVIVES)
tmp_file=ok (WIPED)
exec_user=ok (app)
workdir=ok (/app)
result=persistent
```

**2. "My bind mount is gone after I restarted the machine. It is right there in `init`."**

`init` ran once. The Linux run shows the machine's own report of it:

```
Init already completed, skipping 3 command(s)
```

There is no `machine start --init`, so the mount has to be re-applied by the command that needs
it. `docker-in-machine` is the packet built entirely around this.

**3. "`smolvm machine exec` just told me the container is not running, but the machine is
running."**

Reproduced deliberately by creating the same machine without a workload command, then running 20
execs, on Lima:

```
 3: the container `smolvm-e51bb94127b751bf` is not running
failures=1/20
 4: the container `smolvm-32edffb50eaf0d20` is not running
failures_after_restart=1/20
```

and with the explicit long-lived workload `scripts/create-dev-machine.sh` passes:

```
failures=0/20
failures_after_restart=0/20
```

The changing hash is the tell: the workload container is being relaunched between execs.

## Re-verified on v1.18.2

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64).

**macOS, as shipped: full pass.**

```
init_ran=yes / machine_running=yes / workload_ready=yes
init_ran_as=root / exec_user=app / workdir=/app / result=up
  Init already completed, skipping 3 command(s)
init_ran_once=ok (yes)
package_version=ok (2.34.2)
home_file=ok (SURVIVES) / storage_file=ok (SURVIVES) / tmp_file=ok (WIPED)
exec_user=ok (app) / workdir=ok (/app)
result=persistent
```

**Linux aarch64: the same values with `memory = 1024`.** With the shipped `memory = 2048` the
first start passed and the restart failed with `agent did not become ready within 30 seconds`, and
every check after it failed on `machine ... is not running`. That box could not boot guests above
2048 MiB in time that day and was borderline at 2048, on v1.16.1 as well, so the cause is the
host; the `install` packet's traps have the numbers. If a restart times out on a small or busy
host, lower `memory` before looking for a product fault.

**Also re-checked:** `machine create --help` still says `--init` runs "on every VM start";
`machine shell` against a stopped machine still answers `machine 'smolskill-dev' is not running.
Use 'smolvm machine start --name smolskill-dev' first.`; the no-command exec race was 0 of 20 on
macOS and 1 of 20 on Linux (``the container `smolvm-36c8a04bc9168bd1` is not running``).

**`--guest-subnet` on a persistent machine**, macOS: created with `-s dev.smolfile --guest-subnet
10.200.0.0/30`, the guest was `10.200.0.2/30` and reached `pypi.org`, and after a stop and start
still `10.200.0.2/30`. A Smolfile with `guest_subnet` under `[network]` is rejected with
``unknown field `guest_subnet`, expected one of `allow_hosts`, `allow_cidrs`, `credentials` ``.

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 on macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04
aarch64). **Full pass on both**, restart included:

```
init_ran=yes / machine_running=yes / workload_ready=yes
init_ran_as=root / exec_user=app / workdir=/app / result=up
init_ran_once=ok (yes)
package_version=ok (2.34.2)
home_file=ok (SURVIVES) / storage_file=ok (SURVIVES) / tmp_file=ok (WIPED)
result=persistent
```

The Linux arm was unconfirmed on v1.14.3 because that host was failing one plain boot in ten. It
is confirmed here.

## What was not run

- **Windows beyond the restart.** The 2026-09-11 v1.14.6 run covered create, stop and start and
  the marker. The WHP device ceiling and the scripted-driving pattern on that page are still from
  the earlier run.
- **Linux x86_64.**
- **`init` after a checkpoint restore.** Nowhere, on any platform.
- **The `USER` interaction still settling.** `init` runs as root at v1.14.2, and whether the
  image's own `USER` still governs it in some paths is open as
  [smolvm#1189](https://github.com/smol-machines/smolvm/issues/1189). Nothing here tested an image
  with a `USER` line.

## Related packets

- `install` for the boot this assumes, and `teardown` for the cleanup script.
- `docker-in-machine` for the clearest case of the `init`-runs-once trap.
- `pack` for turning the machine this packet builds into a portable artifact.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can keep a persistent smolvm dev machine. Read-only:
# starts no VM, writes no smolvm state, changes no group membership.
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.18.2"

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
        emit restart_after_stop verified
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
        emit restart_after_stop verified
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        emit restart_after_stop broken
        note "this script covers macOS and Linux. On Windows a stopped machine starts again as of v1.14.6, and the WHP device budget caps you at four -v mounts, three when a port is published. See references/windows.md."
        ;;
esac

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `assets/dev.smolfile`

```toml
# A persistent development machine. `smolvm machine create -s dev.smolfile`.
#
# The two keys worth understanding before you edit this:
#
#   init  runs ONCE, on the first start, and as root. It does not run again on
#         later starts, whatever the docs say, so anything that has to be true
#         on every boot does not belong here.
#   user  governs `exec` and `shell`, not `init`.
#
# There is no workload-command key here. Pass one after `--` on `machine create`,
# as scripts/create-dev-machine.sh does: without it the image's own CMD becomes
# the persistent workload, and for an interpreter image that command exits at
# once and `exec` starts racing the relaunch.
image = "python:3.12-alpine"
net = true
cpus = 2
memory = 2048

# A host mount carries host ownership, so `user` below cannot write to it.
# Read source in, write build output somewhere else.
volumes = ["./src:/app"]

init = [
  "sh -c \"id -un > /init-ran-as.txt\"",
  "sh -c \"date +%s >> /init-count.txt\"",
  "adduser -D app",
]

user = "app"
workdir = "/app"
```

### `scripts/create-dev-machine.sh`

```bash
#!/usr/bin/env bash
# Create a persistent dev machine and bring it up for the first time.
#
# usage: create-dev-machine.sh [<name>] [<smolfile>]
#   name      default smolskill-dev (the prefix cleanup.sh will delete)
#   smolfile  default ../assets/dev.smolfile
#
# `create` is configuration only: it returns in milliseconds, pulls nothing and
# reports no failure. The pull, the init commands and any of their failures all
# land on the first `start`, so a fast create is not evidence that anything works.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-smolskill-dev}"
SMOLFILE="${2:-$here/../assets/dev.smolfile}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

case "$NAME" in
    smolskill-*) ;;
    *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;;
esac

# The Smolfile mounts ./src, which is relative to the working directory.
mkdir -p ./src

# Give the machine a workload that stays up. Without a command, `create` launches
# the image's own ENTRYPOINT/CMD as the persistent workload; for an interpreter
# image such as python:3.12-alpine that command reads EOF and exits at once, the
# container is relaunched, and `exec` then intermittently answers "the container
# `smolvm-<hash>` is not running" instead of running your command. Measured on a
# nested-virt aarch64 host: 1 exec in 20 failed that way with no command, 0 in 20
# with this one, both on a fresh machine and immediately after a restart.
"$SMOLVM" machine create --name "$NAME" -s "$SMOLFILE" \
    -- sh -c 'while true; do sleep 3600; done' 2>&1 | sed 's/^/  /'
"$here/cleanup.sh" --record "$NAME"

start_out="$("$SMOLVM" machine start --name "$NAME" 2>&1)"
printf '%s\n' "$start_out" | sed 's/^/  /'

fail=0
if printf '%s' "$start_out" | grep -q 'Running .* init command'; then
    printf 'init_ran=yes\n'
else
    printf 'init_ran=no\n'
    fail=1
fi
if printf '%s' "$start_out" | grep -q "Machine '$NAME' running"; then
    printf 'machine_running=yes\n'
else
    printf 'machine_running=no\n'
    fail=1
fi

# `start` returns before the workload container is up. Wait for a VALUE: an empty
# result and a zero exit code both pass while the container is still coming up,
# so a probe that asserts either of those reports ready too early and the next
# three checks read a message as their answer.
wait_for_workload() {
    # 120 s: the slowest first start observed while building this packet was
    # under 20 s on a nested-virt aarch64 host, so this is six times the worst
    # case and still short enough that a real hang is reported, not waited on.
    waited=0
    while [ "$waited" -lt 120 ]; do
        out="$("$SMOLVM" machine exec --name "$1" -- sh -c 'echo WORKLOAD_READY' 2>&1 | tr -d '\r')"
        if [ "$out" = "WORKLOAD_READY" ]; then
            printf 'workload_ready_after_s=%s\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    printf 'workload_ready_after_s=timeout last_probe=%s\n' "$out"
    return 1
}

if wait_for_workload "$NAME"; then
    printf 'workload_ready=yes\n'
else
    printf 'workload_ready=no\n'
    fail=1
fi

# init runs as root even with `user` set. Asserting the value rather than the
# absence of an error is the point: an exec that fails still leaves you guessing.
printf 'init_ran_as=%s\n' "$("$SMOLVM" machine exec --name "$NAME" --user root -- cat /init-ran-as.txt 2>&1 | tr -d '\r')"
printf 'exec_user=%s\n'   "$("$SMOLVM" machine exec --name "$NAME" -- id -un 2>&1 | tr -d '\r')"
printf 'workdir=%s\n'     "$("$SMOLVM" machine exec --name "$NAME" -- pwd 2>&1 | tr -d '\r')"

if [ "$fail" -eq 0 ]; then printf 'result=up\n'; else printf 'result=failed\n'; fi
exit "$fail"
```

### `scripts/verify-persistence.sh`

```bash
#!/usr/bin/env bash
# Prove the machine is worth keeping: that a package installed in one session is
# still there in the next, that init does not run again, and that the parts of
# the filesystem people assume persist actually do.
#
# usage: verify-persistence.sh [<name>]     (default smolskill-dev)
#
# Every check asserts a value. Asserting that an import did not crash proves
# nothing here: a system copy of the package satisfies it and tells you nothing
# about whether your install survived.

set -uo pipefail

NAME="${1:-smolskill-dev}"
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

# `start` returns before the workload container is up, and an `exec` in that
# window answers "the container `smolvm-<hash>` is not running" on stdout while
# still exiting zero. Wait for a VALUE: an empty result or a zero exit code both
# pass while the container is still coming up, which is how this window gets
# missed. Observed on a nested-virt aarch64 host, where a probe that asserted
# only an empty result let three later checks read that message as their answer.
wait_for_workload() {
    # 120 s: six times the slowest start observed while building this packet.
    # Long enough to absorb a loaded host, short enough to report a real hang.
    waited=0
    while [ "$waited" -lt 120 ]; do
        probe="$(exec_in sh -c 'echo WORKLOAD_READY')"
        if [ "$probe" = "WORKLOAD_READY" ]; then
            printf 'workload_ready_after_s=%s\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    printf 'workload_ready_after_s=timeout last_probe=%s\n' "$probe"
    return 1
}

if ! wait_for_workload; then
    printf 'result=FAILED (workload container never came up)\n'
    exit 1
fi

# 1. Install something and record its version, not its presence.
"$SMOLVM" machine exec --name "$NAME" -- pip install --quiet --user requests >/dev/null 2>&1
before="$(exec_in python3 -c 'import requests; print(requests.__version__)')"
printf 'installed_version=%s\n' "$before"

# 2. Seed one file per filesystem so the stop tells them apart.
# shellcheck disable=SC2016  # $HOME must expand inside the guest, not here
"$SMOLVM" machine exec --name "$NAME" -- sh -c 'echo SURVIVES > "$HOME/keep.txt"; echo GONE > /tmp/scratch.txt' >/dev/null 2>&1
"$SMOLVM" machine exec --name "$NAME" --user root -- sh -c 'mkdir -p /storage/keep && echo SURVIVES > /storage/keep/disk.txt' >/dev/null 2>&1

# 3. Stop and come back.
"$SMOLVM" machine stop --name "$NAME" >/dev/null 2>&1
restart_out="$("$SMOLVM" machine start --name "$NAME" 2>&1)"
printf '%s\n' "$restart_out" | sed 's/^/  /'

if ! wait_for_workload; then
    fail=1
fi

if printf '%s' "$restart_out" | grep -q 'Init already completed'; then
    check init_ran_once yes yes
else
    check init_ran_once no yes
fi

after="$(exec_in python3 -c 'import requests; print(requests.__version__)')"
check package_version "$after" "$before"

# shellcheck disable=SC2016  # same: the guest resolves $HOME
check home_file    "$(exec_in sh -c 'cat "$HOME/keep.txt" 2>/dev/null')" SURVIVES
check storage_file "$(exec_in cat /storage/keep/disk.txt)" SURVIVES

# /tmp is tmpfs and is wiped by a stop. Anything a provisioning step leaves
# there is gone on the next start, while the same step's writes to $HOME or /
# persist. This is the asymmetry that surprises people.
check tmp_file "$(exec_in sh -c 'cat /tmp/scratch.txt 2>/dev/null || echo WIPED')" WIPED

check exec_user "$(exec_in id -un)" app
check workdir   "$(exec_in pwd)" /app

if [ "$fail" -eq 0 ]; then printf 'result=persistent\n'; else printf 'result=FAILED\n'; fi
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

PACKET="dev-env"
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

## Persistent dev machine traps

### `init` runs once, not on every start

Observed on v1.14.2 on macOS arm64 and Linux aarch64: `init` runs on the **first `start`**, not
on `create`, and never again. The second start prints
`Init already completed, skipping N command(s)`.

**Anything that must be true on every boot does not belong in `init`.** The most common victim is
a bind mount: put `mount --bind ...` in `init` and the second boot comes up without it. Re-apply
it in the same command that needs it. The `docker-in-machine` packet is built around this.

**The CLI still says otherwise, and the docs no longer do.** `smolvm machine create --help` at
v1.18.2 describes `--init` as "Run command on every VM start", while `smolvm machine run --help`
has the corrected wording, so the two subcommands contradict each other in their own help output.
`introduction/concepts/smolfile.md` has since been corrected and carries a "When init runs"
heading stating that init runs once, on the first start, and that later starts skip it. Believe
the observed behaviour, which the docs now match and `machine create --help` does not.

`init` also runs **as root**, even with `user` set: `/init-ran-as.txt` contained `root` while
`exec` and `shell` ran as `app`. There is no `machine start --init` to force a re-run.

### `create` is not where the time goes, and not where failures appear

It is pure configuration and returns in milliseconds without touching the registry. The pull, the
init commands and any of their failures all land on the first `start`. Do not read a fast
`create` as evidence that anything works.

Two docs claims to ignore: `introduction/concepts/isolation-networking-credentials.md` says "a
persistent machine pulls once, when it is created". Observed: `create` pulls nothing.

### `exec` right after `start` can answer with a message instead of running

**If you see ``the container `smolvm-<hash>` is not running``**, the workload container is not up
and the exec did nothing. The hash differs between occurrences, because the container is being
relaunched.

**Why it happens.** Without a command, `machine create` launches the image's own ENTRYPOINT or CMD
as the persistent workload (`machine create --help`, `[COMMAND]`). For an interpreter image such
as `python:3.12-alpine` that command reads EOF from a stdin nobody is holding and exits at once,
so the container dies and is relaunched, and an `exec` can land in the gap.

Measured on a nested-virt aarch64 host on 2026-09-07, 20 execs each on a fresh machine and again
immediately after a restart:

| workload command | failures, fresh | failures, after restart |
|---|---|---|
| none (image CMD) | 1 in 20 | 1 in 20 |
| `sh -c 'while true; do sleep 3600; done'` | 0 in 20 | 0 in 20 |

**On v1.18.2**, 2026-09-24, the no-command row was 0 in 20 on macOS arm64 and 1 in 20 on Lima
aarch64, where it had been 0 in 20 on both on v1.16.1.

**The fix is to give the machine a workload that stays up**, which is what
`scripts/create-dev-machine.sh` does. There is no Smolfile key for it: pass it after `--` on
`machine create`.

**And this is why the readiness probe has to assert a value.** The message goes to stdout, so a
probe that waits for empty output or a zero exit code reports ready while the container is still
flapping, and the next three checks silently read that message as their answer. Both scripts here
wait for the exact string `WORKLOAD_READY`.

### A missing host mount source lets a machine start once and never restart

**If a machine created from a Smolfile starts fine and then never starts again**, check that every
host path in `volumes` exists. A Smolfile with `volumes = ["./src:/app"]` in a directory that has
no `./src` creates and starts once, and every later `start` fails with:

```
Error: agent operation failed: start machine: agent operation failed: wait for ready:
agent did not become ready within 30 seconds
```

which names neither the mount nor the missing directory, and reads exactly like host load.

Measured on macOS 26.6.2 arm64 on v1.14.3, 2026-09-08, three create-start-stop-start cycles each
with the workload confirmed ready before the stop:

| host mount source | restarts |
|---|---|
| `./src` exists | **3 of 3** |
| `./src` absent | **0 of 3** |

`scripts/create-dev-machine.sh` runs `mkdir -p ./src` before creating, which is why the packet's
own flow does not hit this. **Anything that writes its own Smolfile has to do the same.** A
relative path in `volumes` resolves against the working directory, so the same Smolfile run from
two directories can behave differently.

This one cost real time while writing this packet: an ad-hoc restart loop that omitted the
`mkdir -p` produced 0 of 5 and looked like a release regression until the two were compared
side by side.

### `machine shell` does not start a stopped machine, despite its own help

`smolvm machine --help` describes `shell` as "Open an interactive shell in a machine (starts it if
stopped)". It does not:

```
$ smolvm machine stop --name dev
$ smolvm machine shell --name dev
Error: agent operation failed: connect: machine 'dev' is not running.
       Use 'smolvm machine start --name dev' first.
```

Verified both through a pipe and under a real pty, so it is not a TTY-detection effect, and again
on v1.18.2. Start it explicitly first.

### A host `volumes` mount is not writable by a non-root `user`

With `volumes = ["./src:/app"]` and `user = "app"`, writing to `/app` fails with
`Operation not permitted`. The mount carries host ownership and the guest user does not match.
Read source in through the mount, write build output somewhere else, or run that step as root.

### `/tmp` is tmpfs and is wiped by a stop

Anything a provisioning step leaves in `/tmp` is gone on the next start, while the same step's
writes to `$HOME` or `/` persist. What survives, verified by writing one file per filesystem and
restarting:

| location | survives | why |
|---|---|---|
| pip `--user` packages | yes | under `$HOME`, on the overlay |
| `$HOME/...` files | yes | overlay |
| files written at `/` | yes | overlay |
| `/tmp` | **no** | `tmpfs` |
| `/storage/...` | yes | the ext4 disk itself |

Read from inside the guest, the mechanism is an overlay whose upper layer lives on the machine's
ext4 disk:

```
none on / type overlay (... upperdir=/storage/overlays/persistent-<name>/upper ...)
/dev/vda on /workspace type ext4 (rw,noatime)
/dev/vda on /storage   type ext4 (rw,noatime)
```

### `machine delete` prompts and defaults to No

Through v1.16.x a scripted delete without `--force` printed `Delete machine 'dev'? [y/N]
Cancelled`, exited 0 and left the machine in place while the script carried on. On v1.17.0 and
later it exits 1 with `needs confirmation but stdin is not a terminal; pass --force to delete it`.
Always pass `--force` in a script.

### A VPN inside the machine takes its gateway and resolver

A machine on virtio-net gets the link `100.96.0.0/30` by default, with the gateway and resolver at
`.1`. Tailscale and other carrier NAT VPNs claim `100.64.0.0/10`, which contains it, so once the
VPN is up inside the machine its gateway and resolver route into the VPN and every lookup fails.
The `sandbox` packet's traps have the measurement: with the routes Tailscale adds, the default link
gave `bad address 'example.com'` and `--guest-subnet 10.200.0.0/30` with the same routes resolved
and fetched, on v1.18.2 on both hosts.

For a dev machine the flag has three constraints, each observed on v1.18.2:

- **It is set at `create` only.** `machine update` has no `--guest-subnet`, so changing it means a
  new machine. It survives stop and start.
- **A Smolfile cannot carry it.** `[network]` accepts `allow_hosts`, `allow_cidrs` and
  `credentials`; pass `--guest-subnet` on `machine create` next to `-s`.
- **It implies `--net` and virtio-net**, and `machine ls --json` then reports `"network": false`
  for a machine that does reach the network, so do not read that field as the answer.

### Do not run two lifecycle commands against the same machine at once

Two overlapping `stop` and `shell` invocations left a `machine stop` unfinished for over two
minutes, against 0.14 s for a single `stop` on the same machine. That was self-inflicted rather
than a reproduced defect, but anything that fans out lifecycle calls should serialize them per
machine.

### Assert the package version, not that the import worked

An import can be satisfied by a system copy and tells you nothing about whether your install
survived the restart. `scripts/verify-persistence.sh` records the version before the stop and
compares it after.

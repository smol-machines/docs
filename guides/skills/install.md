---
title: "Install: set up smolvm and prove the host boots"
---

# Install: set up smolvm and prove the host boots

Installs smolvm from a published release and proves the host can actually boot a microVM before any other work starts. Use when setting smolvm up on a new machine, a CI runner or an agent sandbox; when a first boot fails with krun_start_enter -22, KVM_DENIED or "agent did not become ready"; when checking whether a host meets smolvm's requirements at all; or when an install has to be isolated from an existing one and then removed. Do not use it to remove an existing install (see the teardown packet) or for anything after the first boot has succeeded.

Verified on **smolvm v1.16.1** on macOS arm64, 2026-09-15, and on **v1.14.6** on Linux aarch64,
2026-09-10. Done means `smolvm --version` prints the release version **and** a throwaway VM has run
one command and exited. A version number alone proves nothing: on every
platform here there is at least one way for the install to succeed and every VM start to fail.

`scripts/preflight.sh` reports the host as `key=value` lines and ends with `result=ready` or
`result=blocked`. Run it first, and run it again after the install if the first boot fails.

## Procedure

**1. Preflight.** Read-only. It starts no VM and writes no smolvm state.

```bash
scripts/preflight.sh
```

Stop on `result=blocked` and read the `note=` lines. The two that block a fresh host are
`accel_access=denied` on Linux (your user cannot open `/dev/kvm`) and `socket_path_status=too_long`
on macOS (the install path is too deep for a VM's Unix socket). Both have a fix in
`references/traps.md`, and neither announces itself later: the installer warns about KVM and
continues, and the path limit surfaces as an error about disks.

**2. Install from the published release.**

```bash
curl -sSL https://smolmachines.com/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
smolvm --version
```

**Install the newest release.** The installer with no `--version` takes the latest published
release, and a later release is expected to work with this packet. The version in the banner above
is what the packet was last verified on, not what you should install. Pin only to reproduce a
recorded run:

```bash
curl -sSL https://smolmachines.com/install.sh | bash -s -- --version 1.16.1   # a recorded run
```

On macOS two `warning:` lines about notarization appear on every install and are not a problem.
On Linux `info: KVM access verified` appears only when your user can already open `/dev/kvm`.

To install without touching an existing one, point `HOME` at a scratch directory: every path
smolvm uses moves with it on macOS and Linux. Keep that directory shallow on macOS. This does not
work on Windows, where state cannot be relocated at all. See `references/layout.md`.

Windows does not use this installer. See `references/windows.md`.

**3. Prove it boots.** This is the step that decides whether smolvm works here.

```bash
scripts/verify-boot.sh
```

It runs one ephemeral alpine VM and asserts two values: a marker the guest printed, and that the
guest kernel is not the host's. On failure it prints the three misreadings that cost the most
time, before you clean up and lose the evidence.

**4. Clean up.**

```bash
scripts/cleanup.sh
```

It waits before asserting an empty machine list, because a successful `machine run` returns
before its entry retires and an immediate assertion fails on a healthy host. It then reports VM
processes an interrupt left behind, and kills them only with `--reap`.

## What the preflight reports

| key | meaning |
|---|---|
| `smolvm_installed`, `smolvm_version` | whether the binary is on `PATH` and what it says |
| `verified_version`, `version_status` | `match`, `newer`, `older` or `unknown` against the version this packet was last verified on. `newer` is the expected state on a current host and is not a failure |
| `platform` | `darwin-aarch64`, `linux-aarch64`, `linux-x86_64` |
| `accel`, `accel_access` | `hvf` and `kern.hv_support`, or `kvm` and whether `/dev/kvm` is readable and writable |
| `macos_version`, `hardware_verified` | `hardware_verified=no` on an Intel Mac: the installer accepts it and nothing here was run on one |
| `socket_path_bytes`, `socket_path_status` | macOS only, and the single most common cause of "macOS is broken" |
| `unsupported` | features this platform does not have |
| `result` | `ready` or `blocked` |

`version_status=newer` is a warning, not a failure. smolvm's flags and messages move every
release, so on a newer binary check each step's output against the binary before trusting the
text here.

## Security defaults, and why they are the defaults

- **The installer is a user-level install and needs no root.** Everything lands under `$HOME`,
  which is what lets an agent or a CI job install a private copy and remove it without a
  privileged step. Nothing in this packet escalates privilege.
- **`sudo usermod -aG kvm` is the one privileged step, and it is yours to run.** Group membership
  on `/dev/kvm` is the host's boundary between users who can start VMs and users who cannot, so a
  script should report `accel_access=denied` and stop rather than widen it for you. `sg kvm -c`
  then applies the group to a single command instead of your whole session.
- **The uninstaller leaves `~/.config/smolvm` and your `PATH` line on purpose.** Those hold
  registry credentials and a change you made to your own shell profile, so removing them is a
  separate, deliberate act. `references/layout.md` has both commands.

## Platform arms

- **macOS arm64**: verified. The path-length rule in `references/traps.md` applies to every install.
- **Linux aarch64 and x86_64**: verified. The `kvm` group check applies to every fresh host.
- **Intel Mac**: **unverified.** The installer accepts macOS 11 or later on Intel and nothing in
  the material behind this packet was run on one. `preflight.sh` reports `hardware_verified=no`
  there rather than implying it works.
- **Windows x86_64**: `references/windows.md`, **re-run on 2026-09-11 against v1.14.6** on
  Windows 11 Home build 10.0.26200.0 UBR 9445, where it confirmed. The
  three facts that break a Unix-shaped script are there: the zip unpacks into a nested versioned
  folder, state lives in `%LOCALAPPDATA%\smolvm` and cannot be moved, and a script must never
  capture `machine start` output because it never returns.

## Eval prompts, and what they produced

Run against this packet on 2026-09-07 PT, on smolvm v1.14.2 installed from the published release
into an isolated `HOME`. Output is verbatim.

**1. "Install smolvm on this machine and tell me whether it can actually run a VM."**

macOS 26.6.2 arm64:

```
smolvm_installed=yes
smolvm_version=1.14.2
version_status=match
platform=darwin-aarch64
accel=hvf
accel_access=ok
socket_path_bytes=62
socket_path_status=ok
result=ready

  BOOTED_OK
  Linux 6.12.95 aarch64
guest_ran=yes
guest_kernel=Linux 6.12.95
host_kernel=Darwin 25.6.0
is_a_vm=yes
result=boot_ok
```

Lima `linux-kvm`, Ubuntu 24.04 aarch64:

```
platform=linux-aarch64
accel=kvm
accel_access=ok
result=ready

  BOOTED_OK
  Linux 6.12.95 aarch64
guest_kernel=Linux 6.12.95
host_kernel=Linux 6.8.0-139-generic
is_a_vm=yes
result=boot_ok
```

Boot plus image pull took 8.9 s on macOS and 22.4 s on the nested-virt Linux box.

**2. "smolvm is installed but every `machine run` fails with `krun_start_enter returned: -22`.
What is wrong?"**

Reproduced deliberately on macOS by installing into a 49-character `HOME`. The preflight names
the cause before any VM is started:

```
socket_path_bytes=104
socket_path_status=too_long
note=HOME is too deep: every VM start will fail with krun_start_enter -22, whose text blames disks and device options. Install under a shorter HOME.
result=blocked
```

and the boot then fails exactly as reported, with the misleading text:

```
Error: agent operation failed: start machine: agent operation failed: monitor agent:
agent operation failed: start vm: krun_start_enter returned: -22 (EINVAL ... libkrun
rejected the VM configuration; usually a disk/overlay that could not be opened ... or an
unsupported device option) (boot process exited (code 1) before the agent was ready)
guest_ran=no
is_a_vm=no
result=boot_failed
```

**3. "Set up smolvm somewhere throwaway so it does not touch my existing install, then remove
it."**

Both isolated installs in this session ran under a scratch `HOME` and the uninstaller then
reported every path removed, with `find "$HOME" -iname '*smolvm*'` empty afterwards:

```
success: Removed <HOME>/.smolvm
success: Removed symlink <HOME>/.local/bin/smolvm
success: Removed data directory <HOME>/Library/Application Support/smolvm
success: Removed cache directory <HOME>/Library/Caches/smolvm
warning: You may want to remove the PATH entry from your shell profile.
success: smolvm has been uninstalled
```

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 from the published release, into a fresh isolated `HOME` on
macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64). Both hosts: `result=ready`, then
`guest_ran=yes`, `guest_kernel=Linux 6.12.95`, `is_a_vm=yes`, `result=boot_ok`, and a clean
cleanup. The guest kernel is unchanged across 1.14.2, 1.14.3 and 1.14.6.

## What was not run

- **Intel Mac.** Nothing.
- **Windows.** `references/windows.md` records a run on Windows 11 Home build 26200 that was not
  repeated here. No PowerShell script ships with this packet for that reason.
- **The unprivileged Windows symlink path.** The Windows preflight check for Developer Mode or
  `SeCreateSymbolicLinkPrivilege` is written from reading the release's extraction path and from a
  session that already held the privilege. The failure it guards against has been reported from
  outside and reproduced by forcing the state, but the unprivileged install itself has not been
  run by anyone here.
- **Linux x86_64** was verified for install and boot in the material behind this packet, on a
  cloud GPU instance that no longer exists. The scripts here were re-run on macOS arm64 and Linux
  aarch64 only.

## Related packets

- `teardown` for the full removal sequence, and for what a leak check must exclude.
- `sandbox` for running untrusted work in a throwaway machine, which assumes this boot.
- `dev-env`, `local-api`, `docker-in-machine`, `gpu-cuda` and `pack` all assume it too.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can install and boot smolvm. Read-only: starts no VM,
# writes no smolvm state, changes no group membership.
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.16.1"

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
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux. On Windows use references/windows.md, which is written from a run and not re-run by this packet."
        ;;
esac

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/verify-boot.sh`

```bash
#!/usr/bin/env bash
# Prove the install can actually boot a VM. This is the step that decides
# whether smolvm works here; `smolvm --version` printing a number does not.
#
# Runs one ephemeral alpine VM, asserts a marker the guest printed and that the
# guest kernel is not the host's, then hands off to cleanup.sh.

set -uo pipefail

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

host_kernel="$(uname -sr)"
marker="BOOTED_OK"

out="$("$SMOLVM" machine run --mem 2048 --net --image alpine -- \
      sh -c "echo $marker && uname -srm" 2>&1)"
printf '%s\n' "$out" | sed 's/^/  /'

fail=0

# Assert the marker, not the exit code. smolvm exits zero on paths where the
# guest never ran the command.
if printf '%s' "$out" | grep -q "^$marker$"; then
    printf 'guest_ran=yes\n'
else
    printf 'guest_ran=no\n'
    fail=1
fi

guest_kernel="$(printf '%s' "$out" | grep -m1 '^Linux ' | awk '{print $1" "$2}')"
printf 'guest_kernel=%s\n' "${guest_kernel:-none}"
printf 'host_kernel=%s\n' "$host_kernel"
if [ -n "$guest_kernel" ] && [ "$guest_kernel" != "$host_kernel" ]; then
    printf 'is_a_vm=yes\n'
else
    printf 'is_a_vm=no\n'
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    printf 'result=boot_ok\n'
else
    printf 'result=boot_failed\n'
    printf 'next: read the failure before cleaning up, because the evidence is deleted with the VM directory.\n'
    printf '  - "agent did not become ready within 30 seconds" is usually host load, not the install. The 30s limit is fixed and no flag raises it for machine run or machine start.\n'
    printf '  - "krun_start_enter returned: -22" on macOS is almost always the socket path length, not the disks its text names. Run preflight.sh and read socket_path_status.\n'
    printf '  - the boot child sends its own output to /dev/null. To see the real failure, copy <vm-dir>/boot-config.json while a start is in flight and run: smolvm-bin _boot-vm <copy>\n'
fi

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

PACKET="install"
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

## Install traps, and what each misleading message actually means

### `krun_start_enter returned: -22 (EINVAL ...)` on macOS

**It means your install path is too long.** The error text blames disks and device options and
is wholly misleading.

A VM's agent socket is `$HOME/Library/Caches/smolvm/vms/<16 hex>/agent.sock`. macOS
`sockaddr_un.sun_path` holds 104 bytes including the terminator, so once `$HOME` is deep enough
the socket path no longer fits and **every** VM start fails immediately. Measured by installing
into `$HOME` directories of increasing length:

| socket path bytes | result |
|---|---|
| 100 | boots |
| 102 | `-22` |
| 104 | `-22` |
| 106 | `-22` |

`scripts/preflight.sh` computes that path and reports `socket_path_bytes` and
`socket_path_status` before you install anything.

This is the single most expensive trap in the material behind this packet: it cost most of a
session and produced a false "macOS is broken" conclusion. Everything else was ruled out by
running it. The same release boots from a short `$HOME` on the same machine; v1.14.1, v1.13.0 and
v1.11.0 all fail identically at a long path, so it is not a regression; the installed binary
matches the tarball byte for byte; `kern.hv_support` is 1; and an ad-hoc-signed C program linking
the release's own `libkrun.dylib` runs a VM to completion and accepts smolvm's own `storage.raw`
and `overlay.raw`.

**A CI job or an agent harness that installs under a deep temporary directory will hit this and
will not be able to tell why.** Nothing in the README or the installer mentions a path-length
limit.

### `KVM_DENIED` on a fresh Linux box

**It means your user is not in the `kvm` group, and the install said nothing about it.** The
installer warns and then continues when `/dev/kvm` is inaccessible, so a successful install says
nothing about whether a VM will start. This was the out-of-the-box state on a fresh cloud GPU
instance.

The installer tells you to log out and back in. You do not have to:

```bash
sudo usermod -aG kvm "$USER"
sg kvm -c 'smolvm machine run --mem 2048 --net --image alpine -- echo OK'
```

`sg kvm -c '<command>'` (or `newgrp kvm`) applies the new group to a single command immediately,
which is what you want over SSH or inside a script.

### `agent did not become ready within 30 seconds`

**Suspect host load before you suspect the install.** This was reproduced on both macOS and a
nested-virt Linux box purely by running other VMs at the same time, and the identical command
passed on a quiet host seconds later.

The 30 s limit is a hard-coded constant (`src/agent/manager.rs`, `AGENT_READY_TIMEOUT`) and
**there is no flag or environment variable that raises it** for `machine run` or `machine start`.
`SMOLVM_AGENT_READY_TIMEOUT_SECS` exists but is read only by `pack run`.

### `machine list` shows your just-finished VM as `unreachable (eph)`

**Nothing is wrong.** The entry retires asynchronously after the run returns; observed gone by
20 s. A cleanup assertion that runs immediately after `machine run` fails on a healthy system,
which is why `scripts/cleanup.sh` waits before asserting.

### The boot subprocess hides its own errors

The child's stdout and stderr go to `/dev/null` unless `SMOLVM_BOOT_DEBUG=1`, and even that
showed nothing useful. To see the real failure, run the child yourself:

```bash
smolvm-bin _boot-vm <vm-dir>/boot-config.json
```

That is how the vCPU panics behind the macOS `-22` were finally read. **The child deletes its own
`boot-config.json` on exit**, so copy it while a start is in flight if you want to re-run it.
`RUST_LOG=debug` on the CLI shows the disk-template and boot timeline, which separates a template
problem from a hypervisor problem.

### `DYLD_PRINT_LIBRARIES` prints nothing on macOS

**Do not conclude anything from it.** `smolvm-bin` carries entitlements, so dyld strips `DYLD_*`
from its environment. The binary finds its libraries through `@executable_path/lib` regardless,
so the stripping is harmless and tells you nothing about a library problem.

### Two assertion habits that apply beyond install

- **Assert values, never exit codes.** A pack that lost its rootfs still boots and exits zero; a
  guest command that fails still returns HTTP 200 from the local API; a CUDA program can link and
  exit zero without ever reaching a GPU. `scripts/verify-boot.sh` asserts a marker the guest
  printed and that the guest kernel differs from the host's, for this reason.
- **Find leftover VMs by argv, not by `pgrep -f _boot-vm` and not by `readlink /proc/<pid>/exe`.**
  The pattern form matches any shell whose text contains that string, including the cleanup script
  itself, and it produced a phantom "1 orphan survived" result in the runs behind this packet.
  **The `/proc/<pid>/exe` route then fails for a different reason**: the VM process is not
  dumpable, so its `/proc/<pid>/exe` is root-owned and `readlink` returns `Permission denied` to
  the very user who started it, leaving a reaper that reports "no orphans" while an orphan runs.
  Both were observed on Ubuntu 24.04 aarch64 on 2026-09-07. `scripts/cleanup.sh` reads
  `/proc/<pid>/cmdline` and requires `argv[1]` to be exactly `_boot-vm`, which a shell cannot
  match, then keeps only the processes whose boot config lives under this `HOME`'s smolvm state so
  another session's VM is left alone. On macOS the same test runs over `ps -axo pid=,command=`.

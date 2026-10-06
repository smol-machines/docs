---
title: "Install: set up smolvm and prove the host boots"
---

# Install: set up smolvm and prove the host boots

Installs smolvm from a published release and proves the host can actually boot a microVM before any other work starts. Use when setting smolvm up on a new machine, a CI runner or an agent's own environment; when a first boot fails with krun_start_enter -22, KVM_DENIED or "agent did not become ready"; when checking whether a host meets smolvm's requirements at all; or when an install has to be isolated from an existing one and then removed. Do not use it to remove an existing install (see the teardown packet) or for anything after the first boot has succeeded.

Verified on **smolvm v1.23.0** on macOS arm64, 2026-10-04, and on **v1.18.2** on Linux aarch64, 2026-09-24. Done means `smolvm --version` prints the release version **and** a throwaway VM has run
one command and exited. A version number alone proves nothing: on every
platform here there is at least one way for the install to succeed and every VM start to fail.
The Linux runs used the scripts of their date; this version's preflight and cleanup scripts ran
on Linux aarch64 on v1.22.2 on 2026-10-03.

`scripts/preflight.sh` reports the host as `key=value` lines and ends with `result=ready`,
`result=not_installed` or `result=blocked`. Run it first, and run it again after the install if
the first boot fails.

## Procedure

**1. Preflight.** Read-only. It starts no VM and writes no smolvm state.

```bash
scripts/preflight.sh
```

`result=not_installed` on a fresh host means the host is fit and smolvm is simply missing: go on
to step 2 and run this again afterwards. With another smolvm first on `PATH`, it describes that one
instead and can end `result=ready`: read `smolvm_path=` and the `note=` before trusting it. Stop on `result=blocked` and read the `note=` lines. The
two that block a fresh host are
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

The installer writes under `$HOME` only: `~/.smolvm`, the launcher in `~/.local/bin`, and the
agent rootfs in `~/Library/Application Support/smolvm` on macOS or `~/.local/share/smolvm` on
Linux. When `~/.local/bin` is not already on `PATH` it appends a `# smolvm` `export PATH=...` line
to your shell profile (`~/.zshrc` for zsh); `--no-modify-path` skips that.

**Install the newest release.** The installer with no `--version` takes the latest published
release, and a later release is expected to work with this packet. The version in the banner above
is what the packet was last verified on, not what you should install. Pin only to reproduce a
recorded run:

```bash
curl -sSL https://smolmachines.com/install.sh | bash -s -- --version 1.23.0   # a recorded run
```

On macOS two `warning:` lines about notarization appear on every install and are not a problem.
On Linux `info: KVM access verified` appears only when your user can already open `/dev/kvm`.

To install without touching an existing one, point `HOME` at a scratch directory: every path
smolvm uses moves with it on macOS, and on Linux once `XDG_DATA_HOME` and `XDG_CACHE_HOME` are
unset, since both outrank `HOME` there. Keep that directory shallow on macOS. This does not work on
Windows, where state cannot be relocated at all. See `references/layout.md`.

Windows does not use this installer. See `references/windows.md`.

**3. Prove it boots.** This is the step that decides whether smolvm works here.

```bash
scripts/verify-boot.sh
```

It runs one ephemeral alpine VM and asserts two values: a marker the guest printed, and that the
guest kernel is not the host's. `--image <ref>` boots another image; when Docker Hub answers
`TOOMANYREQUESTS`, its anonymous pull limit, name the same image from a mirror,
`scripts/verify-boot.sh --image mirror.gcr.io/library/alpine` or
`public.ecr.aws/docker/library/alpine`, and the step tells you so when it sees that error. On
failure it prints the three misreadings that cost the most time, before you clean up and lose the
evidence.

It boots a 2048 MiB guest, and a machine you create without `--mem` asks for 8192. A host can pass
this step and still fail every default-size machine with `agent did not become ready within 30
seconds`; if your work uses the default, boot one at that size too. `references/traps.md` has the
measurement. From v1.22.0 the first run of each registry image also starts a seed helper at 8192
MiB whatever `--mem` says. When that helper cannot start the run prints
`WARN no image seed; pulling in the guest` and goes on: after the helper's 30 s timeout on a host
that cannot boot 8192 MiB, or at once when the helper's own pull is refused, as it is under the rate
limit.

**4. Clean up.**

```bash
scripts/cleanup.sh
```

It waits up to 20 seconds, polling the machine list and printing `waiting=up to 20s` first,
before asserting an empty machine list, because a successful `machine run` returns before its
entry retires and an immediate assertion fails on a healthy host. It then reports VM processes
left under this `HOME`, and `--reap` kills every one of them, a running machine you meant to keep
included, so read the plain report first.

## What the preflight reports

| key | meaning |
|---|---|
| `smolvm_installed`, `smolvm_path`, `smolvm_version` | whether the binary is on `PATH`, which one, and what it says; a `note=` when that binary is not under the `HOME` being checked |
| `verified_version`, `version_status` | `match`, `newer`, `older` or `unknown` against the version this packet was last verified on. `newer` is the expected state on a current host and is not a failure |
| `platform` | `darwin-aarch64`, `linux-aarch64`, `linux-x86_64` |
| `accel`, `accel_access` | `hvf` and `kern.hv_support`, or `kvm` and whether `/dev/kvm` is readable and writable |
| `macos_version`, `hardware_verified` | `hardware_verified=no` and `result=blocked` on an Intel Mac: no `darwin-x86_64` archive is published for v1.23.0 |
| `socket_path_bytes`, `socket_path_status` | macOS only, and the single most common cause of "macOS is broken" |
| `unsupported` | features this platform does not have |
| `result` | `ready`, `not_installed` (the host is fit and smolvm is missing) or `blocked` |

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

- **macOS arm64**: verified on v1.23.0. The path-length rule in `references/traps.md` applies to
  every install.
- **Linux aarch64**: verified on v1.18.2, and run once on v1.22.2. **Linux x86_64**: verified on
  v1.14.2, and installed on v1.14.6 for the gpu-cuda run. The `kvm` group check applies to every
  fresh host.
- **Intel Mac**: the installer accepts macOS 11 or later on Intel and then stops at the download,
  because no `darwin-x86_64` archive is published for v1.23.0; `preflight.sh` says so.
- **Windows x86_64**: `references/windows.md`, **re-run on 2026-10-03 against v1.22.2** on
  Windows 11 Home build 10.0.26200 UBR 9457, where it confirmed. The
  three facts that break a Unix-shaped script are there: the zip unpacks into a nested versioned
  folder, state lives in `%LOCALAPPDATA%\smolvm` and cannot be moved, and a script must never
  capture `machine start` output because it never returns.

## Eval prompts, and what they produced

**1. "Install smolvm on this machine and tell me whether it can actually run a VM."** On macOS
arm64 on v1.23.0: `result=not_installed`, the install, then `result=ready`, `guest_ran=yes`,
`guest_kernel=Linux 6.12.95`, `is_a_vm=yes`, `result=boot_ok`.

**2. "smolvm is installed but every `machine run` fails with `krun_start_enter returned: -22`.
What is wrong?"** Reproduced on macOS on v1.22.2 by installing into a 52-character `HOME`. The
preflight names the cause before any VM is started:

```
socket_path_bytes=106
socket_path_status=too_long
result=blocked
```

and the boot then fails with `krun_start_enter returned: -22 (EINVAL ...)`, whose text blames
disks and device options.

**3. "Set up smolvm somewhere throwaway so it does not touch my existing install, then remove
it."** Install under a scratch `HOME`, then `install.sh --uninstall`; on v1.22.2 it printed
`success: smolvm has been uninstalled`, and `find "$HOME" -iname '*smolvm*'` was empty afterwards.

## Re-verified on v1.23.0

Run 2026-10-04 PT against v1.23.0 from the published release, checksum checked, under a fresh
isolated `HOME` on macOS 27.0.1 arm64, once. On Lima `linux-kvm` (Ubuntu 24.04 aarch64) the
checks named below ran once, so the Linux stamp stays on its earlier release.

macOS: `result=not_installed` on the empty `HOME`; the installer with no `--version` printed
`Installing version: 1.23.0` and `Checksum verified`, and the pinned command above did the same.
Then `version_status=match`, `result=ready`, `guest_kernel=Linux 6.12.95`, `result=boot_ok` in
15 s and a clean cleanup, 23 s for the whole packet. Eval 2 repeated in a 52-character `HOME`:
`socket_path_bytes=106`, `socket_path_status=too_long`, `result=blocked`, and the boot failed with
the same `-22` text, printed twice. Eval 3 repeated: after an install, one boot and
`--uninstall`, `find` printed nothing.

Linux aarch64: `result=not_installed`, the installer took 1.23.0 with `Checksum verified`, then
`version_status=match` and `result=ready`. A first boot at 1024 MiB took 33 s and one at 2048 MiB
9 s.

## Re-verified on v1.22.2

Run 2026-10-03 PT against v1.22.2 from the published release, checksum checked, under an isolated
`HOME` on macOS 27.0.1 arm64, twice, the second time from a fresh `HOME`. On Lima `linux-kvm`
(Ubuntu 24.04 aarch64) on 2026-10-03 guests above 2048 MiB timed out, so the Linux lines below are
a single run and the Linux stamp stays on its earlier release.

macOS: `result=not_installed` on the empty `HOME`, the installer took the newest release,
`smolvm 1.22.2`, then `result=ready`, `guest_kernel=Linux 6.12.95`, `result=boot_ok` and a clean
cleanup, 41 s for the whole packet. The path trap repeated: a 52 byte `HOME` gave
`socket_path_bytes=106`, `socket_path_status=too_long`, and the boot failed with the same `-22`
text, printed twice because the image seed helper fails first. A default-size machine booted in
under a second once the image was seeded.

Linux aarch64: `result=boot_ok` in 87 s at 2048 MiB, after the seed helper's 30 s timeout and
`WARN no image seed; pulling in the guest`; the readiness trap has the measurement. Linux was last
verified on v1.18.2.

## What was not run

- **Intel Mac.** Nothing.
- **Windows through a script.** The v1.22.2 run on Windows issued the commands on
  `references/windows.md` by hand, and no PowerShell script ships with this packet.
- **The unprivileged Windows symlink path.** The Windows preflight check for Developer Mode or
  `SeCreateSymbolicLinkPrivilege` is written from reading the release's extraction path and from a
  Windows run whose account already held the privilege. The failure it guards against has been
  reported from outside and reproduced by forcing the state, but the unprivileged install itself
  has not been run.
- **Linux x86_64** was verified for install and boot on v1.14.2, and installed on v1.14.6 for the
  gpu-cuda run. The scripts here were re-run on macOS arm64 and Linux aarch64 only.

## Related packets

- `teardown` for the full removal sequence, and for what a leak check must exclude.
- `throwaway-machine` for running untrusted work in a throwaway machine, which assumes this boot.
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
# always result=ready, result=not_installed or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.23.0"

emit() { printf '%s=%s\n' "$1" "$2"; }

blocked=0
note() { printf 'note=%s\n' "$1"; }

# --- the binary --------------------------------------------------------------

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
missing=0
if [ -z "$SMOLVM" ]; then
    emit smolvm_installed no
    emit smolvm_version ""
    missing=1
else
    emit smolvm_installed yes
    emit smolvm_path "$SMOLVM"
    version="$("$SMOLVM" --version 2>/dev/null | awk '{print $NF}')"
    emit smolvm_version "${version:-unknown}"
    # A HOME set aside for a test install still finds whatever smolvm is first on
    # PATH, so say when that binary belongs to another HOME.
    case "$SMOLVM" in
        "$HOME"/*) ;;
        *) note "the smolvm on PATH, $SMOLVM, is not under this HOME ($HOME); the lines below describe that binary, not an install in this HOME. Put \$HOME/.local/bin first on PATH, or set SMOLVM, to check the one you mean" ;;
    esac
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
            blocked=1
            note "no darwin-x86_64 archive is published for v1.23.0, so the installer accepts an Intel Mac and then stops at the download"
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
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux. On Windows use references/windows.md, run there by hand on v1.22.2."
        ;;
esac

# Not installed yet is not a fault of the host, and reading it as one stopped a
# first install that had nothing wrong with it.
if [ "$blocked" -ne 0 ]; then
    emit result blocked
elif [ "$missing" -ne 0 ]; then
    note "smolvm is not installed yet and nothing else blocks this host: install it (step 2), then run this again"
    emit result not_installed
else
    emit result ready
fi
```

### `scripts/verify-boot.sh`

```bash
#!/usr/bin/env bash
# Prove the install can actually boot a VM. This is the step that decides
# whether smolvm works here; `smolvm --version` printing a number does not.
#
# Runs one ephemeral alpine VM and asserts a marker the guest printed and that
# the guest kernel is not the host's. Run cleanup.sh afterwards.
#
# usage: verify-boot.sh [--image <ref>]   (default alpine)
#   --image <ref>  the image to boot, for example mirror.gcr.io/library/alpine
#                  or public.ecr.aws/docker/library/alpine when Docker Hub
#                  refuses with TOOMANYREQUESTS

set -uo pipefail

IMAGE="alpine"
while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

host_kernel="$(uname -sr)"
marker="BOOTED_OK"

out="$("$SMOLVM" machine run --mem 2048 --net --image "$IMAGE" -- \
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
    if printf '%s' "$out" | grep -q 'TOOMANYREQUESTS'; then
        printf '  - "TOOMANYREQUESTS" is Docker Hub refusing anonymous pulls from this address, not the install. Boot the same image from a mirror: verify-boot.sh --image mirror.gcr.io/library/alpine, or public.ecr.aws/docker/library/alpine.\n'
    fi
    printf '  - "agent did not become ready within 30 seconds" is usually host load or a guest too large for this host, not the install. The 30s limit is fixed and no flag raises it for machine run or machine start; retry with a smaller --mem to tell the two apart.\n'
    printf '  - "krun_start_enter returned: -22" on macOS is almost always the socket path length, not the disks its text names. Run preflight.sh and read socket_path_status.\n'
    printf '  - the boot child sends its own output to /dev/null. To see the real failure, copy <vm-dir>/boot-config.json in a loop while a start is in flight (the child deletes it as soon as it reads it) and run: smolvm-bin _boot-vm <copy>\n'
fi

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

## Install traps, and what each message actually means

### `krun_start_enter returned: -22 (EINVAL ...)` on macOS

**It means your install path is too long.** The error text names disks and device options; the
cause is the path length. The one other cause is a binary that lost its hypervisor entitlement by being
re-signed or built locally; [known limitations](https://github.com/smol-machines/smolvm/blob/main/docs/limitations.md) has the fix for that, and the
release binary the installer lays down has it.

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

Of the traps here this one took longest to diagnose, and it was first concluded to be "macOS is
broken". Everything else was ruled out by running it. The same release boots from a short `$HOME`
on the same machine; v1.14.1, v1.13.0 and v1.11.0 all fail identically at a long path, so it is
not a regression; the installed binary matches the tarball byte for byte; `kern.hv_support` is 1;
and an ad-hoc-signed C program linking the release's own `libkrun.dylib` runs a VM to completion
and accepts smolvm's own `storage.raw` and `overlay.raw`.

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
nested-virt Linux host purely by running other VMs at the same time, and the identical command
passed on a quiet host seconds later.

**Then suspect the guest's size.** A host that is slow to fault in guest memory can boot a small
guest and time out on a large one, and the message is the same. Measured on Lima `linux-kvm`
(Ubuntu 24.04 aarch64, nested virtualisation on a 16 GiB Mac that was paging), 2026-09-24:

| `--mem` | v1.18.2 | v1.16.1 |
|---|---|---|
| 512, 1024 | booted, about 14 s | not run |
| 2048 | booted, 33 s | booted, 36 s |
| 2560 to 8192 | `agent did not become ready within 30 seconds` | the same at 4096 and 8192 |

The default is 8192, so on such a host `machine create` without `--mem` gives a machine that never
starts, while `scripts/verify-boot.sh` at 2048 passes. Bisect on `--mem` before designing around
it: the same host booted 8192 on v1.14.6 on 2026-09-10, when its host was not paging.

**From v1.22.0 a first boot can wait out that timeout before it starts.** The first run of each
registry image builds a shared seed of it in a helper machine, `image-seed-<hash>-<pid>`, which
boots at 8192 MiB whatever `--mem` asks for. On Lima `linux-kvm` on 2026-10-03, which booted 2048
and timed out at 4096 and 8192, `scripts/verify-boot.sh` printed
`WARN no image seed; pulling in the guest ... agent did not become ready within 30 seconds`, fell
back to pulling inside its own 2048 MiB guest, and passed in 87 s. On a host that boots 8192 the
seed is built once and later runs of that image start in about a second.

The 30 s limit is a hard-coded constant (`src/agent/manager.rs`, `AGENT_READY_TIMEOUT`) and
**there is no flag or environment variable that raises it** for `machine run` or `machine start`.
`SMOLVM_AGENT_READY_TIMEOUT_SECS` exists but is read only by `pack run`.

### `TOOMANYREQUESTS` from `crane manifest`

**It means Docker Hub has refused this address's anonymous pulls, not that the install is broken.**
The guest pulls with `crane`, and a pull of `alpine` by its short name then fails as
`fetching manifest docker.io/library/alpine:latest: ... TOOMANYREQUESTS: You have reached your
unauthenticated pull rate limit`, at once and before any timeout. Name the same image from a
mirror, `mirror.gcr.io/library/alpine` or `public.ecr.aws/docker/library/alpine`, as
`scripts/verify-boot.sh --image` does.

To see the remaining count before a run, ask the endpoint the guest uses, `index.docker.io`, with
a `HEAD` request, which does not count against it:

```bash
T=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/alpine:pull" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -s --head -H "Authorization: Bearer $T" https://index.docker.io/v2/library/alpine/manifests/latest | grep -i ratelimit-remaining
```

On 2026-10-03 this answered `0` while the same request to `registry-1.docker.io` still answered
`63`, so ask `index.docker.io`. Setting a registry `mirror` for `docker.io` in
`~/.config/smolvm/config.toml` is not a substitute on v1.22.2: every run then ended with
`run command: image not found: docker.io/library/<image>`.

### `machine list` shows your just-finished VM as `unreachable (eph)`

**Nothing is wrong.** The entry retires asynchronously after the run returns; observed gone by
20 s. On v1.22.2 it was already gone when `machine list` ran straight after the run, 4 of 4 on
macOS arm64; the wait stays for the releases that need it. A cleanup assertion that runs immediately after `machine run` fails on a healthy system,
which is why `scripts/cleanup.sh` waits before asserting.

### The boot subprocess hides its own errors

The child's stdout and stderr go to `/dev/null` unless `SMOLVM_BOOT_DEBUG=1`, and even that
showed nothing useful. To see the real failure, run the child yourself:

```bash
smolvm-bin _boot-vm <vm-dir>/boot-config.json
```

That is how the vCPU panics behind the macOS `-22` were read. **The child deletes its own
`boot-config.json` as soon as it has read it**, before the VM starts, so a copy has to be taken in
the moment between the CLI writing it and the child reading it: loop on `cp` while you start the
machine.
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
- **Find leftover VMs by the process name, not by `pgrep -f _boot-vm` and not by `readlink
  /proc/<pid>/exe`.** The pattern form matches any shell whose text contains that string, including
  the cleanup script itself, and it produced a phantom "1 orphan survived" result.
  **The `/proc/<pid>/exe` route then fails for a different reason**: the VM process is not
  dumpable, so its `/proc/<pid>/exe` is root-owned and `readlink` returns `Permission denied` to
  the very user who started it, leaving a reaper that reports "no orphans" while an orphan runs.
  Both were observed on Ubuntu 24.04 aarch64 on 2026-09-07. `scripts/cleanup.sh` matches the VM
  process's name in `/proc/<pid>/comm` (`libkrun VM`, or `VM:<hostname>` when `HOSTNAME` is
  exported), which a shell cannot hold, then keeps only those whose boot config lives under this
  `HOME`'s smolvm state, or whose executable is under the install prefix, so another session's VM
  is left alone. On macOS it scopes by the executable path under the prefix and the parent chain
  over `ps -axo pid=,ppid=,command=`.

---
title: "Teardown: stop everything and remove smolvm's state"
---

# Teardown: stop everything and remove smolvm's state

Stops every smolvm machine a session started, removes smolvm's state, and proves the host is clean. Use after any smolvm session; when a machine seems to have survived a Ctrl-C or a crash; when disk space has disappeared; when uninstalling smolvm; when tearing down the Kubernetes runtime from a node; or when a borrowed or shared host has to be handed back with nothing left behind. Also use it as the cleanup step for other smolvm work, because the obvious assertions here give false results. Do not use it to delete machines another session created: it removes only what a script recorded under its own name prefix.

Verified on **smolvm v1.16.1** on macOS arm64, 2026-09-15, and on **v1.14.6** on Linux aarch64,
2026-09-10. This packet exists on its own because **almost every cleanup fact
in smolvm is counterintuitive**: the obvious assertion gives a false failure, the obvious reaper
matches the wrong process or nothing at all, and the command a user reaches for when a run
misbehaves does not stop the machine. Anything that starts machines needs this more than it needs
any single feature.

Every other packet's cleanup script is this packet's `scripts/cleanup.sh` with one line changed.

## Procedure

**1. See what is there.** Read-only: deletes nothing, starts no VM.

```bash
scripts/preflight.sh
```

It reports each state directory with its size, whether a `--oci-cache` image store exists,
whether the launcher symlink and the `PATH` block are present, and whether state can be relocated
on this platform.

**2. Delete the machines your scripts created, and report the rest.**

```bash
scripts/cleanup.sh            # report leftover VM processes
scripts/cleanup.sh --reap     # and kill them
```

Only machines recorded in the state file are deleted, so a machine you or another session created
by hand is never touched. A script records what it creates with
`scripts/cleanup.sh --record <name>`, and names must carry the `smolskill-` prefix or the delete
is skipped. `--purge` removes the state file once the list is empty.

The state file lives under `${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills/`, outside
`~/.smolvm` and outside smolvm's own caches. Nothing here edits smolvm configuration.

**3. Prove it.**

```bash
scripts/verify-clean.sh
scripts/verify-clean.sh --protected "$HOME/.smolvm"   # after a run under an isolated HOME
```

**Every check here is scoped to the `HOME` it runs under**, and the `audited_home=` line says
which profile the result describes. Run it under a different `HOME` and it reports a clean host no
matter what is running elsewhere: an agent that hit `machines=FAIL` did exactly that, re-ran the
script under a fresh `mktemp -d`, got `result=clean`, and reported the host clean while a VM was
still running.

Each check prints `ok` or `FAIL expected=... actual=...`, and the script exits non-zero if any
failed. `--protected <dir>` asserts nothing under a real installation was written today, which is
how you show a test run under a scratch `HOME` did not reach it. Without it the check reports
`protected=not_checked` rather than passing silently.

**4. Reclaim space, or remove smolvm entirely.**

```bash
smolvm machine prune --name <NAME>   # one machine's unreferenced layers; --all drops its cached images
smolvm pack prune
curl -sSL https://smolmachines.com/install.sh | bash -s -- --uninstall
```

`references/locations.md` has the full layout, what the uninstaller removes, and the two things it
deliberately leaves.

## The four traps that make this a packet

Full detail with the observations behind each is in `references/traps.md`.

- **`Ctrl-C` does not stop the machine. On v1.14.x there was no CLI route to what it left; on
  v1.16.x there is.** The VM still outlives the CLI, and it still exits only when its own workload
  finishes, so a run that loops or hangs is unbounded exposure. What changed is visibility.
  Measured on macOS arm64 on v1.16.1, 2026-09-15: killing the **wrapper** and leaving the CLI
  reparented to PID 1 leaves the pair running and `machine list` shows it as
  `vm-12175b4a running (eph)`, and `smolvm machine stop --name vm-12175b4a` then stops it and both
  processes go. Killing the **CLI** itself took the VM with it: `No machines found`, no processes.
  **The reaper's remaining case is a VM process whose `machine list` entry is absent**, which
  neither of those two routes produced on v1.16.1; it is now a backstop rather than the only route.
  The transcripts recorded below are from v1.14.x, where the entry was never shown.
- **The two obvious reapers both fail, in opposite directions.** `pgrep -f _boot-vm` matches any
  shell whose text contains that string, including the cleanup script, and reports orphans that do
  not exist. `readlink /proc/<pid>/exe` reports none that do: the VM process is not dumpable, so
  its `/proc/<pid>/exe` is root-owned and `readlink` returns `Permission denied` to the user who
  started it. `cleanup.sh` matches `argv[1]` exactly instead, and scopes by the boot config's path.
- **Asserting "no machines" immediately after `machine run` fails on a healthy host.** The entry
  retires after the command returns, observed gone by 20 s.
- **`machine delete` prompts and defaults to No.** Without `--force` a script prints `Cancelled`
  and carries on believing it cleaned up. A branched machine also needs `--cascade`.

And one false alarm: **`ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check.** Once `--oci-cache`
has run, `_shared` lives there holding the baked images. Both scripts exclude it.

## Security defaults, and why they are the defaults

- **Cleanup deletes only what it was told it created.** A shared host can carry another session's
  machines, and during the runs behind this packet it did: a second VM under a different `HOME`
  was live throughout. `cleanup.sh` listed only the processes whose boot config sits under its own
  state tree and left the other one running. A cleanup script that kills every smolvm process is
  fine on your laptop and destructive on a build agent.
- **`--reap` is opt-in and prints what it is about to kill.** Killing a VM is not recoverable and
  the VM cannot be identified from `machine list`, so the default is to report.
- **Nothing here escalates privilege.** The one place teardown needs `sudo` is the Kubernetes
  runtime, which installs outside your home directory; those commands are in
  `references/kubernetes.md` for you to run and read, not wrapped in a script.
- **The uninstaller leaves `~/.config/smolvm` and your `PATH` line on purpose**, because those
  hold registry credentials and a change you made to your own shell profile.

## Platform arms

- **macOS arm64** and **Linux aarch64**: the scripts were run here.
- **Linux x86_64**: the procedure was verified in the material behind this packet, on hosts that
  no longer exist. The scripts themselves were not re-run there.
- **Windows x86_64**: `references/windows.md`, **not re-run**, including by the 2026-09-11 batch
  on v1.14.6, so that page stays a v1.14.2 record. The scripts are POSIX shell and do
  not run there at all. Windows is the platform where this matters most, because state cannot be
  relocated and one session left 30 GB in `%LOCALAPPDATA%\smolvm`.
- **Kubernetes nodes**: `references/kubernetes.md`. Verified on Ubuntu 22.04 x86_64 with k3s in
  the material behind this packet, not re-run here.

## Eval prompts, and what they produced

Run on 2026-09-07 PT against smolvm v1.14.2 from the published release, under an isolated `HOME`
on macOS 26.6.2 arm64 and on Lima `linux-kvm` (Ubuntu 24.04 aarch64). Output is verbatim.

**1. "I ran some smolvm machines. Clean up after me and show me the host is clean."**

A machine was created, started, recorded, then cleaned up. macOS:

```
  Cleaning up data directory for vm: smolskill-td
  Deleted machine: smolskill-td
machines=clean
vm_processes=none

machines=ok
vm_dirs=ok
vm_processes=ok
protected_untouched_since_2026-09-07=ok
result=clean
```

Linux gave the same, with `protected=not_checked` because no real installation was named.

**2. "Is anything still running that `smolvm machine list` cannot see?"**

**The expected answer changed with v1.16.x, and the transcripts below are v1.14.x.** On v1.16.1 an
interrupted run stays in `machine list` as `running (eph)`, so the honest answer to this question
is now "nothing that the list cannot see; here is what it does show, and `machine stop --name`
clears it". The reaper is still worth running, because it names the process pair and the boot
config path, and because a process whose list entry is absent would not be found any other way.
Re-measured on macOS arm64 on v1.16.1, 2026-09-15.

Run against a live machine on v1.14.x, so this is the answer when the host is not clean. Linux:

```
vm_process=51706 config=/home/<user>/skp/.cache/smolvm/vms/2ec3433ec42ca6de/boot-config.json
rerun with --reap to kill them
```

macOS:

```
vm_process=76032 config=/tmp/skp/Library/Caches/smolvm/vms/2ec3433ec42ca6de/boot-config.json
```

A second VM belonging to another session was live on the Linux host under a different `HOME`
throughout, and was correctly not listed. The same run through `readlink /proc/<pid>/exe`
returned nothing at all, which is the finding that changed this script.

**3. "Prove my test run did not touch my real smolvm install."**

```
machines=ok
vm_dirs=ok
vm_processes=ok
protected_untouched_since_2026-09-07=ok
result=clean
```

against `--protected $HOME/.smolvm` on the macOS host, where a real v0.5.20 installation sits
beside the isolated v1.14.2 one used for these runs.

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 on macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04
aarch64). `verify-clean.sh` returned `result=clean` on both, including
`protected_untouched_since_2026-09-10=ok` against the real installation on the Mac.

**The reaper changed on this release**, and the change is the reason to read
`references/traps.md` again: the pack-run path forks without execing, so its VM child carries no
`_boot-vm` in argv and the previous scanner could not see it. Measured on v1.14.6 before the fix,
`cleanup.sh` reported `vm_processes=none` and `result=clean` while two orphaned VMs held 234 MB
each. The scanner now matches both process shapes and was verified against a live orphan on both
hosts.

## What was not run

- **Windows.** `references/windows.md` records one run that was not repeated.
- **Kubernetes.** `references/kubernetes.md` records a verified sequence on a node that no longer
  exists.
- **Linux x86_64.**
- **The macOS `hdiutil` mount-point case.** `references/traps.md` records that `rm -rf` on the
  pack cache can fail with `Resource busy` and what the uninstaller does about it. No pack was
  created in these runs, so that path was not exercised here.
- **`--oci-cache`.** No `_shared` store existed on either host, so the exclusion these scripts
  carry was exercised only against its absence.

## Related packets

- `install` for what the install lays down, which is what you are removing.
- Every other packet's `scripts/cleanup.sh` is this one.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report what smolvm state exists on this host, so you know what teardown has to
# remove before you remove it. Read-only: deletes nothing, starts no VM.
#
# Output is one key=value per line. The last line is always result=ready or
# result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.14.6"

emit() { printf '%s=%s\n' "$1" "$2"; }
note() { printf 'note=%s\n' "$1"; }

blocked=0

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    emit smolvm_installed no
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
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; check each path below still exists before trusting a removal step"
        else
            emit version_status older
        fi
    fi
else
    emit version_status unknown
fi

kernel="$(uname -s)"
arch="$(uname -m)"
case "$arch" in aarch64|arm64) arch=aarch64 ;; esac

case "$kernel" in
    Darwin)
        emit platform "darwin-$arch"
        emit accel hvf
        if [ "$(sysctl -n kern.hv_support 2>/dev/null)" = "1" ]; then emit accel_access ok; else emit accel_access denied; fi
        data_dir="$HOME/Library/Application Support/smolvm"
        cache_dir="$HOME/Library/Caches/smolvm"
        pack_dir="$HOME/Library/Caches/smolvm-pack"
        libs_dir="$HOME/Library/Caches/smolvm-libs"
        emit unsupported "vulkan,cuda"
        # There is no SMOLVM_DATA_DIR on macOS (it is Linux-only), but every path
        # below is derived from HOME, so an install under a scratch HOME is
        # self-contained. Windows is the platform where neither route works.
        emit state_relocatable via_home
        ;;
    Linux)
        emit platform "linux-$arch"
        emit accel kvm
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then emit accel_access ok; else emit accel_access denied; fi
        data_dir="$HOME/.local/share/smolvm"
        cache_dir="$HOME/.cache/smolvm"
        pack_dir="$HOME/.cache/smolvm-pack"
        libs_dir="$HOME/.cache/smolvm-libs"
        emit unsupported "vulkan"
        emit state_relocatable via_home_or_data_dir
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux. The Windows removal sequence is references/windows.md and was not re-run by this packet."
        exit_now=1
        ;;
esac

if [ "${exit_now:-0}" = "1" ]; then
    emit result blocked
    exit 0
fi

report_dir() {
    if [ -d "$2" ]; then
        emit "$1" "$(du -sk "$2" 2>/dev/null | awk '{printf "%d", $1/1024}')MB"
    else
        emit "$1" absent
    fi
}

report_dir install_prefix "$HOME/.smolvm"
report_dir agent_rootfs   "$data_dir"
report_dir vm_state       "$cache_dir"
report_dir pack_cache     "$pack_dir"
report_dir packed_libs    "$libs_dir"
report_dir credentials    "$HOME/.config/smolvm"

if [ -L "$HOME/.local/bin/smolvm" ]; then emit launcher_symlink present; else emit launcher_symlink absent; fi

# `_shared` is the image store --oci-cache bakes into. It is the cache, not
# residue, so counting it as a leak gives a false positive.
if [ -d "$cache_dir/vms" ]; then
    total="$(find "$cache_dir/vms" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    shared=0
    [ -d "$cache_dir/vms/_shared" ] && shared=1
    emit vm_dirs "$((total - shared))"
    if [ "$shared" = 1 ]; then emit oci_cache_present yes; else emit oci_cache_present no; fi
else
    emit vm_dirs 0
    emit oci_cache_present no
fi

if grep -rqs 'smolvm' "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile" 2>/dev/null; then
    emit path_block present
    note "the uninstaller deliberately leaves the PATH block and \$HOME/.config/smolvm; remove them by hand if you want them gone"
else
    emit path_block absent
fi

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
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

PACKET="teardown"
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

### `scripts/verify-clean.sh`

```bash
#!/usr/bin/env bash
# Prove the host is clean after a teardown. Every check asserts a value rather
# than an exit code, because the commands teardown runs report success while
# leaving state behind.
#
# usage: verify-clean.sh [--protected <dir>] [--since <date>]
#   --protected <dir>  assert nothing under <dir> was written on or after --since.
#                      Point it at a real installation you ran beside: that is how
#                      you show a test under an isolated HOME did not reach it.
#                      Omitted, the check is reported as not run rather than passed.
#   --since <date>     the cutoff for --protected (default: today)

set -uo pipefail

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
since="$(date +%F)"
protected=""
while [ $# -gt 0 ]; do
    case "$1" in
        --protected) protected="$2"; shift ;;
        --since)     since="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf '%s=ok\n' "$1"
    else
        printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"
        fail=1
    fi
}

if [ -n "$SMOLVM" ]; then
    if "$SMOLVM" machine list 2>&1 | grep -q 'No machines found'; then
        check machines clean clean
    else
        check machines dirty clean
    fi
else
    printf 'machines=skipped (smolvm not on PATH; it may already be uninstalled)\n'
fi

case "$(uname -s)" in
    Darwin) cache_dir="$HOME/Library/Caches/smolvm" ;;
    *)      cache_dir="${SMOLVM_DATA_DIR:-$HOME/.cache/smolvm}" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$cache_dir/vms}"
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

# _shared is the --oci-cache image store, not residue. Excluding it is what
# makes this a leak check rather than a false alarm.
if [ -d "$cache_dir/vms" ]; then
    left="$(find "$cache_dir/vms" -mindepth 1 -maxdepth 1 -type d ! -name _shared 2>/dev/null | wc -l | tr -d ' ')"
else
    left=0
fi
check vm_dirs "$left" 0

procs="$(list_vm_processes | grep -c . )"
check vm_processes "$procs" 0

# Proof that a run under an isolated HOME left a real installation alone. Silence
# here would read as a pass, so an unchecked run says so.
if [ -n "$protected" ]; then
    touched="$(find "$protected" -newermt "$since" 2>/dev/null | wc -l | tr -d ' ')"
    check "protected_untouched_since_$since" "$touched" 0
else
    printf 'protected=not_checked (pass --protected <dir> to assert a real install was untouched)\n'
fi

# Every check above is scoped to this HOME. Name it, so a result read later says
# which profile it describes and cannot be mistaken for a statement about the host.
printf 'audited_home=%s\n' "$HOME"
if [ "$fail" -eq 0 ]; then printf 'result=clean\n'; else printf 'result=dirty\n'; fi
exit "$fail"
```

## Teardown traps

Almost every cleanup fact in smolvm is counterintuitive: the obvious assertion gives a false
failure, the obvious reaper matches the wrong process, and the command a user reaches for when a
run misbehaves does not stop the machine. Each entry below was hit on a real host.

### `Ctrl-C` does not stop the machine

**And there is no CLI route to the machine it leaves behind.** From a clean zero-process
baseline, the VM's two processes were still alive at t+10 s, t+30 s and t+60 s after `SIGINT` to
the CLI, and `SIGKILL` to the CLI left one. Throughout, `smolvm machine list` says
`No machines found` and no VM cache directory exists.

The VM exits only when its own **workload** finishes: a run whose command was `sleep 45` was gone
30 s after the interrupt; one running `sleep 300` was still alive at 60 s. For a sandbox running
untrusted code that loops or hangs, the exposure is unbounded.

`scripts/cleanup.sh` is the only way to find it.

### Three reapers that look right, and what each one misses

**`pgrep -f _boot-vm` is too wide.** Any process whose command line contains that string matches,
including the cleanup script itself. That produced a phantom "1 orphan survived" result and a
confounded baseline that briefly made `Ctrl-C` look clean.

**`readlink /proc/<pid>/exe` is unreliable in both directions.** For the exec'd VM child the
process is not dumpable, so `/proc/<pid>/exe` is root-owned and `readlink` returns
`Permission denied` to the user who started it:

```
$ ls -l /proc/51706/exe
ls: cannot read symbolic link '/proc/51706/exe': Permission denied
```

On v1.14.6 it is readable for the forked child, which makes it useful for scoping and still no
good for finding.

**Matching `argv[1] == "_boot-vm"` is exact, and blind to half the VMs.** There are two shapes:

| route | child | argv[1] | carries its boot config |
|---|---|---|---|
| plain `machine run` | exec'd | `_boot-vm` | yes, in argv[2] |
| pack-run (`--oci-cache`, or any `init`) | **forked, never exec'd** | inherited, so `machine` | **no** |

The forked child inherits the parent's whole command line, so nothing in its argv marks it as a
VM. Measured on v1.14.6 on Ubuntu 24.04 aarch64 with two such orphans alive at 234 MB each, the
argv-only scanner reported `vm_processes=none` and `result=clean`. **That is the worst of the
outcomes: a false clean.**

**What works.** On Linux both shapes rename themselves to `libkrun VM`, which no shell can hold,
so `scripts/cleanup.sh` matches `/proc/<pid>/comm`, then scopes by argv[2] where it exists and by
the executable's path where it does not. macOS exposes no rename, so the search is scoped by the
executable path under this `HOME` and the parent chain separates a VM from the CLI that started
it. Verified against a live orphan on both hosts.

### Asserting "no machines" immediately after `machine run` fails on a healthy system

A successful `machine run` returns **before** its entry retires. It was observed still listed as
`vm-... unreachable (eph)` immediately after the command returned, and gone by 20 s. This is the
single most likely false failure in a scripted teardown, and it is why `cleanup.sh` waits.

### `machine delete` prompts and defaults to No

Without `--force` a scripted cleanup prints `Delete machine '<name>'? [y/N] Cancelled` and
**leaves the machine in place**, while the surrounding script carries on believing it cleaned up.
A machine that has been branched additionally needs `--cascade`, which removes the children first.

### `ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check

Once `--oci-cache` has been used, a `_shared` directory lives there holding the baked images
(379 MB after one Python image). It is the cache, not residue. `cleanup.sh` and
`verify-clean.sh` both exclude it.

### Small leftover VM directories are not necessarily a leak either

`smolvm serve start` prints `Reclaimed 2 dangling VM data dir(es)` on startup and clears them, so
a directory left by a force-killed run is tidied the next time the API server runs.

### On macOS, do not `rm -rf` the pack cache by hand

`smolvm-pack` can contain `layers-cs` directories that are live `hdiutil` mount points, and `rm`
fails on them with `Resource busy`. The uninstaller detaches them first
(`find ... -name layers-cs -type d -exec hdiutil detach {} -force \;`); do the same if you are
cleaning up manually.

### Pre-existing residue is not yours

Check timestamps and paths before reporting a leak. During the runs behind this packet a second
VM belonging to another session was live on the same host, under a different `HOME`;
`cleanup.sh` listed only the one under its own state tree and left the other running, which is
the behaviour you want from anything you let run unattended.

### Nothing in the docs describes cancellation or teardown

`guides/agent-sandboxes-ci.md` is the page a sandbox author would read and it never mentions how
to stop a run, which matters given the `Ctrl-C` behaviour above.

---
title: "Teardown: stop everything and remove smolvm's state"
---

# Teardown: stop everything and remove smolvm's state

Stops every smolvm machine a session started, removes smolvm's state, and proves the host is clean. Use after any smolvm session; when a machine seems to have survived a Ctrl-C or a crash; when disk space has disappeared; when uninstalling smolvm; when tearing down the Kubernetes runtime from a node; or when a borrowed or shared host has to be handed back with nothing left behind. Also use it as the cleanup step for other smolvm work, because the obvious assertions here give false results. Do not use it to delete machines another session created: it removes only what a script recorded under its own name prefix.

Verified on **smolvm v1.23.0** on macOS arm64, 2026-10-04, and on **v1.18.2** on Linux aarch64,
2026-09-24. This packet exists on its own because **the obvious cleanup steps fail here**: the
obvious assertion gives a false failure, the obvious reaper matches the wrong process or nothing
at all, and killing a wrapper around a run does not stop its machine. Anything that starts machines
needs this more than it needs any single feature.
The Linux runs used the scripts of their date; this version's preflight and cleanup scripts ran
on Linux aarch64 on v1.22.2 on 2026-10-03.

The cleanup scripts of credentials, dev-env, docker-in-machine, gpu-cuda and install are this
packet's `scripts/cleanup.sh` with the `PACKET=` line changed; branch-and-checkpoint, local-api, pack
and throwaway-machine build on it and add flags of their own.

## Procedure

The commands below are relative to this packet's directory; its scripts write nothing to the
working directory, so running them from there is safe.

**1. See what is there.** Read-only: deletes nothing, starts no VM.

```bash
scripts/preflight.sh
```

It reports each state directory with its size, whether an `--oci-cache` bake cache exists,
whether the launcher symlink and the `PATH` block are present, and whether state can be relocated
on this platform.

**2. Delete the machines your scripts created, and report the rest.**

```bash
scripts/cleanup.sh            # report leftover VM processes
scripts/cleanup.sh --reap     # and kill them
```

`--reap` kills every VM process under this `HOME`, a running machine you meant to keep included, so
run plain `cleanup.sh` first to read the list, and reap only when nothing there should keep running.

`cleanup.sh` waits up to 20 seconds, polling the machine list, and prints `waiting=up to 20s`
first: an ephemeral machine's entry retires after its run returns.

Only machines recorded in the state file are deleted, so a machine you or another session created
by hand is never deleted. A script records what it creates with
`scripts/cleanup.sh --record <name>`, and names must carry the `smolskill-` prefix or the delete
is skipped. `--purge` removes the state file once the list is empty.

**When the user asks you to clean up machines they made themselves**, which is what "clean up
after me" usually means, nothing is recorded and the script reports them as `machines=remaining`
and leaves them. That is the guard working, not the end of the job. List them, confirm they are
the user's and not another session's, and delete each by name. `smolvm machine list --json` gives
each machine's `created_at`, in Unix seconds, and its image: one created before the user's session
began, or under a name they do not recognise, is not theirs to delete without asking.
`machine stop` on a machine that is already stopped prints `Machine '<name>' is not running` and
exits 0, so the stop line is safe either way:

```bash
smolvm machine list
smolvm machine stop   --name <NAME>
smolvm machine delete --name <NAME> --force --cascade
```

Then run `scripts/cleanup.sh` again for the process check, and step 3.

The state file lives under `${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills/`, outside
`~/.smolvm` and outside smolvm's own caches. Nothing here edits smolvm configuration.

**3. Prove it.**

```bash
scripts/verify-clean.sh
HOME=/tmp/sk SMOLVM=/tmp/sk/.local/bin/smolvm scripts/verify-clean.sh --protected "$HOME/.smolvm" \
    --protected "$HOME/.local/share/smolvm" --protected "$HOME/.cache/smolvm"   # typed in your real shell
```

Typed in your real shell, `$HOME` expands to the real profile before `HOME=/tmp/sk` applies, so the
checks audit the scratch profile and the three `--protected` directories are the real
installation's binary, data and cache. On macOS the last two are
`~/Library/Application Support/smolvm` and `~/Library/Caches/smolvm`; a `--protected` directory
that does not exist fails rather than passing. `SMOLVM=` points the scan at the scratch install's
binary; on Linux, run it with `XDG_DATA_HOME` and `XDG_CACHE_HOME` unset, as the install was.
Anything the real installation wrote today counts, and a running real machine writes to its cache
directory. Stop the real machines first, and pass `--since` with the time the test began, such as
`--since "2026-10-03 14:00"`.

**Every check here is scoped to the `HOME` it runs under**, and the `audited_home=` line says
which profile the result describes. Run it under a different `HOME` and it reports a clean host no
matter what is running elsewhere: an agent that hit `machines=FAIL` did exactly that, re-ran the
script under a fresh `mktemp -d`, got `result=clean`, and reported the host clean while a VM was
still running.

Each check prints `ok` or `FAIL expected=... actual=...`, and the script exits non-zero if any
failed. When the `HOME` you are auditing is the only installation there is nothing to protect:
leave the flag off, and the `protected=not_checked` line it then prints is expected.
`--protected <dir>` asserts nothing under that directory was written today, which is how you show
a test run under a scratch `HOME` did not reach a real installation. It is repeatable, and a leak
lands in the data and cache directories rather than the prefix, so name all three. It takes an
installation's directories, not a home directory: pointed at a whole home it counts every file
written there today and reports `result=dirty`.

**4. Reclaim space, or remove smolvm entirely.**

```bash
# machine prune: unreferenced layers; starts the machine if it is stopped. --all also
# drops cached images, except for a machine created from an image
smolvm machine prune --name <NAME>
smolvm pack prune
curl -sSL https://smolmachines.com/install.sh | bash -s -- --uninstall
```

`references/locations.md` has the full layout, what the uninstaller removes, and the two things it
deliberately leaves. On v1.18.2 on macOS it also leaves `~/Library/Caches/smolvm-registry`, and on
v1.23.0 `smolvm-image-archives` beside the cache directory on both hosts, without saying so; remove
those by hand after `--uninstall`.

## The traps that make this a packet

Full detail with the observations behind each is in `references/traps.md`.

- **`Ctrl-C` on the CLI stops the machine from v1.20.2; killing a wrapper around it does not.** On
  v1.22.2 the killed wrapper's CLI and VM kept running, listed as `vm-<id> running (eph)`;
  `smolvm machine stop --name vm-<id>` ends both, and the entry stays `stopped (eph)` until
  `machine delete --force`. Before v1.20.2 an interrupted CLI left its VM running, unlisted on
  v1.14.x, which is the case the reaper still covers.
- **The two obvious reapers fail in opposite directions.** `pgrep -f _boot-vm` matches the cleanup
  script itself; `readlink /proc/<pid>/exe` is denied for a VM process. Matching `argv[1]` misses
  the forked VMs a pack run starts. On Linux VM processes rename themselves to `libkrun VM`, or to
  `VM:<hostname>` when `HOSTNAME` is exported, which no shell can hold, so `cleanup.sh` matches
  that in `/proc/<pid>/comm`; on macOS it matches the executable path and parent chain. Both are
  scoped to this `HOME`.
- **Asserting "no machines" straight after `machine run` can fail on a healthy host**: the entry
  retires after the command returns.
- **`machine delete` needs `--force` in a script**, and `--cascade` for a branched machine. On
  v1.17.0 and later a delete without it exits 1; before that it printed `Cancelled`, exited 0 and
  left the machine.
- **A paused machine refuses `stop`** with `machine has saved execution; use resume or delete`;
  `delete --force` removes it and its saved execution.

And one false alarm: **`ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check.** On Linux, after
`machine create --from` or a checkpoint restore, `_shared` lives there: the shared pack store. Both
scripts exclude it. An `--oci-cache` bake goes to `init-layers/` beside `vms/` and to the pack
cache. The opposite case is real residue: **a boot that timed out leaves its VM directory**,
`verify-clean.sh` reports `vm_dirs=FAIL`, and running `smolvm serve start` once reclaims it. And
one cache that is sensitive: **on macOS smolvm keeps a clone of the last restored checkpoint**,
memory included, in `vms/_restore-base`, after every machine and checkpoint is gone.
`verify-clean.sh` reports it as `restore_base=present` rather than as a leak; remove it with
`rm -rf` once no restore is running.
From v1.22.0 it is `vms/_restore-checkpoints`, reported as `restore_cache=present`;
`references/traps.md` has its size and how to turn it off.

**A machine named `image-seed-<hash>-<pid>` or `init-bake-<hash>-<pid>` is smolvm's own helper.**
From v1.22.0 the first run of a registry image builds a shared seed of it in a helper machine, and
the seed itself lives in `image-seeds/` beside `vms/`. When that run is interrupted, or the helper
cannot boot, the helper can stay listed as `created` or `stopped`: three did on Linux aarch64 on
v1.22.2, at 8192 MiB each whatever the run asked for. It is neither the user's nor another
session's; delete it by name with `--force`.

## Security defaults, and why they are the defaults

- **Cleanup deletes only what it was told it created.** A shared host can carry another session's
  machines, and during the runs behind this packet it did: a second VM under a different `HOME`
  was live throughout. `cleanup.sh` listed only the processes whose boot config sits under its own
  state tree and left the other one running. A cleanup script that kills every smolvm process is
  fine on your laptop and destructive on a build agent.
- **`--reap` is opt-in, and without it the script only reports.** With it, each `vm_process=` line
  is killed as it is printed. Killing a VM is not recoverable and the VM cannot be identified from
  `machine list`, so the default is to report.
- **Nothing here escalates privilege.** The one place teardown needs `sudo` is the Kubernetes
  runtime, which installs outside your home directory; those commands are in
  `references/kubernetes.md` for you to run and read, not wrapped in a script.
- **The uninstaller leaves `~/.config/smolvm` and your `PATH` line on purpose**, because those
  hold registry credentials and a change you made to your own shell profile.

## Platform arms

- **macOS arm64**: the scripts were run here on v1.23.0. **Linux aarch64**: on v1.18.2, and once
  on v1.22.2.
- **Linux x86_64**: the procedure was verified on v1.14.2 on an NVIDIA A10 cloud host. The
  scripts themselves were not re-run there.
- **Windows x86_64**: `references/windows.md`, **run on 2026-10-03 against v1.22.2** on
  Windows 11 Home build 10.0.26200 UBR 9457 as the cleanup after runs that had created
  machines, packs and bakes, after which the profile matched its listing from before them. The
  scripts are bash and do not run there. State cannot be relocated there, and one set of runs left
  30 GB in `%LOCALAPPDATA%\smolvm`.
- **Kubernetes nodes**: `references/kubernetes.md`. The sweep was verified on Ubuntu 22.04 x86_64
  with k3s on v1.14.2, not re-run since; the lines for the `RuntimeClass`, the node label and the
  drop-in are read from the repository's k3s scripts at v1.22.2 and were not run.

## Eval prompts, and what they produced

On macOS arm64 on v1.23.0, under an isolated `HOME`:

**1. "I ran some smolvm machines. Clean up after me and show me the host is clean."** A machine
created, started, recorded and cleaned up: `Deleted machine: smolskill-td`, `machines=clean`,
`vm_processes=none`, then `machines=ok`, `vm_dirs=ok`, `vm_processes=ok`, `result=clean`.

**2. "Is anything still running that `smolvm machine list` cannot see?"** On v1.22.2 and v1.23.0 an
interrupted run stays listed, so the answer is "nothing the list cannot see"; the reaper still
names the process and its boot config. With a wrapper killed:

```
vm_process=89092 config=/tmp/u23/Library/Caches/smolvm/vms/ea8c396d10b0f0b9/boot-config.json
  killed 89092
```

**3. "Prove my test run did not touch my real smolvm install."** `verify-clean.sh --protected
$HOME/.smolvm` against the real installation beside the isolated one:
`protected_untouched_since_2026-10-04:<dir>=ok` for each `--protected` directory, and
`result=clean`.

## Re-verified on v1.23.0

Run 2026-10-04 PT against v1.23.0 from the published release, checksum checked, under a fresh
isolated `HOME` on macOS 27.0.1 arm64, once. On Lima `linux-kvm` (Ubuntu 24.04 aarch64) the
checks named below ran once, so the Linux stamp stays on its earlier release.

macOS: eval 1 gave `result=clean`. `SIGINT` and `SIGKILL` to the CLI each left no VM process at
t+1 s; a killed wrapper left `vm-0072df9e running (eph)` and its `_boot-vm`, which `cleanup.sh
--reap` found and killed. A delete without `--force` exited 1 with the confirmation message, a
paused machine refused `stop` with `machine has saved execution; use resume or delete`, and a
second `machine stop` of a missing name gave `vm_dirs=FAIL` until `serve start` printed `Reclaimed
1 dangling VM data dir(es)`. Eval 3 gave `protected_untouched_since_2026-10-04:<dir>=ok` for each
of the real installation's three directories. New beside `vms/`: `registry-tokens/`. After every
packet had run, `--uninstall` left `Library/Caches/smolvm-image-archives`, 24 MB;
`references/locations.md` has it.

Linux aarch64: `verify-clean.sh` gave `result=clean`, and `--uninstall` left
`~/.cache/smolvm-image-archives` there too.

## Re-verified on v1.22.2

Run 2026-10-03 PT against v1.22.2 from the published release, checksum checked, under an isolated
`HOME` on macOS 27.0.1 arm64, twice, the second time from a fresh `HOME`. On Lima `linux-kvm`
(Ubuntu 24.04 aarch64) on 2026-10-03 guests above 2048 MiB timed out, so the Linux lines below are
a single run and the Linux stamp stays on its earlier release.

macOS: eval 1 gave `result=clean` with `protected_untouched_since_2026-10-03=ok`, from the
script's earlier one-directory form. `SIGINT` and
`SIGKILL` to the CLI each left no VM process at t+1 s; a killed wrapper left `vm-90dd19c7 running
(eph)` and its `_boot-vm`, which `cleanup.sh --reap` found and killed. A delete without `--force`
exited 1 with the confirmation message, a paused machine refused `stop`, and a second `machine
stop` of a missing name gave `vm_dirs=FAIL` until `serve start` printed `Reclaimed 1 dangling VM
data dir(es)`. After every packet had run, the final check said `result=clean`.

Linux aarch64: eval 1 clean, the delete and pause refusals the same, and three `image-seed-*`
helpers left listed by interrupted and failed first boots. Linux was last verified on v1.18.2.

## What was not run

- **Windows through a script.** The sequence on `references/windows.md` was run by hand.
- **Kubernetes.** `references/kubernetes.md` records a sweep verified on an Ubuntu 22.04 x86_64 k3s
  node on v1.14.2, not re-run since. Its lines for the `RuntimeClass`, the node label and the
  drop-in are read from the repository's k3s scripts at v1.22.2 and were not run.
- **Linux x86_64.**
- **The macOS `hdiutil` mount-point case.** `references/traps.md` records that `rm -rf` on the
  pack cache can fail with `Resource busy` and what the uninstaller does about it. No pack was
  created in the runs recorded here, so that path was not exercised.
- **The shared pack store.** No `_shared` store existed on either host, so the exclusion these
  scripts carry was exercised only against its absence.

## Related packets

- `install` for what the install lays down, which is what you are removing.
- Every other packet's `scripts/cleanup.sh` is built from this one.

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

VERIFIED_VERSION="1.23.0"

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
        emit unsupported "cuda"
        # There is no SMOLVM_DATA_DIR on macOS (it is Linux-only), but every path
        # below is derived from HOME, so an install under a scratch HOME is
        # self-contained. Windows is the platform where neither route works.
        emit state_relocatable via_home
        ;;
    Linux)
        emit platform "linux-$arch"
        emit accel kvm
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then emit accel_access ok; else emit accel_access denied; fi
        # With SMOLVM_DATA_DIR set, smolvm runs with HOME there; otherwise XDG wins.
        data_dir="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.local/share}"
        data_dir="${data_dir:-${XDG_DATA_HOME:-$HOME/.local/share}}/smolvm"
        cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
        cache_root="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}"
        cache_dir="$cache_root/smolvm"
        pack_dir="$cache_root/smolvm-pack"
        libs_dir="$cache_root/smolvm-libs"
        emit state_relocatable via_home_or_data_dir
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux. The Windows removal sequence is references/windows.md, run there by hand on v1.22.2."
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

# `_shared` is the Linux shared pack store, written by machine create --from and
# checkpoint restores. It is cache, not residue, so counting it as a leak gives
# a false positive.
if [ -d "$cache_dir/vms" ]; then
    total="$(find "$cache_dir/vms" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    shared=0
    [ -d "$cache_dir/vms/_shared" ] && shared=1
    emit vm_dirs "$((total - shared))"
else
    emit vm_dirs 0
fi
# An --oci-cache bake writes its layers to init-layers beside vms.
if [ -d "$cache_dir/init-layers" ]; then emit bake_cache_present yes; else emit bake_cache_present no; fi

if grep -qs 'smolvm' "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.config/fish/config.fish" 2>/dev/null; then
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

### `scripts/verify-clean.sh`

```bash
#!/usr/bin/env bash
# Prove the host is clean after a teardown. Every check asserts a value rather
# than an exit code, because the commands teardown runs report success while
# leaving state behind.
#
# usage: verify-clean.sh [--protected <dir>]... [--since <date>]
#   --protected <dir>  assert nothing under <dir> was written on or after --since.
#                      Repeatable. Point it at the prefix, data and cache directories
#                      of a real installation you ran beside: that is how you show a
#                      test under an isolated HOME did not reach it.
#                      Omitted, the check is reported as not run rather than passed.
#   --since <date>     the cutoff for --protected (default: today)

set -uo pipefail

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
since="$(date +%F)"
protected=()
while [ $# -gt 0 ]; do
    case "$1" in
        --protected) protected+=("$2"); shift ;;
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
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            cache_dir="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$cache_dir/vms}"
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

# _shared is the Linux shared pack store, _restore-base the clone of the last
# restored checkpoint, _restore-checkpoints the cache of recent restores that
# replaced it in v1.22.0, and checkpoint-unpack their scratch area, none of them a
# machine. Excluding them is what makes this a leak check rather than a false
# alarm; the two restore caches are reported, since they hold guest memory and disks.
# An empty directory holds no state and is reported apart from the check.
if [ -d "$cache_dir/vms" ]; then
    left="$(find "$cache_dir/vms" -mindepth 1 -maxdepth 1 -type d ! -empty ! -name _shared ! -name _restore-base ! -name _restore-checkpoints ! -name checkpoint-unpack 2>/dev/null | wc -l | tr -d ' ')"
    empty="$(find "$cache_dir/vms" -mindepth 1 -maxdepth 1 -type d -empty ! -name checkpoint-unpack 2>/dev/null | wc -l | tr -d ' ')"
    [ "$empty" != 0 ] && printf 'empty_vm_dirs=%s (no state in them; not counted)\n' "$empty"
else
    left=0
fi
if [ -d "$cache_dir/vms/_restore-checkpoints" ]; then
    printf 'restore_cache=present %s (recently restored checkpoints'"'"' memory and disks; machine create --from --restore-cache-entries 0 turns it off)\n' "$(du -sh "$cache_dir/vms/_restore-checkpoints" 2>/dev/null | cut -f1)"
fi
if [ -d "$cache_dir/vms/_restore-base" ]; then
    printf 'restore_base=present %s (the last restored checkpoint'"'"'s memory and disks; rm -rf it once no restore is running)\n' "$(du -sh "$cache_dir/vms/_restore-base" 2>/dev/null | cut -f1)"
fi
check vm_dirs "$left" 0
if [ "$left" != 0 ]; then
    printf 'note=a boot that timed out or was killed leaves its VM directory; run smolvm serve start once to reclaim it, then check again\n'
fi

procs="$(list_vm_processes | grep -c . )"
check vm_processes "$procs" 0

# Proof that a run under an isolated HOME left a real installation alone. Silence
# here would read as a pass, so an unchecked run says so.
for dir in ${protected[@]+"${protected[@]}"}; do
    if [ ! -d "$dir" ]; then
        printf 'protected_untouched_since_%s:%s=FAIL not a directory\n' "$since" "$dir"; fail=1; continue
    fi
    touched="$(find "$dir" -newermt "$since" 2>/dev/null | wc -l | tr -d ' ')"
    check "protected_untouched_since_$since:$dir" "$touched" 0
done
[ "${#protected[@]}" -eq 0 ] && printf 'protected=not_checked (pass --protected <dir> to assert a real install was untouched)\n'

# Every check above is scoped to this HOME. Name it, so a result read later says
# which profile it describes and cannot be mistaken for a statement about the host.
printf 'audited_home=%s\n' "$HOME"
printf 'scanned_prefix=%s\n' "$SMOLVM_PREFIX"
if [ "$fail" -eq 0 ]; then printf 'result=clean\n'; else printf 'result=dirty\n'; fi
exit "$fail"
```

## Teardown traps

The obvious cleanup steps fail here: the obvious assertion gives a false failure, the obvious
reaper matches the wrong process, and killing a wrapper around a run does not stop its machine. Each entry below was hit on a real host.

### `Ctrl-C` on the CLI stops the machine from v1.20.2, and did not before

**On v1.22.2 it does**, measured on macOS arm64 against a clean baseline: `SIGINT` and `SIGKILL`
to the CLI's process group each left neither the CLI nor its `_boot-vm` alive at t+1 s, and
`machine list` said `No machines found`. A killed **wrapper** is the case that still leaves a VM:
the CLI is reparented to PID 1, both processes keep running, and the run is listed as
`running (eph)`. `machine stop --name <id>` ends both and leaves the entry as `stopped (eph)`, still
there 20 s later, until `machine delete --name <id> --force` removes it.

**Before v1.20.2 there was no CLI route to the machine it left behind.** From a clean zero-process
baseline, the VM's two processes were still alive at t+10 s, t+30 s and t+60 s after `SIGINT` to
the CLI, and `SIGKILL` to the CLI left one. Throughout, `smolvm machine list` says
`No machines found` and no VM cache directory exists.

The VM exits only when its own **workload** finishes: a run whose command was `sleep 45` was gone
30 s after the interrupt; one running `sleep 300` was still alive at 60 s. For a throwaway machine running
untrusted code that loops or hangs, the exposure is unbounded.

`scripts/cleanup.sh` is the only way to find it.

**Measured again on v1.18.2, 2026-09-24**, with the wrapper killed and the CLI left alone: on macOS
arm64 the run stayed in `machine list` as `running (eph)` and `machine stop --name` cleared it; on
Linux aarch64 the VM went with the wrapper. Killing the CLI as well took the VM on both.

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

**What works.** On Linux both shapes rename themselves to `libkrun VM`, or to `VM:<hostname>` when
`HOSTNAME` is exported, which no shell can hold, so `scripts/cleanup.sh` matches either in
`/proc/<pid>/comm`, then scopes by argv[2] where it exists and by the executable's path where it
does not. macOS exposes no rename, so the search is scoped by the
executable path under this `HOME` and the parent chain separates a VM from the CLI that started
it. Verified against a live orphan on both hosts.

### Asserting "no machines" immediately after `machine run` fails on a healthy system

A successful `machine run` returns **before** its entry retires. It was observed still listed as
`vm-... unreachable (eph)` immediately after the command returned, and gone by 20 s. This is the
single most likely false failure in a scripted teardown, and it is why `cleanup.sh` waits.

### `machine delete` needs `--force` in a script

**Through v1.16.x**, without `--force` a scripted cleanup printed `Delete machine '<name>'? [y/N]
Cancelled`, exited 0 and **left the machine in place**, while the surrounding script carried on
believing it cleaned up. **On v1.17.0 and later** (#1333) the same call with stdin not a terminal
exits 1:

```
Error: agent operation failed: delete: machine 'smolskill-del' needs confirmation but stdin is not
a terminal; pass --force to delete it, or --cascade to remove it together with any machines
branched from it
```

Measured on v1.18.2 on macOS arm64 and Linux aarch64, 2026-09-24. Pass `--force` either way. A
machine that has been branched additionally needs `--cascade`, which removes the children first.

### A paused machine refuses `stop`

`machine pause` saves the machine's RAM, disks and execution state and stops it, and `machine
list` then shows it as `paused`. **`machine stop` refuses it** with `machine has saved execution;
use resume or delete`, exit 1, because stopping would discard the saved execution, and `machine
start` refuses it with `machine has saved execution; use resume`. `machine delete --force` removes the machine and the saved state. On
v1.18.2 the saved state of a 1024 MiB alpine guest was 70 MB on macOS and 73 MB on Linux, in the
machine's own directory, so it goes with the delete.

### `ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check

On Linux, after `machine create --from` or a checkpoint restore, a `_shared` directory lives
there: the shared pack store. It is cache, not residue. `cleanup.sh` and `verify-clean.sh` both
exclude it. An `--oci-cache` bake writes to `init-layers/` beside `vms/` and to the pack cache,
not here.

### Small leftover VM directories are not necessarily a leak either

`smolvm serve start` prints `Reclaimed 2 dangling VM data dir(es)` on startup and clears them, so
a directory left by a force-killed run is tidied the next time the API server runs.

**A boot that timed out leaves one too.** On v1.18.2 on Linux aarch64, 2026-09-24, seven ephemeral
runs that failed with `agent did not become ready within 30 seconds` left seven directories, each
holding `agent-startup-error.log`, and `verify-clean.sh` reported `vm_dirs=FAIL expected=0
actual=7`. Starting `smolvm serve start` once and stopping it printed `Reclaimed 7 dangling VM data
dir(es)`, and the check then passed. Read `agent-startup-error.log` first if you want to know why
the boot failed.

**`machine stop` on a name that does not exist leaves an empty directory** there on v1.18.2, so a
cleanup that stops every recorded name after `--cascade` removed the children leaves one per child.
They hold nothing; `verify-clean.sh` reports them as `empty_vm_dirs=` and does not fail on them.
**A second stop of the same missing name writes a 12-byte `name` file into it** on v1.22.2, and the
directory then counts as a leak (`vm_dirs=FAIL`). `scripts/cleanup.sh` acts only on names still in
`machine list` for that reason, and one `smolvm serve start` reclaims what an older script left.

### Restored checkpoints stay in the cache

On macOS, `vms/_restore-base` is a clone of the most recently restored checkpoint, kept so the next
restore writes only what differs. It holds that checkpoint's memory and disks, 243 MB after
several restores on v1.18.2, and it stays after every machine and every `.smolcheckpoint` is
deleted; `serve start` does not reclaim it. `checkpoint-unpack`, beside it, is an empty scratch
directory. `verify-clean.sh` excludes both from the leak count and prints `restore_base=present`
with the size. Remove it with `rm -rf` when no restore is running, and treat it like the
checkpoints themselves. Linux aarch64 did not create one.

From v1.22.0 the cache is `vms/_restore-checkpoints`, which keeps the three most recently restored
checkpoints, up to 16 GiB, so jumping back to one clones it instead of rebuilding its RAM. After
several restores on macOS on v1.23.0 it held 258 MB with no machine and no checkpoint left, and
no `_restore-base` was created. `verify-clean.sh` reports it as `restore_cache=present` and does not
count it. `machine create --from` takes `--restore-cache-entries` and `--restore-cache-gib`, and
`--restore-cache-entries 0` turns the cache off.

### A machine whose guest disk failed refuses `delete --force`

A machine restored and started while the host disk was full came up with its guest overlay
failing. With space back, its delete:

```
Error: agent operation failed: stop agent: guest did not confirm filesystem synchronization; left
the VM alive for retry: agent operation failed: shutdown ack: freeze /oldroot/mnt/overlay: I/O error
(os error 5)
```

exit 1, still `running`. `scripts/cleanup.sh --reap` killed its VM process, and `delete --force`
then removed the machine and its directory. `--reap` kills every VM process under this `HOME`.

Zero-byte files named `.<name>.fork-operation.lock` or `.<name>.fork-operation.pause-operation.lock`
stay in the same directory after a machine that was paused or checkpointed is deleted. They are
not directories and the leak check does not count them. On Linux every delete also prints
`WARN unable to lock UID registry; retaining assignment` and still deletes.

### On macOS, do not `rm -rf` the pack cache by hand

`smolvm-pack` can contain `layers-cs` directories that are live `hdiutil` mount points, and `rm`
fails on them with `Resource busy`. The uninstaller detaches them first
(`find ... -name layers-cs -type d -exec hdiutil detach {} -force \;`); do the same if you are
cleaning up manually.

### Pre-existing residue is not yours

Check timestamps and paths before reporting a leak. During the runs recorded here a second VM
belonging to another session was live on the same host, under a different `HOME`;
`cleanup.sh` listed only the one under its own state tree and left the other running, which is
the behaviour you want from anything you let run unattended.

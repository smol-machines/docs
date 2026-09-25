---
title: "Branch and checkpoint: scheduled checkpoints, restores and branch points"
---

# Branch and checkpoint: scheduled checkpoints, restores and branch points

Saves a running smolvm machine as checkpoints on a schedule, keeps a bounded history, restores any generation in it, pauses and resumes machines without losing running processes, and branches a warm machine into children with a checkpoint of the exact point they started from. Use when a machine's state has to survive the machine; when an agent or a job needs to roll back; when checkpoints must be taken periodically, since smolvm has no scheduler or retention of its own; when fanning a prepared machine out into workers; or when a checkpoint, a pause or a branch fails with an error that names none of its preconditions. Do not use it to ship an environment to another host as a file, which is the pack packet, or for state that only has to survive a stop and start, which is the dev-env packet.

Verified on **smolvm v1.18.2** on macOS arm64 and Linux aarch64, 2026-09-24. Done means a restore
brings back both the disk and the memory you left, the schedule keeps exactly the checkpoints you
asked for and no fewer, and every child of a branch starts from a state you still hold as a
checkpoint after the children are gone.

`README.md` says what each of these operations is. This file is how to run them, and the traps.

**Three facts shape everything here.**

- **smolvm has no scheduler and no retention.** `scripts/checkpoint.sh` is the one capture a timer
  runs, with the rules the engine asks a scheduler to follow built in; `references/scheduling.md`
  puts it under cron, systemd or launchd.
- **A branch's captured state stays on this host and cannot be exported.** So a branch point is
  paired with a checkpoint taken at the same moment, which is the copy you keep.
- **`--branchable` at `start` decides what a machine can do later.** A branch source needs it on
  every host. On macOS `checkpoint` and `pause` need it too, and the error when it was not,
  `guest RAM has no file-backed regions`, names neither the flag nor the operation; Linux
  checkpoints and pauses without it. The scripts always start with it.

## Procedure

```
- [ ] 1. preflight.sh               read result= and store_space_ok=
- [ ] 2. create-source.sh           a machine with state in RAM and on disk
- [ ] 3. checkpoint.sh / schedule.sh   captures, with retention
- [ ] 4. restore.sh                 any generation, into a new machine
- [ ] 5. pause and resume           the restored machine, or any branchable one
- [ ] 6. branch-point.sh            children plus a checkpoint of where they started
- [ ] 7. cleanup.sh                 machines, checkpoints, and smolvm's restore cache
```

**1. Preflight.** Read-only.

```bash
scripts/preflight.sh --store ./store
```

It checks that this binary has `--store`, `--history`, `checkpoint-log`, `pause` and restore
`--at`, says whether this host needs `--branchable`, and reports `scheduler=builtin_none` and
`retention=builtin_none` so nobody goes looking for them. `store_space_ok=no` blocks: a capture
into a full disk publishes nothing, and a machine restored while the disk was full was left with
guest I/O errors that stopped it being deleted normally.

**2. A source with state you can check.**

```bash
scripts/create-source.sh smolskill-src                 # for checkpoints and restores
scripts/create-source.sh smolskill-bp --branch-ready   # for a batch branch
```

The workload writes a counter into `/tmp` every second, which is tmpfs and so RAM, and a marker to
`/root/setup.txt` on disk. A restore that brings the counter back proves memory came back, not only
the disk. `--branch-ready` makes the workload park in `smolvm-branch-ready` after its setup, which a
batch branch waits for.

**Or the user's own machine.** Name it with `--name` in the steps below. On macOS, if it was
started without `--branchable`, the first capture fails with `guest RAM has no file-backed
regions`, and the only fix is a restart with the flag:

```bash
smolvm machine stop  --name worker
smolvm machine start --name worker --branchable
```

That restart is a normal stop and start: disk state survives, and anything in RAM or `/tmp` is
lost, once. Say so to the user before doing it. Every start of that machine needs the flag from
then on for it to stay checkpointable.

**3. Capture, once or on a schedule.**

```bash
scripts/checkpoint.sh --name smolskill-src --store ./store --keep 6 --history 2
scripts/schedule.sh   --name smolskill-src --store ./store --every 600 --times 3 --keep 6 --history 2
```

Each capture goes to a new directory named `<machine>-<label>-<UTC time>.smolcheckpoint` beside the
store. It is judged published only when `checkpoint-log` lists it as `(this checkpoint)`, and only
then are the oldest beyond `--keep` deleted and the store pruned. A capture started while another
of the same machine runs exits 3 with `result=skipped`. `schedule.sh` is for a session you are
watching; a schedule that outlives it is `checkpoint.sh` under a system timer,
`references/scheduling.md`.

```
run=1 rc=0 took_s=2 ... kept=1 store_size= 59M result=captured
run=2 rc=0 took_s=5 ... kept=2 store_size= 76M result=captured
run=3 rc=0 took_s=2 ... kept=2 store_size= 95M result=captured
run=4 rc=0 took_s=1 ... kept=2 store_size=114M result=captured
captures_ok=4
longest_capture_s=5
result=schedule_ok
```

**Set the interval from `longest_capture_s`, not from the pause.** The source pauses for a few
hundredths of a second; the command takes seconds, because retained RAM is hashed and compressed
after the source resumes. **`--keep` alone does not bound the disk**: every kept checkpoint also
retains `--history` earlier generations, 32 by default, so the store above kept growing with two
directories kept. Bound both.

**4. Restore, any generation.**

```bash
smolvm machine checkpoint-log ./smolskill-src-ckpt-<time>.smolcheckpoint
scripts/restore.sh --from <checkpoint> --name smolskill-old --at '~2'
scripts/restore.sh --from <checkpoint> --name smolskill-new
```

`~0` is the checkpoint itself and `~N` is N generations back along its history. `restore.sh`
names the new machine `smolskill-...` so cleanup can find it; to restore under a name the user
chooses, run `smolvm machine create --name <name> --from <checkpoint> --at '~N'` and then
`smolvm machine start --name <name> --branchable` yourself. The restore path is
`machine create --from`; **there is no `machine restore`**. A restored machine takes its own name as
its hostname, and its disks are copy-on-write over what the checkpoint holds, so a restore costs
about 29 MB of real disk on macOS for a 243 MiB checkpoint while `du` reports five times that.

**5. Pause and resume.**

```bash
smolvm machine pause  --name smolskill-new
smolvm machine resume --name smolskill-new
```

Pause saves RAM, disks and the running execution and stops the machine; resume brings the same
execution back under the same name. Check a value the workload holds in memory: on both hosts the
counter read 31 before the pause and 34 and 33 after the resume, so it continued where it stopped
and did not run while paused. A paused machine refuses `stop` and `start`; resume it or delete it.
A resume that fails keeps the saved state, and a later resume of the same machine succeeded.

**6. Branch, and keep the branch point.**

```bash
scripts/branch-point.sh --from smolskill-bp --store ./store --count 2 --name-prefix smolskill-w
scripts/branch-point.sh --from smolskill-src --store ./store --name smolskill-one
```

For a batch it waits until the source's PID 1 is `smolvm-branch-ready`, takes the checkpoint while
the source is parked there, then branches. Every child and that checkpoint then hold the same
state: a random value the source wrote to RAM before parking came back identical in both children
and in a restore of the checkpoint.

```
source_parked_after_s=1
checkpoint=.../smolskill-bp-branchpoint-<time>.smolcheckpoint
child=smolskill-w-0
child=smolskill-w-1
source_state=running
result=branched
```

For one child with `--name` the checkpoint is taken first and the branch a second or two later, so
the two points differ by whatever the source did in between.

**A restored branch point is not a parked source.** On start the helper releases and the workload
runs the child program with an empty `SMOLVM_BRANCH_NAME`, so a batch branch from it waits for a
branch point that never comes. Branch it with `--name`, one child at a time, or restore it once per
worker; either way the child gets the state the original children started from.

**7. Clean up.**

```bash
scripts/cleanup.sh --purge --restore-base --checkpoints ./store ./*.smolcheckpoint
```

It deletes the machines the scripts recorded, children first by `--cascade`, removes the named
checkpoint directories and stores, and with `--restore-base` removes smolvm's clone of the last
restored checkpoint, which otherwise stays after every machine and checkpoint is gone.

## Traps

Full detail in `references/traps.md`. The ones that cost the most:

- **`--branchable` is decided at `start` and cannot be added later.** Branching needs it
  everywhere; on macOS `checkpoint` and `pause` need it as well.
- **`--output` must end in `.smolcheckpoint`**, with `--store` too, where it names a directory.
- **`pgrep -f smolvm-branch-ready` inside the guest always matches**, because the `sh -c` running it
  contains the string. Read `/proc/1/cmdline`.
- **`smolvm machine list | grep -q` under `pipefail` can report a machine missing that exists**:
  `grep -q` closes the pipe early and the failed write fails the pipeline. Read the list into a
  variable first. Two scripts in this packet did this before the run caught it.
- **`machine stop --name` on a name that does not exist leaves an empty directory** under the VM
  cache on v1.18.2. A cleanup that stops each recorded name after `--cascade` deleted the children
  leaves one per child.
- **smolvm keeps the last restored checkpoint** in `vms/_restore-base` on macOS, 243 MB here,
  memory included. Deleting the checkpoint does not delete it.

## Security defaults, and why they are the defaults

- **A checkpoint is the machine's memory and disks.** Anything the workload held, secrets included,
  is in it; keep stores on a disk only you can read, and remove `_restore-base` when you remove the
  checkpoints.
- **Retention deletes only after the new checkpoint is published**, so a failed capture never
  leaves you with fewer good checkpoints than before.
- **A store is local.** It protects against a bad change, not a lost host; export a checkpoint
  with `machine checkpoint --export-from` and copy it elsewhere for that.
- **Cleanup deletes only machines the scripts recorded under the `smolskill-` prefix**, and removes
  only the checkpoint paths you name.
- **Nothing here escalates privilege** or edits smolvm configuration.

## Platform arms

`references/platforms.md` has each arm. In short: **macOS arm64** and **Linux aarch64** ran every
step here on v1.18.2, with the one difference that Linux needs no `--branchable`. On v1.16.1 Linux
aarch64 refused `--store` and froze a branch source; on v1.18.2 it does neither. **Linux x86_64**
was not re-run. **Windows** refuses checkpoint and branch.

## Eval prompts, and what they produced

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64), every machine at 1024 MiB. Output is
verbatim unless marked.

**1. "Checkpoint this machine every few minutes, keep only the last few, and show me I can go back
to any of them."**

`schedule.sh` with `--keep 2 --history 2`, four captures ten seconds apart, both hosts:
`captures_ok=4`, `kept=2`, and `checkpoint-log` on the newest listed `~0`, `~1` and `~2`. A marker
written between captures came back as `GEN1` from `--at '~2'` and `GEN3` from the newest, with the
RAM counter restored alongside. A second capture started while one ran:

```
result=skipped
note=a capture of smolskill-src is still running (pid 13935). Run one capture at a time per source: ...
```

**2. "Fan this prepared machine out into workers, and keep a copy of exactly the state they started
from."**

`branch-point.sh --count 2` on a `--branch-ready` source, macOS: the source wrote `8445` to RAM
before parking; both children read `SETUP_DONE`, their own `CHILD=` name and `8445`, and a restore of
the branch-point checkpoint read `8445`. Linux the same with `22642`. `source_state=running` on both.

**3. "Pause the machine I restored and bring it back later without losing what is running."**

The restored machine's counter: `ram before=31 after=34` on macOS and `ram before=31 after=33` on
Linux, across a 10 s pause. Separately, on macOS a restored machine paused while the host disk was
full failed its first resume with `extract paused checkpoint: failed to unpack ...`, and the same
`machine resume` succeeded once space was freed: counter 8 before the pause, 14 after, still
counting.

## What was not run

- **Linux x86_64 and Windows** on v1.18.2.
- **A schedule over hours.** Four captures ten seconds apart on each host, and single captures
  across the session; the growth of a store under `--history 32` over a day was not measured.
- **Restores on another host.** A checkpoint is host, CPU and device specific, and nothing here
  moved one between the two hosts.
- **GPU and CUDA machines**, and `--share-weights`.
- **Branch pools** (`--hold`, `branch-release`) and `--freeze-source`.
- **The API's restore route**, the `from` field on create; the `local-api` packet covers pause and
  resume over HTTP.

## Related packets

- `dev-env` for state that only has to survive a stop and start.
- `pack` for moving a machine to another host as a file, including a restored one.
- `local-api` for pause and resume over HTTP.
- `teardown` for the wider cleanup, and for what a leak check must exclude.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can checkpoint, restore, pause and branch smolvm
# machines, and whether the place the checkpoints will go has room. Read-only:
# starts no VM, writes no smolvm state, changes no group membership.
#
# usage: preflight.sh [--store <dir>]   (default: the current directory)
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.18.2"

emit() { printf '%s=%s\n' "$1" "$2"; }

blocked=0
note() { printf 'note=%s\n' "$1"; }

STORE_DIR="."
while [ $# -gt 0 ]; do
    case "$1" in
        --store) STORE_DIR="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

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
        emit checkpoint_needs_branchable yes
        note "on macOS machine checkpoint and machine pause refuse a machine that was not started with machine start --branchable, and the error, guest RAM has no file-backed regions, names neither. The flag cannot be added to a running machine; the scripts here always start with it."
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
        emit checkpoint_needs_branchable no
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux. Windows refuses checkpoint and branch; see references/platforms.md."
        ;;
esac

# --- the checkpoint surface this packet uses -----------------------------------

if [ -n "$SMOLVM" ]; then
    ckhelp="$("$SMOLVM" machine checkpoint --help 2>&1)"
    for flag in --store --history --export-from; do
        k="has_$(printf %s "${flag#--}" | tr - _)"
        if grep -q -- "$flag" <<<"$ckhelp"; then emit "$k" yes; else emit "$k" no; blocked=1; fi
    done
    if "$SMOLVM" machine checkpoint-log --help >/dev/null 2>&1; then emit has_checkpoint_log yes; else emit has_checkpoint_log no; blocked=1; fi
    if "$SMOLVM" machine pause --help >/dev/null 2>&1; then emit has_pause yes; else emit has_pause no; fi
    createhelp="$("$SMOLVM" machine create --help 2>&1)"
    if grep -q -- '--at <GENERATION>' <<<"$createhelp"; then emit restore_any_generation yes; else emit restore_any_generation no; blocked=1; fi
    emit scheduler builtin_none
    emit retention builtin_none
fi

# --- memory and disk ---------------------------------------------------------

# The scripts start every machine with --mem 1024. A host that cannot boot that
# inside smolvm's fixed 30 s readiness window fails with "agent did not become
# ready", which names neither memory nor the host.
emit memory_required_mib 1024
mkdir -p "$STORE_DIR" 2>/dev/null
free_kb="$(df -Pk "$STORE_DIR" 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "$free_kb" ]; then
    emit store_free_mib "$((free_kb / 1024))"
    # A capture of a 1 GiB alpine machine wrote about 55 MiB the first time and
    # about 19 MiB after that; restores, the restore base and the capture
    # staging need more. 2 GiB is headroom, not a measurement of any one step.
    if [ "$((free_kb / 1024))" -lt 2048 ]; then
        emit store_space_ok no
        blocked=1
        note "less than 2 GiB free where the checkpoints go. A capture into a full disk publishes nothing, and a machine restored or resumed while the disk is full can be left with guest I/O errors that stop it from being deleted normally (references/traps.md)."
    else
        emit store_space_ok yes
    fi
fi

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/create-source.sh`

```bash
#!/usr/bin/env bash
# Create and start a machine to checkpoint and branch, with state in RAM and on
# disk that a restore or a child can be checked against.
#
# usage: create-source.sh [<name>] [--branch-ready]
#   <name>          default smolskill-src; must start with smolskill- so cleanup.sh deletes it
#   --branch-ready  the workload does its setup and then parks in smolvm-branch-ready,
#                   which a batch branch (branch-point.sh --count) needs
#
# The workload keeps a counter in /tmp, which is tmpfs and therefore RAM: a
# restore or a resume that brings the counter back proves memory came back, not
# only the disk. /root/setup.txt is the disk marker. The machine is started
# --branchable because on macOS a checkpoint is refused without it and the flag
# cannot be turned on for a running machine.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NAME="smolskill-src"
READY=0
for a in "$@"; do
    case "$a" in
        --branch-ready) READY=1 ;;
        -*) printf 'unknown argument: %s\n' "$a" >&2; exit 2 ;;
        *) NAME="$a" ;;
    esac
done

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi
case "$NAME" in
    smolskill-*) ;;
    *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;;
esac

counter='i=0; while true; do i=$((i+1)); echo $i > /tmp/ram_counter; sleep 1; done'
if [ "$READY" -eq 1 ]; then
    # setup, then park; each child continues into the program after --
    workload="echo SETUP_DONE > /root/setup.txt; echo \$RANDOM > /tmp/ram_token; exec smolvm-branch-ready -- sh -c 'echo CHILD=\$SMOLVM_BRANCH_NAME > /root/child.txt; $counter'"
else
    workload="echo SETUP_DONE > /root/setup.txt; echo \$RANDOM > /tmp/ram_token; $counter"
fi

"$SMOLVM" machine create --name "$NAME" --net --mem 1024 --image alpine -- sh -c "$workload" 2>&1 | sed 's/^/  /'
"$here/cleanup.sh" --record "$NAME"
"$SMOLVM" machine start --name "$NAME" --branchable 2>&1 | sed 's/^/  /'

# Wait for a value from the workload, not for the start command to return.
for i in $(seq 1 60); do
    v="$("$SMOLVM" machine exec --name "$NAME" -- cat /root/setup.txt 2>/dev/null)"
    if [ "$v" = "SETUP_DONE" ]; then
        printf 'workload_ready_after_s=%s\n' "$i"
        printf 'ram_token=%s\n' "$("$SMOLVM" machine exec --name "$NAME" -- cat /tmp/ram_token 2>/dev/null)"
        printf 'result=up\n'
        exit 0
    fi
    sleep 1
done
printf 'result=FAILED the workload never wrote /root/setup.txt\n'
exit 1
```

### `scripts/checkpoint.sh`

```bash
#!/usr/bin/env bash
# One capture of a running machine into a checkpoint store, under a unique name,
# then optional retention. This is the command a timer runs: smolvm has no
# checkpoint scheduler and no retention of its own.
#
# usage: checkpoint.sh --name <machine> --store <dir> [--out <dir>] [--label <word>]
#                      [--keep <K>] [--history <N>]
#   --store <dir>    the checkpoint store, created if missing
#   --out <dir>      where the checkpoint directories go (default: the store's
#                    parent); must be on the same filesystem as the store
#   --label <word>   goes into the output name (default: ckpt)
#   --keep <K>       keep the K newest checkpoints with this label in --out,
#                    delete the older ones, then run checkpoint-prune
#   --history <N>    earlier generations each new checkpoint retains (smolvm's
#                    default is 32). Retention frees space only for generations
#                    no kept checkpoint still retains, so bound this too.
#
# What it enforces, each from the engine's own documentation of periodic use:
#   - one capture at a time per source: a run that finds another in progress
#     exits 3 without capturing
#   - a unique output each time: <name>-<label>-<UTC timestamp>.smolcheckpoint
#   - the previous checkpoint stays until the new one is published, and
#     "published" is read back from checkpoint-log, not taken from the exit code
#   - retention removes whole checkpoint directories, then prunes the store

set -uo pipefail

NAME=""
STORE=""
OUT=""
LABEL="ckpt"
KEEP=""
HISTORY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    NAME="$2"; shift ;;
        --store)   STORE="$2"; shift ;;
        --out)     OUT="$2"; shift ;;
        --label)   LABEL="$2"; shift ;;
        --keep)    KEEP="$2"; shift ;;
        --history) HISTORY="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$NAME" ] || [ -z "$STORE" ]; then
    printf 'usage: checkpoint.sh --name <machine> --store <dir> [--out <dir>] [--keep <K>] [--history <N>]\n' >&2
    exit 2
fi

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

mkdir -p "$STORE"
STORE="$(cd "$STORE" && pwd)"
[ -n "$OUT" ] || OUT="$(dirname "$STORE")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# One capture at a time per source. mkdir is atomic on every filesystem this
# runs on, and macOS has no flock(1). A lock whose owner is gone is taken over.
LOCK="$STORE/.smolskill-capture-$NAME.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    owner="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
        printf 'result=skipped\n'
        printf 'note=a capture of %s is still running (pid %s). Run one capture at a time per source: overlapping captures compete for memory and I/O and finish no sooner. Lengthen the interval.\n' "$NAME" "$owner"
        exit 3
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" || { printf 'result=FAILED could not take the capture lock %s\n' "$LOCK"; exit 1; }
fi
printf '%s\n' "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="$OUT/$NAME-$LABEL-$stamp.smolcheckpoint"
if [ -e "$output" ]; then
    printf 'result=FAILED %s already exists; smolvm never overwrites an output, and two captures in one second collide on this name\n' "$output"
    exit 1
fi

hist=()
[ -n "$HISTORY" ] && hist=(--history "$HISTORY")

start="$(date +%s)"
out="$("$SMOLVM" machine checkpoint --name "$NAME" --store "$STORE" --output "$output" ${hist[@]+"${hist[@]}"} 2>&1)"
rc=$?
end="$(date +%s)"
printf '%s\n' "$out" | sed 's/^/  /'
printf 'output=%s\n' "$output"
printf 'capture_s=%s\n' "$((end - start))"

# The exit code is not the assertion. A checkpoint is usable once the store
# lists it as its own generation, so read that back.
log="$("$SMOLVM" machine checkpoint-log "$output" 2>&1)"
if [ "$rc" -ne 0 ] || ! printf '%s' "$log" | grep -q '(this checkpoint)'; then
    printf 'published=no\n'
    printf 'result=FAILED the capture did not publish; the previous checkpoint is untouched\n'
    case "$out" in
        *"no file-backed regions"*)
            printf 'note=on macOS a checkpoint needs the machine started with machine start --branchable, and this one was not. The flag cannot be turned on for a running machine.\n' ;;
        *"No space left"*)
            printf 'note=the disk is full. A failed capture publishes nothing, so delete old checkpoints and run machine checkpoint-prune before the next attempt.\n' ;;
    esac
    exit 1
fi
printf 'published=yes\n'
printf 'generation=%s\n' "$(printf '%s\n' "$log" | awk '$1=="~0"{print $2}')"
printf 'generations_retained=%s\n' "$(printf '%s\n' "$log" | grep -c '^~')"

# Retention: only after the new checkpoint is published, and by whole
# directory. Output names sort by time because the stamp is UTC and fixed width.
if [ -n "$KEEP" ]; then
    n=0
    for d in $(ls -1d "$OUT/$NAME-$LABEL"-*.smolcheckpoint 2>/dev/null | sort -r); do
        n=$((n + 1))
        [ "$n" -le "$KEEP" ] && continue
        rm -rf "$d" && printf 'deleted=%s\n' "$d"
    done
    "$SMOLVM" machine checkpoint-prune --store "$STORE" 2>&1 | sed 's/^/  /'
    printf 'kept=%s\n' "$(ls -1d "$OUT/$NAME-$LABEL"-*.smolcheckpoint 2>/dev/null | wc -l | tr -d ' ')"
fi

printf 'store_size=%s\n' "$(du -sh "$STORE" 2>/dev/null | cut -f1)"
printf 'result=captured\n'
```

### `scripts/schedule.sh`

```bash
#!/usr/bin/env bash
# Run checkpoint.sh on an interval, in the foreground, and say whether the
# interval is long enough. For a test or a session an agent is watching; for a
# schedule that outlives the session, put checkpoint.sh under cron, a systemd
# timer or launchd instead (references/scheduling.md).
#
# usage: schedule.sh --name <machine> --store <dir> --every <seconds> --times <N>
#                    [--keep <K>] [--history <N>] [--out <dir>]

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
EVERY=""
TIMES=""
pass=()
while [ $# -gt 0 ]; do
    case "$1" in
        --every) EVERY="$2"; shift ;;
        --times) TIMES="$2"; shift ;;
        --name|--store|--keep|--history|--out|--label) pass+=("$1" "$2"); shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$EVERY" ] || [ -z "$TIMES" ]; then
    printf 'usage: schedule.sh --name <machine> --store <dir> --every <seconds> --times <N> [--keep <K>]\n' >&2
    exit 2
fi

ok=0
failed=0
longest=0
for run in $(seq 1 "$TIMES"); do
    start="$(date +%s)"
    out="$("$here/checkpoint.sh" ${pass[@]+"${pass[@]}"} 2>&1)"
    rc=$?
    took=$(( $(date +%s) - start ))
    [ "$took" -gt "$longest" ] && longest="$took"
    printf 'run=%s rc=%s took_s=%s %s\n' "$run" "$rc" "$took" "$(printf '%s\n' "$out" | grep -E '^(output|result|kept|store_size)=' | tr '\n' ' ')"
    if [ "$rc" -eq 0 ]; then ok=$((ok + 1)); else failed=$((failed + 1)); printf '%s\n' "$out" | sed 's/^/  /'; fi
    if [ "$took" -ge "$EVERY" ]; then
        printf 'note=this capture took %ss and the interval is %ss. Set the interval from the complete capture time, not the source pause.\n' "$took" "$EVERY"
    fi
    [ "$run" -lt "$TIMES" ] && sleep $(( EVERY > took ? EVERY - took : 0 ))
done
printf 'captures_ok=%s\n' "$ok"
printf 'captures_failed=%s\n' "$failed"
printf 'longest_capture_s=%s\n' "$longest"
if [ "$failed" -eq 0 ]; then printf 'result=schedule_ok\n'; else printf 'result=FAILED\n'; exit 1; fi
```

### `scripts/restore.sh`

```bash
#!/usr/bin/env bash
# Restore a checkpoint, or an earlier generation it retains, into a new machine
# and start it.
#
# usage: restore.sh --from <checkpoint> --name <new> [--at <~N|id>]
#
# The restore path is `machine create --from`; there is no `machine restore`.
# The new machine is started --branchable so it can itself be checkpointed,
# paused and branched on every host.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
FROM=""
NAME=""
AT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --from) FROM="$2"; shift ;;
        --name) NAME="$2"; shift ;;
        --at)   AT="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$FROM" ] || [ -z "$NAME" ]; then
    printf 'usage: restore.sh --from <checkpoint> --name <new> [--at <~N|id>]\n' >&2
    exit 2
fi
case "$NAME" in smolskill-*) ;; *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;; esac

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
[ -n "$SMOLVM" ] || { printf 'smolvm not found; set SMOLVM to its path\n' >&2; exit 2; }

at=()
[ -n "$AT" ] && at=(--at "$AT")
"$SMOLVM" machine create --name "$NAME" --from "$FROM" ${at[@]+"${at[@]}"} 2>&1 | sed 's/^/  /'
# Read the list first: under pipefail, grep -q closing the pipe early can fail
# the pipeline and report a machine missing that exists.
listing="$("$SMOLVM" machine list 2>/dev/null)"
if ! printf '%s\n' "$listing" | grep -q "^$NAME "; then
    printf 'result=FAILED no machine was created\n'
    exit 1
fi
"$here/cleanup.sh" --record "$NAME"
start="$(date +%s)"
"$SMOLVM" machine start --name "$NAME" --branchable 2>&1 | sed 's/^/  /'
printf 'start_s=%s\n' "$(( $(date +%s) - start ))"
state="$("$SMOLVM" machine list 2>/dev/null | awk -v n="$NAME" '$1==n{print $2}')"
printf 'state=%s\n' "$state"
[ "$state" = running ] && printf 'result=restored\n' || { printf 'result=FAILED\n'; exit 1; }
```

### `scripts/branch-point.sh`

```bash
#!/usr/bin/env bash
# Branch a machine and take a checkpoint of the same point, so the state the
# children started from outlives them. A branch's captured generation lives on
# this host only; the checkpoint is the copy you can keep, export and restore.
#
# usage: branch-point.sh --from <source> --store <dir> --count <N> --name-prefix <prefix>
#        branch-point.sh --from <source> --store <dir> --name <child>
#   --count/--name-prefix  a batch. The source's workload must park in
#                          smolvm-branch-ready; the checkpoint is taken while it
#                          is parked, so it is the exact state every child starts from.
#   --name                 one child. The checkpoint is taken first and the
#                          branch follows, a second or two later, so the two
#                          points differ by whatever the source did in between.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
FROM=""
STORE=""
COUNT=""
PREFIX=""
CHILD=""
while [ $# -gt 0 ]; do
    case "$1" in
        --from)        FROM="$2"; shift ;;
        --store)       STORE="$2"; shift ;;
        --count)       COUNT="$2"; shift ;;
        --name-prefix) PREFIX="$2"; shift ;;
        --name)        CHILD="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$FROM" ] || [ -z "$STORE" ] || { [ -z "$CHILD" ] && { [ -z "$COUNT" ] || [ -z "$PREFIX" ]; }; }; then
    printf 'usage: branch-point.sh --from <source> --store <dir> (--count <N> --name-prefix <p> | --name <child>)\n' >&2
    exit 2
fi
case "${PREFIX}${CHILD}" in
    smolskill-*) ;;
    *) printf 'children must be named smolskill-... so cleanup.sh deletes them\n' >&2; exit 2 ;;
esac

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
[ -n "$SMOLVM" ] || { printf 'smolvm not found; set SMOLVM to its path\n' >&2; exit 2; }

if [ -n "$COUNT" ]; then
    # Parked means PID 1 of the workload is the helper. pgrep -f is not a test
    # for it: it matches the sh -c that runs the check, whose text names the helper.
    parked=no
    for i in $(seq 1 120); do
        if "$SMOLVM" machine exec --name "$FROM" -- sh -c 'tr "\0" " " < /proc/1/cmdline' 2>/dev/null | grep -q '^smolvm-branch-ready'; then
            parked=yes; printf 'source_parked_after_s=%s\n' "$i"; break
        fi
        sleep 1
    done
    if [ "$parked" != yes ]; then
        printf 'result=FAILED the source never parked in smolvm-branch-ready, so a batch branch would wait for a branch point that is not coming. Its workload has to run smolvm-branch-ready -- <program> after its setup (create-source.sh --branch-ready does), or branch one child with --name.\n'
        exit 1
    fi
fi

ck="$("$here/checkpoint.sh" --name "$FROM" --store "$STORE" --label branchpoint 2>&1)"
printf '%s\n' "$ck" | sed 's/^/  /'
checkpoint="$(printf '%s\n' "$ck" | sed -n 's/^output=//p')"
if ! printf '%s' "$ck" | grep -q '^result=captured'; then
    printf 'result=FAILED no checkpoint of the branch point, so no branch was taken\n'
    exit 1
fi
printf 'checkpoint=%s\n' "$checkpoint"

if [ -n "$COUNT" ]; then
    out="$("$SMOLVM" machine branch --from "$FROM" --count "$COUNT" --name-prefix "$PREFIX" 2>&1)"
    children="$(seq 0 $((COUNT - 1)) | sed "s/^/$PREFIX-/")"
else
    out="$("$SMOLVM" machine branch --from "$FROM" --name "$CHILD" 2>&1)"
    children="$CHILD"
fi
printf '%s\n' "$out" | sed 's/^/  /'
made=0
# Read the list once: under pipefail, grep -q closing the pipe early can fail
# the pipeline and report a child missing that exists.
listing="$("$SMOLVM" machine list 2>/dev/null)"
for c in $children; do
    "$here/cleanup.sh" --record "$c"
    if printf '%s\n' "$listing" | grep -q "^$c "; then made=$((made + 1)); printf 'child=%s\n' "$c"; fi
done
# The source is frozen on some hosts after a branch and running on others; read
# which, rather than assuming.
printf 'source_state=%s\n' "$(printf '%s\n' "$listing" | awk -v n="$FROM" '$1==n{print $2}')"
if [ "$made" -eq "$(printf '%s\n' "$children" | grep -c .)" ]; then
    printf 'result=branched\n'
else
    printf 'result=FAILED %s of the children exist\n' "$made"
    exit 1
fi
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
# usage: cleanup.sh [--record <name>] [--reap] [--purge] [--restore-base] [--checkpoints <dir>...]
#   --record <name>       add a machine name to the state file and exit
#   --reap                kill leftover VM processes (see the warning it prints)
#   --purge               also remove the state file once the list is empty
#   --restore-base        also remove smolvm's clone of the last restored checkpoint
#   --checkpoints <dir>   also remove these checkpoint directories and stores; last
#
# Checkpoints hold the machine's memory and disks, so they are sensitive, and
# smolvm keeps one more copy of its own: vms/_restore-base is a clone of the most
# recently restored checkpoint, kept to make the next restore cheaper, and it
# outlives every machine and every checkpoint file.

set -uo pipefail

PACKET="branch-and-checkpoint"
PREFIX="smolskill-"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
STATE_FILE="$STATE_DIR/$PACKET.machines"

reap=0
purge=0
restore_base=0
CHECKPOINTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --record)
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$2" >> "$STATE_FILE"
            exit 0
            ;;
        --reap)  reap=1 ;;
        --purge) purge=1 ;;
        --restore-base) restore_base=1 ;;
        --checkpoints) shift; CHECKPOINTS="$*"; break ;;
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
        # A child is gone once its source was deleted with --cascade, and on
        # v1.18.2 `machine stop` on a name that does not exist leaves an empty
        # directory under vms/. Act only on names still listed.
        "$SMOLVM" machine list </dev/null 2>/dev/null | awk 'NR>2{print $1}' > "$STATE_DIR/.listed" 2>/dev/null
        grep -qx -- "$name" "$STATE_DIR/.listed" || continue
        "$SMOLVM" machine stop   --name "$name" >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 1b. Checkpoints and stores named on the command line, then the restore base.
for d in ${CHECKPOINTS:-}; do
    case "$d" in *.smolcheckpoint|*store*) ;; *)
        printf 'skipping %s: not a .smolcheckpoint or a store directory\n' "$d"; continue ;;
    esac
    [ -e "$d" ] && rm -rf "$d" && printf 'removed=%s\n' "$d"
done
if [ "$restore_base" -eq 1 ] && [ -d "$VMS_DIR/_restore-base" ]; then
    rm -rf "$VMS_DIR/_restore-base" "$VMS_DIR/_restore-base.lock" && printf 'removed=%s\n' "$VMS_DIR/_restore-base"
elif [ -d "$VMS_DIR/_restore-base" ]; then
    printf 'restore_base=present %s (the last restored checkpoint; --restore-base removes it)\n' "$(du -sh "$VMS_DIR/_restore-base" 2>/dev/null | cut -f1)"
fi

rm -f "$STATE_DIR/.listed"

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

## Checkpoint, restore, pause and branch traps

Each entry was hit on v1.18.2 on 2026-09-24 unless it says otherwise.

### `--branchable` is decided at start, and macOS needs it for more than branching

`machine branch` against a machine started without it, on either host:

```
Error: agent operation failed: fork: machine 'smolskill-sfx' was not started as branchable, so it
has no copy-on-write memory to branch from. Restart it with `smolvm machine start --name
smolskill-sfx --branchable`; branchability is decided at start time and cannot be turned on for an
already-running machine.
```

That message is clear. The macOS one for `checkpoint` and `pause` is not:

```
Error: agent operation failed: checkpoint machine: libkrun save failed: ERR EIO capture VM: VM
snapshot/restore failed: retain COW guest-memory generation: guest RAM has no file-backed regions
```

`pause` prints the same text, because a pause is a checkpoint underneath, and the machine keeps
running. On Linux aarch64 both succeeded without the flag: a checkpoint of 55 MiB with a 1.242 s
pause, and a pause and resume. Start every machine you might checkpoint with `--branchable`.

### `--output` must end in `.smolcheckpoint`, even when it is a directory

```
Error: config operation failed: checkpoint machine: output must end in .smolcheckpoint
```

for `-o ./x.checkpoint`, and the same for `--store ./st -o ./inc1`, where the output is a directory
and the help calls it one.

### The exit code of a capture is not the proof

A capture is usable once it has been durably published, which `checkpoint-log <output>` shows as the
`~0` line ending `(this checkpoint)`. `scripts/checkpoint.sh` reads that back before it deletes any
older checkpoint. During this run the host disk filled and an export failed with `tar error: No
space left on device (os error 28)`; a scheduler that trusted a zero exit elsewhere and deleted the
previous checkpoint would have been left with none.

### `--keep` does not bound the store on its own

Each stored checkpoint retains up to `--history` earlier generations, 32 by default, and deleting
the directory of a generation that a kept checkpoint retains frees nothing. With `--keep 2
--history 2` the store grew 59, 76, 95, 114 MB over four captures. `references/scheduling.md` has
how to pick the two together.

### A restored branch point is not a parked source

A checkpoint taken while the source is parked in `smolvm-branch-ready` holds exactly the state its
children start from. Restoring it does not give you a parked source back: on start the helper
releases, and the workload runs the program after `--` with an empty `SMOLVM_BRANCH_NAME`, so
`/root/child.txt` in that test read `CHILD=`. A batch branch from the restored machine then waits
its full `--ready-timeout`, 10 minutes by default, and fails with

```
A batch branch checkpoints the source at a point its workload declares by running
`smolvm-branch-ready` after setup ... either add the call, raise --ready-timeout, or take single
`--name` branches, which checkpoint the source wherever it is.
```

A single `--name` branch from the restored machine worked and carried the source's state. To fan out
again from a kept branch point, branch it one child at a time or restore it once per worker, and
give each its identity some other way, since the branch variables are empty.

### Detecting a parked source: `pgrep -f` always matches

`smolvm machine exec --name src -- sh -c 'pgrep -f smolvm-branch-ready'` succeeds whether or not the
source is parked, because the `sh -c` running it has the string in its own command line. Read PID 1
instead, which is the workload:

```bash
smolvm machine exec --name src -- sh -c 'tr "\0" " " < /proc/1/cmdline' | grep -q '^smolvm-branch-ready'
```

A parked source shows `smolvm-branch-ready -- sh -c ...`; a released one shows the program after
`--`.

### `machine list | grep -q` under `pipefail`

`set -o pipefail` plus `smolvm machine list | grep -q name` can fail for a machine that exists:
`grep -q` exits on the first match, the list's next write hits a closed pipe, and the pipeline's
status is the list's failure. Two scripts in this packet reported `result=FAILED no machine was
created` for machines that were running before this was caught. Read the list into a variable, then
search it.

### A paused machine refuses `stop` and `start`, and a failed resume can be retried

```
Error: agent operation failed: stop: machine has saved execution; use resume or delete
Error: agent operation failed: start: machine has saved execution; use resume
```

A restored machine paused while the host disk was full failed its resume with `extract paused
checkpoint: failed to unpack ...`. After space was freed the same `machine resume` succeeded, and
the counter the workload keeps in RAM read 14 against 8 before the pause, then kept counting.

### A full disk leaves machines that `delete --force` will not remove

A machine restored and started while the disk was full came up with its overlay failing. Its
delete, later, with space available:

```
Error: agent operation failed: stop agent: guest did not confirm filesystem synchronization; left
the VM alive for retry: agent operation failed: shutdown ack: freeze /oldroot/mnt/overlay: I/O error
(os error 5)
```

exit 1, still `running`. `scripts/cleanup.sh --reap` killed its VM process, after which `delete
--force` removed it. **`--reap` kills every VM process under this `HOME`**, not only that one, so
use it when nothing else there should keep running. `scripts/preflight.sh` checks free space for
this reason.

### `du` overstates what a restore costs

Restores are copy-on-write over the checkpoint. On macOS three restores of one checkpoint moved the
volume's free space by 22 MB at create and 65 MB at start, about 29 MB a machine, while `du` on
each machine's directory said 150 to 190 MB. On Linux each restored machine's directory holds small
`qcow2` layers over `.smolcheckpoint-*.raw` bases, 29 MB by `du`. Measure a restore budget with
`df` before and after.

### smolvm keeps the last restored checkpoint after you delete it

On macOS `vms/_restore-base` under smolvm's cache is, in the source's words, a pristine clone of the
most recently restored checkpoint, kept so the next restore writes only the chunks that differ. It
was 243 MB here, with the checkpoint's `memory.bin` inside, and it stayed after every machine and
every checkpoint file was deleted. `smolvm serve start`'s reclaim did not touch it.
`scripts/cleanup.sh --restore-base` removes it. None was created on Linux aarch64.

### `machine stop` on a missing name leaves an empty directory

On v1.18.2, `smolvm machine stop --name <name>` for a machine that does not exist leaves an empty
directory under the VM cache. A cleanup that stops each recorded name after `--cascade` has already
deleted the children leaves one per child, which a leak check counting directories then reports.
This packet's cleanup stops only names still listed.

### Environment given to a restore reaches `exec`, not the resumed workload

`machine create --from <checkpoint> -e ROLE=seven`: `machine exec` saw `ROLE=seven`, and the resumed
workload's own environment did not have it. The workload is the process that was running when the
checkpoint was taken, and its environment came with it.

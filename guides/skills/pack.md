---
title: "Pack: ship a prepared machine as one file"
---

# Pack: ship a prepared machine as one file

Turns an image, or a machine already provisioned, into a single self-contained artifact that runs on another compatible host. Use when shipping a prepared environment as one file, when a packed artifact runs but the state installed into it is missing, when pack create fails because the VM it boots to pull or export could not start, when an older release refuses to export a branched machine, or when deciding whether to pack from an image or from a machine. Do not use it to keep a machine you re-enter, which is the dev-env packet, or to run untrusted code, which is the throwaway-machine packet.

Verified on **smolvm v1.22.2** on macOS arm64, 2026-10-03, and on **v1.14.6** on Linux aarch64,
2026-09-11; the Linux host could not run the packing steps on v1.18.2 or v1.22.2, for the reason in
"Platform arms". Done means the artifact runs a command in a real VM and, for a machine pack, **the state you installed is still
inside it**.
The Linux runs used the scripts of their date; this version's preflight and cleanup scripts ran
on Linux aarch64 on v1.22.2 on 2026-10-03.

**The assertion that matters is a value, not a boot.** A pack that lost its rootfs still boots,
still prints a guest kernel and still exits zero. The only thing that separates a good artifact
from an empty one is a marker written into the source machine before packing and read back out of
the artifact afterwards, which is what `pack-machine.sh` and `verify-pack.sh` do between them.

## Procedure

**1. Preflight.** Read-only: starts no VM, packs nothing.

```bash
scripts/preflight.sh
```

The lines to read are `exporter_memory_ok` and `image_vm_memory_ok`. Both pack paths boot a
helper VM before they write anything. `pack create --image` pulls the image in a VM fixed at 4
vCPUs and 8192 MiB on every release here. `pack create --from-vm` boots an export helper: fixed at
8192 MiB through v1.16.1, when a host that could not seat it failed with `agent did not become
ready within 30 seconds`, which mentions neither memory nor the helper; from v1.16.2 it asks for
4096 MiB (on Linux half of the available memory when that is less, never under 1024),
`SMOLVM_EXPORT_HELPER_MEMORY_MIB=<MiB>` sets it, and a failed start says `The export helper asked
for N MiB of memory` and names the variable. `exporter_memory_mib` is the figure this binary will
ask for, except under a cgroup memory limit on Linux, where smolvm asks for less. Both lines are
warnings and not gates, because the figures are caps rather than reservations: see "What the
memory lines do and do not promise". From v1.16.1 the export helper reuses the machine's cached
image layers instead of pulling the image again and prints `Reusing
the machine's cached image layers...`; on macOS arm64 on v1.16.1 that export completed in 1.2 s
with `exporter_memory_ok=no` reported by the same preflight moments earlier, 2026-09-15.

**2. Pack from an image**, when you want a runnable artifact of a stock image.

```bash
scripts/pack-image.sh                       # alpine, ./from-image
scripts/pack-image.sh python:3.12-alpine ./mypack
```

This path boots the 8192 MiB pull VM, so `image_vm_memory_ok` is its line; `--mem` sets the
artifact's memory and does not reach that VM. **If you pass a custom output, pass it to the
verify step too** (`verify-pack.sh --image ./mypack`), or that step finds nothing at its defaults
and tells you so rather than passing.

**3. Pack from a machine you provisioned**, when the point is the state in it.

```bash
scripts/pack-machine.sh                     # smolskill-golden, ./from-vm
```

It creates the machine with a workload that stays up, waits for a value from it, writes a marker,
**asserts the marker on the source**, stops the machine and exports it. The source assertion is
not ceremony: packing a machine whose provisioning silently failed produces an artifact that runs
perfectly and contains nothing, and nothing downstream will tell you.

**Packing a machine that already exists**, the user's own rather than one `pack-machine.sh` made:
the script refuses any name without the `smolskill-` prefix, so run its sequence by hand. **Stop
the machine first**: `--from-vm` packs a stopped machine's snapshot and refuses a running one. A
`machine start` afterwards is how the machine comes back. A machine provisioned by hand is verified
with a file of the user's own: `--marker-path` names it and `--marker` its expected last line.

```bash
smolvm machine exec --name myapp -- tail -1 /root/provisioned.txt   # note the value on the source
smolvm machine stop --name myapp
smolvm pack create --from-vm myapp --output ./myapp-portable --single-file   # one file, no sidecar
scripts/verify-pack.sh --machine ./myapp-portable --marker-path /root/provisioned.txt --marker <that value>
smolvm machine start --name myapp                                    # the machine comes back
```

With no file of the user's to check, write the packet's marker before the stop,
`smolvm machine exec --name myapp -- sh -c 'echo PACKED_STATE_PRESENT > /marker.txt'`, verify
without `--marker-path`, and remove `/marker.txt` after the start.

`verify-pack.sh --machine` reads the marker out of a `--single-file` artifact as it does from a stub
with a sidecar. With no image artifact beside it, expect `image_pack=skipped` and
`result=artifacts_good (1 of 2 artifacts)`; the `what the artifact says it is` block reads the
sidecar, so a single file prints none.

**4. Verify.** Both halves.

```bash
scripts/verify-pack.sh
```

```
image_pack_is_a_vm=ok (Linux)
image_pack_second_run=ok (SECOND_RUN_OK)
pack_cache_entries=2
image_pack_reused_cache=ok (2)
machine_pack_carried_rootfs=ok (PACKED_STATE_PRESENT)
machine_pack_is_a_vm=ok (Linux)
result=artifacts_good (2 of 2 artifacts)
```

`machine_pack_carried_rootfs` is the load-bearing line. The rest is context.

**Verifying nothing is not a pass.** Point it at artifacts that are not there and it says
`result=nothing_verified` and exits non-zero, because a green line over zero artifacts is the same
false clean the marker exists to prevent.

**5. Clean up.**

```bash
scripts/cleanup.sh --purge --artifacts ./from-image ./from-vm
```

`cleanup.sh` waits up to 20 seconds, polling the machine list, and prints `waiting=up to 20s`
first: an ephemeral machine's entry retires after its run returns.

It prunes each recorded machine while it still exists, deletes it, removes both stubs and their
sidecars, and runs `pack prune`, which keeps the five most recently used extractions, so the two
this procedure made stay; `smolvm pack prune --all` removes every unused one, theirs included.
**`smolvm machine prune` with no argument does not run on this release**; the form is
`--name <NAME>`.

## Forwarding the SSH agent to an artifact

From v1.18.1 the artifact's own `run` and `start` take `--ssh-agent`, the same bridge `machine
run` has: the guest gets `SSH_AUTH_SOCK=/tmp/ssh-agent.sock` and the host agent signs, so no key
enters the artifact or the VM.

```bash
./from-image run --net --ssh-agent -- sh -c 'apk add -q openssh-client; ssh-add -l'
./from-image start --net --ssh-agent
./from-image exec -- sh -c 'apk add -q openssh-client; ssh-add -l'
```

Measured on macOS arm64 on v1.18.2 with a throwaway key in a throwaway agent, and the artifact's
own `run --ssh-agent` again on v1.22.2: both forms listed that key's fingerprint from inside the
guest, a `run` without the flag had `SSH_AUTH_SOCK` unset, and with the host variable empty the flag stops before booting with
`--ssh-agent: SSH_AUTH_SOCK is not set. Start an SSH agent with: eval $(ssh-agent) && ssh-add`.
**Forward the agent only to an artifact you trust**: the guest can ask for signatures for as long
as it runs, and an artifact is a filesystem somebody else prepared.

## What an artifact is, and what it carries

A pack is **two files**: a stub binary and a `<stub>.smolmachine` sidecar. `--output` names the
**stub**; the sidecar is created for you. Keep them together.

```
Mode:       container
Image:      python:3.12-alpine
Platform:   linux/arm64
CPUs:       4
Memory:     8192 MiB
Checksum:   94baf297
```

That `Memory` is the **packed artifact's** runtime memory, which `pack create --mem` can set. It
is not the export helper's, which `SMOLVM_EXPORT_HELPER_MEMORY_MIB` sets from v1.16.2, nor the
image pull VM's, which is fixed at 8192 MiB.

A machine pack carries the root filesystem and the workload settings. It does not carry
`/workspace`, which lives on the storage disk, unless `pack create --from-vm --include-workspace`
is passed, nor host mounts, remote volumes, credential bindings (`pack create` warns about the
last two), or the source machine's CPU and memory sizes.

## What the memory lines do and do not promise

A helper VM's memory is a **cap, not a reservation**, so a host reporting less available memory
can still pack. Measured on v1.14.6, when the export helper was fixed at 8192 MiB: the export
succeeded on a Mac whose preflight reported `free_memory_mib=4990`, and on v1.16.1 an export
completed in 1.2 s with `exporter_memory_ok=no`. On a small Linux host the fixed figure was the
binding constraint and the export failed with the unnamed ready timeout. So the preflight **warns
and does not block**, and `result=ready` with `exporter_memory_ok=no` or `image_vm_memory_ok=no`
means "this may work, and if it does not, here is why". From v1.16.2 the export helper's failure
names its figure, and a lower `SMOLVM_EXPORT_HELPER_MEMORY_MIB` is the fix; the image pull VM has
no such setting.

## Traps

Full detail with the evidence in `references/traps.md`. The ones that cost the most:

- **`--output` names the stub, not the sidecar.** Passing `--output foo.smolmachine` fails; the
  scripts refuse it before the CLI does.
- **"One file" needs `--single-file`, and the default is two.** By default `pack create` writes the
  stub plus a `.smolmachine` sidecar and the CLI says `Note: Keep the .smolmachine file alongside
  the binary`; the stub on its own prints smolvm's usage and exits. `--single-file` writes one
  executable with no sidecar, and its own help warns it `may have issues with macOS notarization`.
- **The stub takes a subcommand, and a bare `--` is rejected** with a tip that does not mention
  `run`. The working form is `./from-vm run -- sh -c '...'`.
- **`pack run` takes `--sidecar <PATH>`, not a positional path**, and getting it wrong reports
  that your sidecar is not an executable in `$PATH`.
- **Reported sizes understate the stub on disk**, by about 8.4 MB on Linux aarch64 and about
  10 MB on macOS arm64 on v1.14.6, 10.4 MB on macOS on v1.22.2: `pack create` prints its sizes,
  then signs the stub on macOS, then appends the compressed runtime libraries to it. The
  `Assets:` figure is accurate to a few KB.
- **A branched machine packs from v1.16.1, and carries both states**; v1.14.6 refused it at export.
  Start the source `--branchable`, `machine branch --from <src> --name <child>`, write a marker in the child, stop
  it, `pack create --from-vm <child>`, and the artifact prints the source's `BASE_STATE` and the
  child's `CHILD_ONLY`. The branch must be stopped before it will pack.
- **Branchability is decided at `machine start`, not at `create`.** `machine branch` against a
  machine started without it refuses with `was not started as branchable, so it has no
  copy-on-write memory to branch from ... branchability is decided at start time and cannot be
  turned on for an already-running machine`, and `machine create --branchable` is not a flag.
- **A checkpoint restore packs and carries its rootfs**, and the restore path is
  `machine create --from`. There is no `machine restore` subcommand. **On macOS before v1.20.0
  taking the checkpoint needs `--branchable`**, and the error, `guest RAM has no file-backed
  regions`, names neither the flag nor the precondition. From v1.20.0 a checkpoint file does not
  need it and a `--store` capture still does; `references/traps.md` has the releases. Linux
  aarch64 took one without it on v1.18.2. A machine created from a pack can be checkpointed from
  v1.18.0, and `create --from` restores the newest generation a checkpoint carries; `--at ~N` picks an earlier
  one, which `branch-and-checkpoint` covers.
- **On Linux, `SMOLVM_DATA_DIR` moves where the agent rootfs is looked up and the installer does
  not write it there**, so an isolated data root needs the rootfs copied in before the first boot.

## Security defaults, and why they are the defaults

- **An artifact is a filesystem you are handing to someone else.** Whatever was in the source
  machine's rootfs is in the sidecar, including anything a provisioning step left in a shell
  history, a cache, or a file under `/root`. The marker this packet writes is deliberately inert;
  treat anything else you put in the source as published.
- **Packing does not narrow what the artifact may do.** The recorded entrypoint, command,
  environment and network setting come from the source, so a machine created with `--net`
  produces an artifact that expects a network. Decide that on the source, not afterwards. CPUs and
  memory do not come from the source: they are `pack create --cpus` and `--mem`, else the
  Smolfile, else 4 and 8192 MiB.
- **The scripts pack only a machine they created**, named under the `smolskill-` prefix and
  recorded in a state file, and cleanup deletes only those and, through `--cascade`, any machine
  branched from one of them, whatever its name. Any other machine you or another session made by
  hand is never exported and never deleted.
- **`pack run` takes the forked boot path.** From v1.20.2 Ctrl-C or a kill of the CLI takes its VM
  with it: on macOS arm64 on v1.22.2 both processes of a packed `run` were gone 2 s after `SIGINT`
  and after `SIGKILL`. Before v1.20.2 a cancelled run left a VM the CLI could not see, and
  `cleanup.sh` is the way to stop one there; its process scan catches both VM shapes.
- **Nothing here escalates privilege**, edits smolvm configuration or touches `~/.smolvm`.

## Platform arms

- **macOS arm64**: verified on v1.22.2, including the SSH agent forwarding, a branched source, and
  a pack of a restored machine on v1.18.2. An extra `Signing binary with hypervisor entitlements`
  step runs here that does not on Linux.
- **Linux aarch64**: verified on v1.14.6. Not run on v1.18.2 or v1.22.2: `pack create --image`
  failed with `agent did not become ready within 30 seconds`, with or without `--mem 1024`,
  because the pull helper does not take `--mem`, and the golden machine's start failed the same
  way. That host could not boot guests above 2048 MiB in time, which the `install` packet's traps
  record. The preflight on v1.18.2 said `exporter_memory_ok=yes` there with 10386 MiB free: free
  memory was not what failed, so read the memory lines as hints about the helper VMs only.
- **Linux x86_64**: verified in the material behind this packet on v1.14.6, including the branched
  and restored cases. Not re-run here.
- **Windows x86_64**: `references/windows.md`. **On v1.22.2 an artifact is created and cannot
  be run there**, re-run on 2026-10-03 on Windows 11 Home build 10.0.26200 UBR 9457: both paths pack, and running any artifact,
  through its stub, `pack run --sidecar` or `machine create --from`, fails extracting its first
  layer with `os error 123`. v1.16.1 and v1.14.6 run the same pack on the same host; v1.18.2 and
  every later release tried fail. On v1.14.6 both paths worked end to end, with the marker read
  back out of the artifact. The stub is written without `.exe` and will not run until it and its
  sidecar are renamed.

**Both hosts run here produce `linux/arm64` artifacts**, so two hosts is two hosts and not two
artifact architectures. The `linux/amd64` side rests on the x86_64 run above.

## Eval prompts, and what they produced

Run 2026-09-11 PT against v1.14.6 from the published release, on macOS 26.6.2 arm64 and Lima
`linux-kvm` (Ubuntu 24.04 aarch64). Output is verbatim.

**1. "Ship this provisioned machine to another host as one file."**

Both hosts, through `pack-machine.sh` then `verify-pack.sh`:

```
source_marker=PACKED_STATE_PRESENT
result=packed

machine_pack_carried_rootfs=ok (PACKED_STATE_PRESENT)
machine_pack_is_a_vm=ok (Linux)
result=artifacts_good
```

macOS produced a 31572 KB sidecar in 3 s, Linux aarch64 a 31491 KB sidecar in 32 s.

**2. "The artifact runs fine but the thing I installed is not in it."**

That is the failure this packet is shaped against, and the answer is that running proves nothing.
`verify-pack.sh` asserts the marker rather than the boot, and `pack-machine.sh` refuses to export
at all if the marker is not on the source first:

```
result=FAILED the source does not carry the marker, so packing it would produce an empty artifact
```

The image pack is the control: it runs and does not carry the machine's state. State written
under `/workspace` needs `--include-workspace`.

**3. "`pack create --from-vm` fails with `agent did not become ready within 30 seconds` and says
nothing else."**

On v1.14.6 the preflight of that date was the only place that failure was named:

```
exporter_memory_mib=8192
free_memory_mib=4990
exporter_memory_ok=no
note=free memory is below the exporter's fixed 8192 MiB. If pack create --from-vm fails with
'agent did not become ready within 30 seconds', that is this, and the message will not mention
memory. Packing from an image starts no exporter and is unaffected.
```

On the hosts here the export then **succeeded anyway**, on the Mac reporting 4990 MiB, which is
why that line warns rather than blocks.

That is the v1.14.6 output, when the export helper was fixed at 8192 MiB. From v1.16.2 the
failure names the figure it asked for and `SMOLVM_EXPORT_HELPER_MEMORY_MIB`, and
`exporter_memory_mib` is what the binary will ask for, 4096 or less. The recorded note's last
sentence was never right: `pack create --image` boots its own 8192 MiB VM on every release here.

## Re-verified on v1.22.2

Run 2026-10-03 PT against v1.22.2 from the published release, checksum checked, under an isolated
`HOME` on macOS 27.0.1 arm64, twice, the second time from a fresh `HOME`. On Lima `linux-kvm`
(Ubuntu 24.04 aarch64) on 2026-10-03 guests above 2048 MiB timed out.

macOS: `result=artifacts_good (2 of 2 artifacts)` with `machine_pack_carried_rootfs=ok
(PACKED_STATE_PRESENT)`, the stub understated by 10657 KB, a branched machine's artifact printing
`BASE_STATE` and `CHILD_ONLY`, a checkpoint of a machine started without `--branchable`, and the
artifact's `run --ssh-agent` listing the host key's fingerprint. `SIGINT` and `SIGKILL` to a packed
`run` ended both its processes within 2 s. Docker Hub's anonymous pull limit stopped the first
verify run's image pack with `TOOMANYREQUESTS`; it passed on the re-run. The one-file route by
hand: `pack create --from-vm --single-file` wrote one 62890688-byte file, and `verify-pack.sh
--machine ... --marker-path` gave `image_pack=skipped` and `result=artifacts_good (1 of 2
artifacts)`.

Linux aarch64: not run. A default-size source machine and the image pack's pull VM both need
8192 MiB, and both timed out; the export helper was never reached.

## What was not run

- **Cross-platform rehydration**, except for one pair. An arm64 stub built on macOS was carried
  to x86_64 Windows on 2026-09-11 and **the OS loader refuses it before any smolvm code runs**:
  the stub runs only on the platform it was built on. `smolvm pack run --sidecar` refuses a
  sidecar built on another platform, with `this artifact was built for ... but the current
  platform is ...`. Nothing here ran a sidecar on another host of the same architecture.
- **`pack push`, `pack pull` and `pack inspect` against a registry.** Nothing here touched a
  registry.
- **Windows through these scripts.** `scripts/*.sh` are bash and do not run there; the
  Windows runs issued the CLI by hand. `references/windows.md` has them.
- **The branched and restored sources on Linux aarch64.** The restored source was run on macOS on
  v1.18.2 and the branched one on v1.22.2; both are answered on Linux
  x86_64 in the material behind this packet.
- **SSH agent forwarding on Linux.** Measured on macOS only.
- **Linux aarch64 on v1.18.2 and v1.22.2**, as above.

## Related packets

- `dev-env` for producing the machine that gets packed, and for the `init`-runs-once semantics
  its provisioning depends on.
- `install` for the boot this assumes, and `teardown` for the wider cleanup.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can pack a machine into a portable artifact.
# Read-only: starts no VM, packs nothing, writes no smolvm state.
#
# The memory lines are the reason this script exists. Both pack paths boot a
# helper VM before they write anything:
#   --image    pulls the image in a VM fixed at 4 vCPUs and 8192 MiB on every
#              release read (src/cli/pack.rs:730-742 at v1.22.2); --mem does
#              not reach it.
#   --from-vm  boots an export helper. Through v1.16.1 it was fixed at 8192 MiB
#              and a host that could not seat it failed as "agent did not become
#              ready within 30 seconds", naming nothing. From v1.16.2 it asks for
#              4096 MiB (on Linux half of the available memory when that is
#              less, never under 1024), SMOLVM_EXPORT_HELPER_MEMORY_MIB sets it,
#              and a failed start names the figure and the variable
#              (src/pack_export.rs:289-335 and :514-522 at v1.22.2).
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
        note "this script covers macOS and Linux. On Windows v1.22.2 packs both ways but no artifact runs there (os error 123), and the stub is written without .exe; see references/windows.md."
        ;;
esac

# --- the helper VMs' memory --------------------------------------------------
#
# Read free memory the way the kernel reports it. MemAvailable is the honest
# number for "could a new process get this". On Linux smolvm also caps it by the
# cgroup's headroom, which this does not read.
case "$kernel" in
    Darwin)
        # Free alone is meaningless on macOS, which keeps almost nothing free.
        # Inactive and purgeable pages are reclaimable, which is what Activity
        # Monitor calls available.
        avail_mib="$(vm_stat 2>/dev/null | awk -v page="$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)" '
            /Pages free/        {gsub(/\./,"",$3); f=$3}
            /Pages inactive/    {gsub(/\./,"",$3); i=$3}
            /Pages speculative/ {gsub(/\./,"",$3); s=$3}
            /Pages purgeable/   {gsub(/\./,"",$3); p=$3}
            END {printf "%d", (f+i+s+p)*page/1048576}')"
        ;;
    Linux)
        avail_mib="$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)"
        ;;
    *) avail_mib="" ;;
esac

# What this binary's export helper will ask for (src/pack_export.rs:318-335).
IMAGE_VM_MIB=8192
override="${SMOLVM_EXPORT_HELPER_MEMORY_MIB:-}"
if [ -n "${version:-}" ] && [ "$version" != "unknown" ] &&
   [ "$(printf '%s\n%s\n' "$version" 1.16.2 | sort -V | head -1)" != "1.16.2" ]; then
    EXPORTER_MIB=8192; exporter_basis=fixed_before_1.16.2
elif [ -n "$override" ] && [ "$override" -gt 0 ] 2>/dev/null; then
    EXPORTER_MIB="$override"; exporter_basis=SMOLVM_EXPORT_HELPER_MEMORY_MIB
elif [ "$kernel" = Linux ] && [ "${avail_mib:-0}" -gt 0 ]; then
    EXPORTER_MIB=$(( avail_mib / 2 ))
    [ "$EXPORTER_MIB" -gt 4096 ] && EXPORTER_MIB=4096
    [ "$EXPORTER_MIB" -lt 1024 ] && EXPORTER_MIB=1024
    exporter_basis=half_of_available
else
    EXPORTER_MIB=4096; exporter_basis=default
fi
emit exporter_memory_mib "$EXPORTER_MIB"
emit exporter_memory_basis "$exporter_basis"
emit image_vm_memory_mib "$IMAGE_VM_MIB"

if [ -n "${avail_mib:-}" ] && [ "${avail_mib:-0}" -gt 0 ]; then
    emit free_memory_mib "$avail_mib"
    # Warnings, not blocks. smolvm memory is a cap and not a reservation, so a
    # helper can still come up under the figure; what these lines buy you is
    # the name of the failure if it does not.
    if [ "$avail_mib" -ge "$EXPORTER_MIB" ]; then
        emit exporter_memory_ok yes
    else
        emit exporter_memory_ok no
        if [ "$exporter_basis" = fixed_before_1.16.2 ]; then
            note "free memory is below the export helper's fixed 8192 MiB on this release. If pack create --from-vm fails with 'agent did not become ready within 30 seconds', that is this; the message does not mention memory, and nothing changes the figure before v1.16.2."
        else
            note "free memory is below the $EXPORTER_MIB MiB the export helper will ask for. If pack create --from-vm fails, its message names the figure; set SMOLVM_EXPORT_HELPER_MEMORY_MIB=<MiB> lower and retry."
        fi
    fi
    if [ "$avail_mib" -ge "$IMAGE_VM_MIB" ]; then
        emit image_vm_memory_ok yes
    else
        emit image_vm_memory_ok no
        note "free memory is below the 8192 MiB pack create --image gives the VM that pulls the image. If it fails with 'agent did not become ready within 30 seconds', that is this; no flag or variable changes that VM, and --mem sets the artifact's memory, not its."
    fi
else
    emit free_memory_mib unknown
    emit exporter_memory_ok unknown
    emit image_vm_memory_ok unknown
    note "could not read free memory; the export helper asks for $EXPORTER_MIB MiB and the image pull VM for $IMAGE_VM_MIB MiB"
fi

# An isolated data root on Linux does not carry the agent rootfs: the variable
# moves where it is looked up and the installer does not write it there.
if [ "$kernel" = "Linux" ] && [ -n "${SMOLVM_DATA_DIR:-}" ]; then
    if [ -d "$SMOLVM_DATA_DIR/.local/share/smolvm/agent-rootfs" ]; then
        emit data_root_rootfs present
    else
        emit data_root_rootfs missing
        blocked=1
        note "SMOLVM_DATA_DIR is set and holds no agent-rootfs, so the first boot fails with 'agent rootfs not found'. Copy the installer's agent-rootfs into \$SMOLVM_DATA_DIR/.local/share/smolvm/ first."
    fi
fi

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/pack-image.sh`

```bash
#!/usr/bin/env bash
# Pack an image into a portable artifact.
#
# usage: pack-image.sh [<image>] [<output>]
#   image   default alpine
#   output  default ./from-image, and it names the STUB, not the sidecar
#
# This path pulls the image in its own temporary VM, fixed at 4 vCPUs and
# 8192 MiB on every release read; --mem sets the artifact's memory, not that
# VM's. preflight.sh reports it as image_vm_memory_ok.

set -uo pipefail

IMAGE="${1:-alpine}"
OUT="${2:-./from-image}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

# `--output` names the stub. Passing a .smolmachine here fails immediately, and
# the error is good, but there is no reason to meet it.
case "$OUT" in
    *.smolmachine)
        printf 'output=%s\n' "$OUT"
        printf 'result=FAILED --output names the stub, not the sidecar. The sidecar is created for you as <output>.smolmachine, so pass --output %s instead.\n' "${OUT%.smolmachine}"
        exit 2
        ;;
esac

start="$(date +%s)"
out="$("$SMOLVM" pack create --image "$IMAGE" --output "$OUT" 2>&1)"
rc=$?
elapsed=$(( $(date +%s) - start ))
printf '%s\n' "$out" | sed 's/^/  /'

printf 'image=%s\n' "$IMAGE"
printf 'elapsed_s=%s\n' "$elapsed"

# Assert the exit code and the artifact: files an earlier run left at OUT pass
# the file tests on their own.
if [ "$rc" -ne 0 ] || [ ! -f "$OUT" ] || [ ! -f "$OUT.smolmachine" ]; then
    printf 'result=FAILED rc=%s (pack create failed, or the stub or sidecar is missing)\n' "$rc"
    exit 1
fi

reported_kb="$(printf '%s' "$out" | sed -n 's/.*stub: \([0-9]*\)KB.*/\1/p' | head -1)"
actual_kb=$(( $(wc -c < "$OUT") / 1024 ))
printf 'stub_reported_kb=%s\n' "${reported_kb:-unknown}"
printf 'stub_actual_kb=%s\n' "$actual_kb"
if [ -n "${reported_kb:-}" ] && [ "$actual_kb" -gt "$reported_kb" ]; then
    printf 'stub_understated_kb=%s\n' "$(( actual_kb - reported_kb ))"
    printf 'note=pack create prints its sizes before it signs the stub (macOS) and appends the compressed runtime libraries to it, so stub: and total: understate the file by that block. Size a disk budget or an upload from the file, not from the report.\n'
fi
printf 'sidecar_kb=%s\n' "$(( $(wc -c < "$OUT.smolmachine") / 1024 ))"
printf 'result=packed\n'
```

### `scripts/pack-machine.sh`

```bash
#!/usr/bin/env bash
# Provision a machine, prove the state is in it, then pack it.
#
# usage: pack-machine.sh [<name>] [<output>] [<image>]
#   name    default smolskill-golden (the prefix cleanup.sh will delete)
#   output  default ./from-vm, naming the STUB
#   image   default python:3.12-alpine
#
# The marker written here is the whole point of the packet. A pack that lost its
# rootfs still boots, still prints a guest kernel and still exits zero, so the
# only assertion that separates a good artifact from an empty one is a value put
# into the source and read back out of the artifact. This script writes it and
# asserts it ON THE SOURCE before packing; verify-pack.sh reads it back.
#
# This path boots an export helper VM: fixed at 8192 MiB through v1.16.1, and
# from v1.16.2 4096 MiB or less, which SMOLVM_EXPORT_HELPER_MEMORY_MIB sets. If
# the export fails, run preflight.sh and read free_memory_mib against
# exporter_memory_mib.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-smolskill-golden}"
OUT="${2:-./from-vm}"
IMAGE="${3:-python:3.12-alpine}"
MARKER="PACKED_STATE_PRESENT"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

case "$NAME" in
    smolskill-*) ;;
    *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;;
esac
case "$OUT" in
    *.smolmachine) printf 'result=FAILED --output names the stub; pass %s\n' "${OUT%.smolmachine}"; exit 2 ;;
esac

# A workload that stays up, so exec does not race a relaunching container.
"$SMOLVM" machine create --name "$NAME" --net --image "$IMAGE" \
    -- sh -c 'while true; do sleep 3600; done' 2>&1 | sed 's/^/  /'
"$here/cleanup.sh" --record "$NAME"
"$SMOLVM" machine start --name "$NAME" 2>&1 | sed 's/^/  /'

# Wait for a value, not for an empty result or a zero exit code: an exec in the
# startup window answers with a message and still exits zero.
waited=0
while [ "$waited" -lt 120 ]; do
    probe="$("$SMOLVM" machine exec --name "$NAME" -- sh -c 'echo READY' 2>&1 | tr -d '\r')"
    [ "$probe" = "READY" ] && break
    sleep 1
    waited=$((waited + 1))
done
printf 'workload_ready_after_s=%s\n' "$waited"
if [ "$probe" != "READY" ]; then
    printf 'result=FAILED the machine never became usable, so there is nothing to pack\n'
    exit 1
fi

"$SMOLVM" machine exec --name "$NAME" -- sh -c "echo $MARKER > /marker.txt" >/dev/null 2>&1

# Assert on the SOURCE. Packing a machine that was never provisioned produces an
# artifact that runs fine and contains nothing, and that mistake is invisible
# until the artifact is read.
src_marker="$("$SMOLVM" machine exec --name "$NAME" -- cat /marker.txt 2>&1 | tr -d '\r')"
printf 'source_marker=%s\n' "$src_marker"
if [ "$src_marker" != "$MARKER" ]; then
    printf 'result=FAILED the source does not carry the marker, so packing it would produce an empty artifact\n'
    exit 1
fi

"$SMOLVM" machine stop --name "$NAME" 2>&1 | sed 's/^/  /'

start="$(date +%s)"
out="$("$SMOLVM" pack create --from-vm "$NAME" --output "$OUT" 2>&1)"
rc=$?
elapsed=$(( $(date +%s) - start ))
printf '%s\n' "$out" | sed 's/^/  /'
printf 'elapsed_s=%s\n' "$elapsed"

if [ "$rc" -ne 0 ] || [ ! -f "$OUT" ] || [ ! -f "$OUT.smolmachine" ]; then
    printf 'result=FAILED rc=%s\n' "$rc"
    case "$out" in
        *"export helper asked for"*)
            printf 'diagnosis: the export helper VM did not start; the message above names the memory it asked for. Retry with SMOLVM_EXPORT_HELPER_MEMORY_MIB set lower, for example 2048.\n' ;;
        *"did not become ready"*)
            printf 'diagnosis: the export helper VM did not come up. Before v1.16.2 its memory is fixed at 8192 MiB and the message never says so. Run scripts/preflight.sh and read free_memory_mib against exporter_memory_mib.\n' ;;
        *"fork clone"*)
            printf 'diagnosis: this machine is a branch child and its copy-on-write disks cannot be exported. Pack the golden it came from, or recreate the state in a machine that was never branched.\n' ;;
    esac
    exit 1
fi

printf 'sidecar_kb=%s\n' "$(( $(wc -c < "$OUT.smolmachine") / 1024 ))"
printf 'marker=%s\n' "$MARKER"
printf 'result=packed\n'
printf 'next: scripts/verify-pack.sh, which reads that marker back out of the artifact\n'
```

### `scripts/verify-pack.sh`

```bash
#!/usr/bin/env bash
# Prove an artifact is worth shipping: that it runs a real VM, and for a machine
# pack that the state is inside it.
#
# usage: verify-pack.sh [--image <stub>] [--machine <stub>] [--marker <value>]
#                       [--marker-path <path>]
#   --image   <stub>       an artifact packed from an image   (default ./from-image)
#   --machine <stub>       an artifact packed from a machine  (default ./from-vm)
#   --marker  <value>      the file's expected last line      (default PACKED_STATE_PRESENT)
#   --marker-path <path>   the file in the guest to read      (default /marker.txt)
#
# Every check asserts a value. A pack that lost its rootfs still boots, still
# prints a guest kernel and still exits zero, so "it ran" proves nothing about
# what is inside it.

set -uo pipefail

IMAGE_STUB="./from-image"
MACHINE_STUB="./from-vm"
MARKER="PACKED_STATE_PRESENT"
MARKER_PATH="/marker.txt"
while [ $# -gt 0 ]; do
    case "$1" in
        --image)   IMAGE_STUB="$2"; shift ;;
        --machine) MACHINE_STUB="$2"; shift ;;
        --marker)  MARKER="$2"; shift ;;
        --marker-path) MARKER_PATH="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
fail=0
checked=0
check() {
    if [ "$2" = "$3" ]; then
        printf '%s=ok (%s)\n' "$1" "$2"
    else
        printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"
        fail=1
    fi
}

# Where `pack run` keeps its extractions, one directory per artifact checksum.
case "$(uname -s)" in
    Darwin) PACK_CACHE="$HOME/Library/Caches/smolvm-pack" ;;
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            PACK_CACHE="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm-pack" ;;
esac
cache_entries() { find "$PACK_CACHE" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

# --- the image pack: a real VM, and a cached second run ----------------------
if [ -f "$IMAGE_STUB" ]; then
    # The stub takes a subcommand. A bare `--` is rejected with a tip that does
    # not mention `run`.
    checked=$((checked + 1))
    kernel="$("$IMAGE_STUB" run -- uname -sr 2>&1 | tr -d '\r' | grep -m1 '^Linux ' | awk '{print $1}')"
    check image_pack_is_a_vm "${kernel:-none}" Linux

    # Count the cache after the first run, then again after the second. A reused
    # extraction adds nothing. Timing is not the test: wall clock on a loaded or
    # nested-virt host varies by more than the saving, so it reports a healthy
    # host as suspect.
    after_first="$(cache_entries)"
    marker2="$("$IMAGE_STUB" run -- sh -c 'echo SECOND_RUN_OK' 2>&1 | tr -d '\r' | tail -1)"
    check image_pack_second_run "$marker2" SECOND_RUN_OK
    after_second="$(cache_entries)"
    printf 'pack_cache_entries=%s\n' "$after_second"
    if [ "$after_first" -gt 0 ]; then
        check image_pack_reused_cache "$after_second" "$after_first"
    else
        printf 'image_pack_reused_cache=skipped (no pack cache at %s)\n' "$PACK_CACHE"
    fi
else
    printf 'image_pack=skipped (%s not present)\n' "$IMAGE_STUB"
fi

# --- the machine pack: the load-bearing assertion ----------------------------
if [ -f "$MACHINE_STUB" ]; then
    checked=$((checked + 1))
    got="$("$MACHINE_STUB" run -- cat "$MARKER_PATH" 2>&1 | tr -d '\r' | tail -1)"
    check machine_pack_carried_rootfs "$got" "$MARKER"

    mkernel="$("$MACHINE_STUB" run -- uname -sr 2>&1 | tr -d '\r' | grep -m1 '^Linux ' | awk '{print $1}')"
    check machine_pack_is_a_vm "${mkernel:-none}" Linux

    if [ -n "$SMOLVM" ] && [ -f "$MACHINE_STUB.smolmachine" ]; then
        printf '%s\n' "--- what the artifact says it is ---"
        "$SMOLVM" pack run --sidecar "$MACHINE_STUB.smolmachine" --info 2>&1 \
            | grep -E '^(Mode|Image|Platform|CPUs|Memory|Checksum):' | sed 's/^/  /'
    fi
else
    printf 'machine_pack=skipped (%s not present)\n' "$MACHINE_STUB"
fi

# Verifying nothing is not a pass. Both stubs absent means the artifacts were
# written somewhere else, and a green line there would be the same false clean
# this packet exists to prevent.
if [ "$checked" -eq 0 ]; then
    printf 'result=nothing_verified\n'
    printf 'note=no artifact was found at %s or %s. If you packed to another path, pass --image and --machine, or this says nothing at all.\n' "$IMAGE_STUB" "$MACHINE_STUB"
    exit 2
fi

if [ "$fail" -eq 0 ]; then printf 'result=artifacts_good (%s of 2 artifacts)\n' "$checked"; else printf 'result=FAILED\n'; fi
exit "$fail"
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Delete the machines this packet's scripts created, then prove the host is clean.
#
# Only machines recorded in the state file are deleted, with --cascade, so any
# machine branched from one of them goes too, whatever its name. Any other
# machine, yours or another session's, is never deleted. Scripts record a name
# by calling: cleanup.sh --record <name>
#
# usage: cleanup.sh [--record <name>] [--reap] [--purge] [--artifacts <stub>...]
#   --record <name>     add a machine name to the state file and exit
#   --reap              kill every VM process under this HOME; run without it first
#   --purge             also remove the state file once the list is empty
#   --artifacts <stub>  also remove that stub and its .smolmachine sidecar; last
#
# `pack run` takes the forked boot path, and before v1.20.2 a cancelled run left
# a VM the CLI cannot see. The process scan below catches both shapes, which is
# why this script and not Ctrl-C is the way to stop one on those releases.

set -uo pipefail

PACKET="pack"
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
        --artifacts) shift; break ;;
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
        # Reclaim this machine's cached layers while it still exists. The bare
        # `smolvm machine prune` is rejected on this release:
        #     Usage: smolvm machine prune --name <NAME>
        "$SMOLVM" machine prune --name "$name" 2>&1 | sed 's/^/  /'
        # Only names still listed: a second stop of a missing name leaves a
        # directory that reads as a leak. The list is read first because grep -q
        # under pipefail can fail the pipeline and skip a listed machine.
        listed="$("$SMOLVM" machine list </dev/null 2>/dev/null | awk 'NR>2{print $1}')"
        grep -qx -- "$name" <<<"$listed" || continue
        "$SMOLVM" machine stop   --name "$name" </dev/null >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade </dev/null 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 1b. Remove the artifacts named on the command line, left in "$@" by the
# argument loop. A stub and its sidecar are two files and the sidecar is the
# large one.
for a in "$@"; do
    for f in "$a" "$a.smolmachine"; do
        [ -f "$f" ] && rm -f "$f" && printf 'removed=%s\n' "$f"
    done
done

# 1c. Reclaim pack caches beyond the five most recently used (pack prune's
# default). `pack prune` takes no required argument; the machine form does, and
# a bare `smolvm machine prune` is rejected outright on this release:
#     Usage: smolvm machine prune --name <NAME>
if [ -n "$SMOLVM" ]; then
    "$SMOLVM" pack prune 2>&1 | sed 's/^/  /'
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

## Pack traps

### `--output` names the stub, not the sidecar

Passing `--output foo.smolmachine` fails immediately, and the error is good: it says the sidecar
is created automatically as `<output>.smolmachine` and to pass `--output ./foo`. Read it rather
than guessing. `scripts/pack-image.sh` and `scripts/pack-machine.sh` refuse the `.smolmachine`
form before the CLI sees it.

### On Windows the stub is written without `.exe`

`pack create -o pimg` on Windows writes `pimg` and `pimg.smolmachine`, and PowerShell refuses to
execute the extensionless stub:

```
ERROR: Cannot run a document in the middle of a pipeline: C:\...\pimg.
```

Rename it to `p.exe` with `p.exe.smolmachine` beside it and it runs, printing `PACK_IMG_OK` from
the packaged entrypoint. The sidecar has to be renamed too, because the stub looks for its own
name plus `.smolmachine`. Observed on v1.14.6; `references/windows.md` has the run.

### The stub takes a subcommand, and a bare `--` is rejected

```
$ ./from-vm -- sh -c 'echo hi'
tip: subcommand 'sh' exists; to use it, remove the '--' before it
```

The working forms are `./from-vm run -- sh -c '...'` and `./from-vm` alone, which executes the
packaged entrypoint. The tip does not mention `run`, which is the part that costs the time.

### `pack run` takes `--sidecar`, not a positional path

```
$ smolvm pack run ./x.smolmachine -- cmd
executable file `./x.smolmachine` not found in $PATH
```

The path was consumed as the command to run. Nothing in the message points at `--sidecar`.

### The helper VMs' memory, by release, and what the failure looks like

`pack create --from-vm` boots an export helper VM. **Through v1.16.1** its memory was fixed,
`memory_mib: 8192` in `src/pack_export.rs` (`:345` at v1.14.6, `:384` at v1.16.1), with no flag
and no variable, and on a host that could not give it that much the export failed as

```
agent did not become ready within 30 seconds
```

which named neither memory nor the helper.

**From v1.16.2** (#1312) it asks for 4096 MiB. On Linux it asks for half of the available memory
instead when that is less, and never under 1024 MiB; macOS and Windows ask for 4096.
`SMOLVM_EXPORT_HELPER_MEMORY_MIB=<MiB>` sets it, `SMOLVM_EXPORT_HELPER_STORAGE_GIB=<GiB>` sets its
disk, and a helper that cannot start ends with `The export helper asked for N MiB of memory and a
G GiB disk. If this host cannot seat that, set SMOLVM_EXPORT_HELPER_MEMORY_MIB=<MiB> and/or
SMOLVM_EXPORT_HELPER_STORAGE_GIB=<GiB> and retry.` (`src/pack_export.rs:289-335` and `:514-522`
at v1.22.2). A bare machine, one with no image, is flattened by a separate helper fixed at 2 vCPUs
and 2048 MiB.

**`pack create --image` is the path with a fixed 8192 MiB VM** on every release here: it pulls
the image in a temporary VM of 4 vCPUs and 8192 MiB (`src/cli/pack.rs:730-742` at v1.22.2), which
no flag or variable changes, and a host that cannot seat it fails with the same bare ready
timeout.

`pack create --mem` sets the **packed artifact's** runtime memory, not either helper's. The two
are easy to confuse because `--info` reports the artifact's figure and it is also 8192 by default.

**It is a cap and not a reservation, so the figure does not decide the outcome.** Measured on
v1.14.6: the export **succeeded** on a Mac whose preflight reported `free_memory_mib=4990`, and
the fixed figure was the binding constraint on a 10.9 GiB Linux host in the material behind this
packet. That is why the preflight warns rather than blocks.

### Verify the state, not the boot

**A pack that lost its rootfs still boots, still prints a guest kernel and still exits zero.**
Packing a machine whose provisioning silently failed produces an artifact that runs perfectly and
contains nothing. In the runs behind this packet a provisioning `exec` once failed unnoticed,
and the resulting pack reported `MISSING` for both markers.

The shape that makes it impossible is the one these scripts use: write a marker into the source,
**assert it on the source before packing**, and read it back out of the artifact afterwards.
`pack-machine.sh` exits non-zero rather than exporting a machine that does not carry its marker.

### Reported sizes understate the stub on disk

`pack create` prints its sizes before it has finished the stub. In the default two-file mode the
`stub:` figure is the smolvm binary it copied, and `total:` is that plus the sidecar. After
printing, it signs the stub on macOS (`Signing binary with hypervisor entitlements...`) and then
appends the runtime libraries to it, compressed, with a 32-byte footer: `libkrun` and `libkrunfw`,
plus the GPU rendering libraries when the install has them (`libvirglrenderer`, `libMoltenVK` and
`libepoxy` on macOS; `libvirglrenderer`, `libepoxy` and `virgl_render_server` on Linux). That
appended block is what the report leaves out. Measured on v1.14.6:

| host | reported | on disk | understated by |
|---|---|---|---|
| Linux aarch64 | 30737 KB | 39195 KB | 8458 KB |
| macOS arm64 | 29643 KB | 39883 KB | 10240 KB |

On macOS arm64 on v1.22.2 the gap was 10657 KB. `Assets:` is the compressed payload, and the
sidecar file adds only its manifest and a 64-byte footer, so that figure is accurate to a few KB.
With `--single-file` the libraries go inside the one file before the sizes are printed, and only
the macOS signature is added afterwards. **Do not size a disk budget or an upload from the reported
total.**

### A branched machine packs on v1.16.1, and was refused on v1.14.6

**#1251 closed this.** Verified on macOS arm64 on v1.16.1, 2026-09-15: a child branched from a
source started `--branchable`, given its own marker and then stopped, packs, and the artifact
prints the source's `BASE_STATE` and the child's `CHILD_ONLY`. A running branch is refused with
`VM 'bchild' is running. Stop it first`. Branchability is decided at `machine start --branchable`,
not at create.

Everything below is the **v1.14.6** behaviour, kept because a host on an older release still meets
it. Packing a branched machine was refused, by design, and the message named both remedies:

```
machine 'child' is a fork clone of 'src'; its copy-on-write disks cannot be exported
directly. Export the golden instead, or recreate the state in a non-clone machine and
export that.
```

The child itself carries the source's state and runs normally; it is only the export that
refuses. **So a branched machine is packed through its golden.** No artifact is produced, so there
is nothing to verify afterwards.

### A checkpoint restore packs, and the restore path is not `machine restore`

**First you have to be able to take the checkpoint, and on macOS before v1.20.0 that needs
`--branchable`.**
Verified on macOS arm64 on v1.16.1, 2026-09-15: `machine checkpoint` against a machine started
without it fails with

```
Error: agent operation failed: checkpoint machine: libkrun save failed: ERR EIO capture VM:
VM snapshot/restore failed: retain COW guest-memory generation: guest RAM has no file-backed
regions
```

which names neither the flag nor the precondition. Started with
`machine start --name <n> --branchable`, the same command wrote 46 MiB in 2.554s with a 0.292s
source pause. Branchability is decided at start and cannot be turned on afterwards. **The same on
v1.18.2 on macOS, 2026-09-24**, with the same message. On Linux aarch64 v1.18.2 took the checkpoint
of a machine started without the flag: `Checkpointed ... (55 MiB written, 1.781s total, 1.242s
source pause)`.

**v1.20.0 lifted it on macOS for a checkpoint file**, measured on 2026-10-03 with a 1024 MiB alpine
machine started without the flag on each release: v1.19.0 and v1.19.3 failed with the message above,
and v1.20.0, v1.20.2, v1.21.1, v1.22.0 and v1.22.2 each wrote one, for example
`Checkpointed 'nb' to ./c.smolcheckpoint (54 MiB written, 0.911s total, 0.300s source pause)` on
v1.20.0. **A stored checkpoint still needs the flag**: `--store` against the same kind of machine
on v1.22.2 fails with

```
Error: agent operation failed: checkpoint machine: libkrun save failed: ERR ENOTSUP VM
snapshot/restore failed: retain COW guest-memory generation: deferred durable save requires
file-backed guest RAM
```

A machine **created from a pack** checkpoints from v1.18.0 (#1361), and its restore reattaches the
pack's layers: on macOS on v1.18.2 a machine created from `from-vm.smolmachine`, checkpointed,
restored and packed again gave an artifact carrying the marker written after the pack.

A machine restored from a checkpoint packs, runs, and carries its rootfs. This is the case
[#1174](https://github.com/smol-machines/smolvm/pull/1174) changed, shipped in v1.14.3.

There is **no `machine restore` subcommand**, which is the obvious guess and gives
`unrecognized subcommand`. The restore path is `machine create --from <PATH>`, the same flag that
takes a `.smolmachine`, documented as "Create from a `.smolmachine` pack or restore a
`.smolcheckpoint`". From v1.19.1 `machine checkpoint --help` names the file `.checkpoint` instead,
and its error for any other name is `output must end in .checkpoint`; v1.22.2 accepts both.

### An isolated data root on Linux does not carry the agent rootfs

`SMOLVM_DATA_DIR` relocates the whole data root **including where the agent rootfs is looked up**,
and the installer does not write it there. The first boot under an isolated root fails with:

```
agent rootfs not found: <data root>/.local/share/smolvm/agent-rootfs
```

which points at a missing file rather than at the variable that moved it. Copy the installer's
`agent-rootfs` in first:

```bash
mkdir -p "$SMOLVM_DATA_DIR/.local/share/smolvm"
cp -r "$HOME/.local/share/smolvm/agent-rootfs" "$SMOLVM_DATA_DIR/.local/share/smolvm/"
```

`scripts/preflight.sh` reports `data_root_rootfs=missing` when the variable is set and the rootfs
is not there.

### `smolvm machine prune` needs a machine, and it starts one

The bare form does not run on v1.14.6:

```
$ smolvm machine prune
Usage: smolvm machine prune --name <NAME>
```

Its own help describes "Remove unused images and layers to free disk space", which reads host
wide, while `--name` is documented as "Machine to prune". `smolvm pack prune`, which removes cached
pack extractions beyond the five most recently used, does take no required argument. Any cleanup
line that says `smolvm machine prune` bare is wrong on this release.

**And the machine form starts the machine to do its work**, observed on Linux aarch64:

```
Starting machine...
Removing unreferenced layers...
No unreferenced layers to remove.
```

So it is worth running while the machine still exists and before deleting it, which is the order
`scripts/cleanup.sh` uses. Run after the delete it is a silent no-op.

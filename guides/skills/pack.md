---
title: "Pack: ship a prepared machine as one file"
---

# Pack: ship a prepared machine as one file

Turns an image, or a machine already provisioned, into a single self-contained artifact that runs on another compatible host. Use when shipping a prepared environment as one file, when a packed artifact runs but the state installed into it is missing, when pack create --from-vm fails with a ready timeout that names nothing, when an export is refused because the machine is a fork clone, or when deciding whether to pack from an image or from a machine. Do not use it to keep a machine you re-enter, which is the dev-env packet, or to run untrusted code, which is the sandbox packet.

Verified on **smolvm v1.18.2** on macOS arm64, 2026-09-24, and on **v1.14.6** on Linux aarch64,
2026-09-11; the Linux host could not run the packing steps on v1.18.2, for the reason in
"Re-verified on v1.18.2". Done means the
artifact runs a command in a real VM and, for a machine pack, **the state you installed is still
inside it**.

**The assertion that matters is a value, not a boot.** A pack that lost its rootfs still boots,
still prints a guest kernel and still exits zero. The only thing that separates a good artifact
from an empty one is a marker written into the source machine before packing and read back out of
the artifact afterwards, which is what `pack-machine.sh` and `verify-pack.sh` do between them.

## Procedure

**1. Preflight.** Read-only: starts no VM, packs nothing.

```bash
scripts/preflight.sh
```

The line to read is `exporter_memory_ok`. `pack create --from-vm` starts an exporter VM whose
memory is **hardcoded to 8192 MiB** with no flag and no environment variable, and on a host that
cannot give it that the export fails as `agent did not become ready within 30 seconds`, which
mentions neither memory nor the exporter. **This preflight is the only place that failure has a
name.** It is a warning and not a gate, because the figure is a cap rather than a reservation: see
"What the memory line does and does not promise". **On v1.16.1 it misfires more often than it
fires**: `pack create --from-vm` now prints `Reusing the machine's cached image layers...` and on
macOS arm64 completed in 1.2 s with `exporter_memory_ok=no` reported by the same preflight
moments earlier, 2026-09-15.

**2. Pack from an image**, when you want a runnable artifact of a stock image.

```bash
scripts/pack-image.sh                       # alpine, ./from-image
scripts/pack-image.sh python:3.12-alpine ./mypack
```

This path starts no exporter, so the memory line does not apply to it. **If you pass a custom
output, pass it to the verify step too** (`verify-pack.sh --image ./mypack`), or that step finds
nothing at its defaults and tells you so rather than passing.

**3. Pack from a machine you provisioned**, when the point is the state in it.

```bash
scripts/pack-machine.sh                     # smolskill-golden, ./from-vm
```

It creates the machine with a workload that stays up, waits for a value from it, writes a marker,
**asserts the marker on the source**, stops the machine and exports it. The source assertion is
not ceremony: packing a machine whose provisioning silently failed produces an artifact that runs
perfectly and contains nothing, and nothing downstream will tell you.

**Packing a machine that already exists**, the user's own rather than one `pack-machine.sh` made:
the script refuses any name without the `smolskill-` prefix, so run its sequence by hand. The
machine has to be stopped, since `--from-vm` packs a stopped machine's snapshot.

```bash
smolvm machine exec --name myapp -- sh -c 'echo PACKED_STATE_PRESENT > /marker.txt'
smolvm machine exec --name myapp -- cat /marker.txt          # assert it on the source first
smolvm machine stop --name myapp
smolvm pack create --from-vm myapp --output ./myapp-portable --single-file   # one file, no sidecar
scripts/verify-pack.sh --machine ./myapp-portable            # reads /marker.txt back out of it
smolvm machine start --name myapp && smolvm machine exec --name myapp -- rm -f /marker.txt
```

`verify-pack.sh --machine` works on a `--single-file` artifact as it does on a stub with a sidecar.
A stranger given only this packet and "ship this provisioned machine as one file" took this route
on v1.18.2, and the 58.8 MiB artifact printed the machine's own `/root/PROOF.txt` on another run.

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

It prunes each recorded machine while it still exists, deletes it, removes both stubs and their
sidecars, and runs `pack prune`. **`smolvm machine prune` with no argument does not run on this
release**; the form is `--name <NAME>`.

## Forwarding the SSH agent to an artifact

From v1.18.1 the artifact's own `run` and `start` take `--ssh-agent`, the same bridge `machine
run` has: the guest gets `SSH_AUTH_SOCK=/tmp/ssh-agent.sock` and the host agent signs, so no key
enters the artifact or the VM.

```bash
./from-image run --net --ssh-agent -- sh -c 'apk add -q openssh-client; ssh-add -l'
./from-image start --net --ssh-agent
./from-image exec -- ssh-add -l
```

Measured on macOS arm64 on v1.18.2 with a throwaway key in a throwaway agent: both forms listed
that key's fingerprint from inside the guest, a `run` without the flag had `SSH_AUTH_SOCK` unset,
and with the host variable empty the flag stops before booting with
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
is not the exporter's, which nothing can set.

## What the memory line does and does not promise

The exporter's 8192 MiB is a **cap, not a reservation**, so a host reporting less available memory
can still export. Measured on this release: the export succeeded on a Mac whose preflight reported
`free_memory_mib=4990`, well under the figure, and it is the binding constraint on a small Linux
box where it fails with the unnamed ready timeout. So the preflight **warns and does not block**,
and `result=ready` with `exporter_memory_ok=no` means "this may work, and if it does not, here is
why".

## Traps

Full detail with the evidence in `references/traps.md`. The ones that cost the most:

- **`--output` names the stub, not the sidecar.** Passing `--output foo.smolmachine` fails; the
  scripts refuse it before the CLI does.
- **"One file" needs `--single-file`, and the default is two.** By default `pack create` writes the
  stub plus a `.smolmachine` sidecar and the CLI says `Note: Keep the .smolmachine file alongside
  the binary`; the stub on its own prints smolvm's usage and exits. `--single-file` writes one
  executable with no sidecar, and its own help warns it `may have issues with macOS notarization`.
  Verified on macOS arm64 on v1.16.1: the default stub alone failed in a fresh directory and
  printed `CARRIED` once the sidecar was beside it; the `--single-file` artifact, 59806048 bytes,
  printed `CARRIED` alone.
- **The stub takes a subcommand, and a bare `--` is rejected** with a tip that does not mention
  `run`. The working form is `./from-vm run -- sh -c '...'`.
- **`pack run` takes `--sidecar <PATH>`, not a positional path**, and getting it wrong reports
  that your sidecar is not an executable in `$PATH`.
- **Reported sizes understate the stub on disk**, by about 8.4 MB on Linux aarch64 and about
  10 MB on macOS arm64, where an extra signing step runs. The sidecar figure is accurate.
- **A branched machine packs on v1.16.1, and carries both states.** This was refused at export on
  v1.14.6; #1251 closed it. Verified on macOS arm64 on 2026-09-15: start the source
  `--branchable`, `machine branch --from <src> --name <child>`, write a marker in the child, stop
  it, `pack create --from-vm <child>`, and the artifact prints the source's `BASE_STATE` and the
  child's `CHILD_ONLY`. The branch must be stopped before it will pack.
- **Branchability is decided at `machine start`, not at `create`.** `machine branch` against a
  machine started without it refuses with `was not started as branchable, so it has no
  copy-on-write memory to branch from ... branchability is decided at start time and cannot be
  turned on for an already-running machine`, and `machine create --branchable` is not a flag.
- **A checkpoint restore packs and carries its rootfs**, and the restore path is
  `machine create --from`. There is no `machine restore` subcommand. **Taking the checkpoint needs
  `--branchable` on macOS**: without it v1.16.1 and v1.18.2 fail with `guest RAM has no
  file-backed regions`, which names neither the flag nor the precondition. Linux aarch64 took one
  without it on v1.18.2. A machine created from a pack can be checkpointed from v1.18.0, and
  `create --from` restores the newest generation a checkpoint carries; `--at ~N` picks an earlier
  one, which `branch-and-checkpoint` covers.
- **On Linux, `SMOLVM_DATA_DIR` moves where the agent rootfs is looked up and the installer does
  not write it there**, so an isolated data root needs the rootfs copied in before the first boot.

## Security defaults, and why they are the defaults

- **An artifact is a filesystem you are handing to someone else.** Whatever was in the source
  machine's rootfs is in the sidecar, including anything a provisioning step left in a shell
  history, a cache, or a file under `/root`. The marker this packet writes is deliberately inert;
  treat anything else you put in the source as published.
- **Packing does not narrow what the artifact may do.** The recorded entrypoint, network setting
  and memory come from the source, so a machine created with `--net` produces an artifact that
  expects a network. Decide that on the source, not afterwards.
- **The scripts pack only a machine they created**, named under the `smolskill-` prefix and
  recorded in a state file, and cleanup deletes only those. A machine you or another session made
  by hand is never exported and never deleted.
- **`pack run` takes the forked boot path**, so a cancelled run leaves a VM the CLI cannot see.
  `cleanup.sh` is the way to stop one, and its process scan catches both VM shapes. Ctrl-C is not.
- **Nothing here escalates privilege**, edits smolvm configuration or touches `~/.smolvm`.

## Platform arms

- **macOS arm64**: verified on v1.18.2, including the SSH agent forwarding and a pack of a
  restored machine. An extra `Signing binary with hypervisor entitlements` step runs here that
  does not on Linux.
- **Linux aarch64**: verified on v1.14.6. Not re-run on v1.18.2: the host could not boot the pull
  helper in time, see below.
- **Linux x86_64**: verified in the material behind this packet on v1.14.6, including the branched
  and restored cases. Not re-run here.

**Both hosts run here produce `linux/arm64` artifacts**, so two hosts is two hosts and not two
artifact architectures. The `linux/amd64` side rests on the x86_64 run above.
- **Windows x86_64**: `references/windows.md`, **re-run on 2026-09-11 against v1.14.6** on
  Windows 11 Home build 10.0.26200.0 UBR 9445. Both paths work: the image pack, and `--from-vm`
  for the first time there, with the marker read back out of the artifact. The stub is written
  without `.exe` and will not run until it and its sidecar are renamed.

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

The image pack is the control: it runs and does not carry the machine's state.

**3. "`pack create --from-vm` fails with `agent did not become ready within 30 seconds` and says
nothing else."**

Run the preflight, which is the only place that failure is named:

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

## Re-verified on v1.18.2

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64).

**macOS: full pass.**

```
exporter_memory_ok=no                   (free_memory_mib=2707, a warning and not a gate)
result=packed                           (image, 4.5 s; stub_understated_kb=10516)
source_marker=PACKED_STATE_PRESENT
  Reusing the machine's cached image layers...
result=packed                           (machine, 1 s of export)
image_pack_is_a_vm=ok (Linux)
image_pack_second_run=ok (SECOND_RUN_OK)
machine_pack_carried_rootfs=ok (PACKED_STATE_PRESENT)
result=artifacts_good (2 of 2 artifacts)
```

The SSH agent forwarding in the section above was measured in the same session. So was a
restore: a machine created from `from-vm.smolmachine`, started `--branchable`, a marker written,
`Checkpointed ... (43 MiB written, 4.043s total, 0.652s source pause)`, restored with
`machine create --from <file>.smolcheckpoint`, started, the marker read back, and
`pack create --from-vm` of the restored machine finished in 2.3 s with an artifact that printed the
marker.

**Linux aarch64: not run, for a host reason.** `pack create --image alpine` failed with `agent did
not become ready within 30 seconds`, with or without `--mem 1024`, because the pull helper does not
take `--mem`; the golden machine's start failed the same way. That box could not boot guests above
2048 MiB in time that day, on v1.16.1 as well, which the `install` packet's traps record. The
preflight reported `exporter_memory_ok=yes` there, since the host had 10386 MiB free: free memory
is not what failed, so read that line as a hint about the exporter only.

## What was not run

- **Cross-platform rehydration**, except for one pair. An arm64 stub built on macOS was carried to
  x86_64 Windows on 2026-09-11 and **the OS loader refuses it before any smolvm code runs**, so an
  artifact has to be built on the platform it will run on. Nothing tests the reverse direction, or
  two hosts of the same architecture on different operating systems.
- **`pack push`, `pack pull` and `pack inspect` against a registry.** Nothing here touched a
  registry.
- **Windows through these scripts.** `scripts/*.sh` are POSIX shell and do not run there; the
  2026-09-11 v1.14.6 run on Windows issued the CLI by hand. `references/windows.md` has it.
- **The branched source on aarch64**, and the restored source on Linux aarch64. The restored
  source was run on macOS on v1.18.2 and the branched one on v1.16.1; both are answered on Linux
  x86_64 in the material behind this packet.
- **SSH agent forwarding on Linux.** Measured on macOS only.
- **Linux aarch64 on v1.18.2**, as above.

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
# The memory line is the reason this script exists. `pack create --from-vm`
# starts an exporter VM whose memory is hardcoded to 8192 MiB
# (`src/pack_export.rs:345` at 3412bd26, and a second exporter at `:914` fixed
# at 2048), with no flag and no environment variable. On a host with less free
# memory the export fails as "agent did not become ready within 30 seconds",
# which names neither memory nor the exporter. This is the only place that
# failure gets a name before you hit it.
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
        note "this script covers macOS and Linux. Windows packs an image and packs --from-vm fine as of v1.14.6, but writes the stub without .exe; see references/windows.md."
        ;;
esac

# --- the exporter's fixed memory, the precondition that names nothing ---------
#
# Read free memory the way the kernel reports it. MemAvailable is the honest
# number for "could a new process get this", and it is what a large host makes
# irrelevant and a small host makes decisive.
EXPORTER_MIB=8192
emit exporter_memory_mib "$EXPORTER_MIB"
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

if [ -n "${avail_mib:-}" ] && [ "${avail_mib:-0}" -gt 0 ]; then
    emit free_memory_mib "$avail_mib"
    if [ "$avail_mib" -ge "$EXPORTER_MIB" ]; then
        emit exporter_memory_ok yes
    else
        # A warning, not a block. smolvm memory is a cap and not a reservation,
        # so an exporter can still come up under the figure; what this line buys
        # you is the name of the failure if it does not.
        emit exporter_memory_ok no
        note "free memory is below the exporter's fixed $EXPORTER_MIB MiB. If pack create --from-vm fails with 'agent did not become ready within 30 seconds', that is this, and the message will not mention memory. Packing from an image starts no exporter and is unaffected."
    fi
else
    emit free_memory_mib unknown
    emit exporter_memory_ok unknown
    note "could not read free memory; the exporter needs $EXPORTER_MIB MiB and fails with a ready timeout that names nothing"
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
# This path starts no exporter VM, so the free-memory precondition in
# preflight.sh does not apply to it. Only `--from-vm` does.

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

# Assert the artifact, not the exit code.
if [ ! -f "$OUT" ] || [ ! -f "$OUT.smolmachine" ]; then
    printf 'result=FAILED rc=%s (stub or sidecar missing)\n' "$rc"
    exit 1
fi

reported_kb="$(printf '%s' "$out" | sed -n 's/.*stub: \([0-9]*\)KB.*/\1/p' | head -1)"
actual_kb=$(( $(wc -c < "$OUT") / 1024 ))
printf 'stub_reported_kb=%s\n' "${reported_kb:-unknown}"
printf 'stub_actual_kb=%s\n' "$actual_kb"
if [ -n "${reported_kb:-}" ] && [ "$actual_kb" -gt "$reported_kb" ]; then
    printf 'stub_understated_kb=%s\n' "$(( actual_kb - reported_kb ))"
    printf 'note=pack create reports a stub smaller than the file on disk, so its total: understates by the same amount. Size a disk budget or an upload from the file, not from the report. The sidecar figure is accurate.\n'
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
# This path starts an exporter VM whose memory is hardcoded to 8192 MiB. If it
# fails with a ready timeout, run preflight.sh: that is the only place the
# failure gets a name.

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

if [ ! -f "$OUT" ] || [ ! -f "$OUT.smolmachine" ]; then
    printf 'result=FAILED rc=%s\n' "$rc"
    case "$out" in
        *"did not become ready"*)
            printf 'diagnosis: the exporter VM did not come up. Its memory is hardcoded to 8192 MiB and the message never says so. Run scripts/preflight.sh and read free_memory_mib against exporter_memory_mib.\n' ;;
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
#   --image   <stub>  an artifact packed from an image   (default ./from-image)
#   --machine <stub>  an artifact packed from a machine  (default ./from-vm)
#   --marker  <value> what pack-machine.sh wrote         (default PACKED_STATE_PRESENT)
#
# Every check asserts a value. A pack that lost its rootfs still boots, still
# prints a guest kernel and still exits zero, so "it ran" proves nothing about
# what is inside it.

set -uo pipefail

IMAGE_STUB="./from-image"
MACHINE_STUB="./from-vm"
MARKER="PACKED_STATE_PRESENT"
while [ $# -gt 0 ]; do
    case "$1" in
        --image)   IMAGE_STUB="$2"; shift ;;
        --machine) MACHINE_STUB="$2"; shift ;;
        --marker)  MARKER="$2"; shift ;;
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
    *)      PACK_CACHE="${SMOLVM_DATA_DIR:-$HOME/.cache}/smolvm-pack" ;;
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
    got="$("$MACHINE_STUB" run -- cat /marker.txt 2>&1 | tr -d '\r' | tail -1)"
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
# Only machines recorded in the state file are deleted, so a machine you or
# another session created by hand is never touched. Scripts record a name by
# calling: cleanup.sh --record <name>
#
# usage: cleanup.sh [--record <name>] [--reap] [--purge] [--artifacts <stub>...]
#   --record <name>     add a machine name to the state file and exit
#   --reap              kill leftover VM processes (see the warning it prints)
#   --purge             also remove the state file once the list is empty
#   --artifacts <stub>  also remove that stub and its .smolmachine sidecar
#
# `pack run` takes the forked boot path, so a cancelled run leaves a VM the CLI
# cannot see. The process scan below catches both shapes, which is why this
# script and not Ctrl-C is the way to stop one.

set -uo pipefail

PACKET="pack"
PREFIX="smolskill-"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
STATE_FILE="$STATE_DIR/$PACKET.machines"

reap=0
purge=0
ARTIFACTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --record)
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$2" >> "$STATE_FILE"
            exit 0
            ;;
        --reap)  reap=1 ;;
        --purge) purge=1 ;;
        --artifacts) shift; ARTIFACTS="$*"; break ;;
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
        # Reclaim this machine's cached layers while it still exists. The bare
        # `smolvm machine prune` the runbooks used is rejected on this release:
        #     Usage: smolvm machine prune --name <NAME>
        "$SMOLVM" machine prune --name "$name" 2>&1 | sed 's/^/  /'
        "$SMOLVM" machine stop   --name "$name" >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 1b. Remove the artifacts named on the command line. A stub and its sidecar are
# two files and the sidecar is the large one.
for a in ${ARTIFACTS:-}; do
    for f in "$a" "$a.smolmachine"; do
        [ -f "$f" ] && rm -f "$f" && printf 'removed=%s\n' "$f"
    done
done

# 1c. Reclaim the pack caches. `pack prune` takes no required argument; the
# machine form does, and the bare `smolvm machine prune` the runbooks used is
# rejected outright on this release:
#     Usage: smolvm machine prune --name <NAME>
if [ -n "$SMOLVM" ]; then
    "$SMOLVM" pack prune 2>&1 | sed 's/^/  /'
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

### The exporter's 8192 MiB, and what the failure looks like

`pack create --from-vm` starts an exporter VM whose memory is **hardcoded to 8192 MiB**:
`src/pack_export.rs:345` at `3412bd26`, `memory_mib: 8192`. A second exporter VM at `:914` is
hardcoded to `cpus: 2, memory_mib: 2048`. A grep of that file for `env::var`, any `SMOLVM_*MEM`
and `--mem` returns nothing, so **neither is overridable**.

`pack create --mem` sets the **packed artifact's** runtime memory, not the exporter's. The two are
easy to confuse because `--info` reports the artifact's figure and it is also 8192 by default.

On a host that cannot give the exporter that much, the export fails as:

```
agent did not become ready within 30 seconds
```

which names neither memory nor the exporter. `scripts/preflight.sh` is the only place it gets a
name.

**It is a cap and not a reservation, so the figure does not decide the outcome.** Measured on
v1.14.6: the export **succeeded** on a Mac whose preflight reported `free_memory_mib=4990`, and
the same trap was the binding constraint on a 10.9 GiB Linux box in the material behind this
packet. That is why the preflight warns rather than blocks. The citation has drifted twice, from
`:299` to `:311` at v1.14.2 to `:345` now, so check the line before quoting it.

### Verify the state, not the boot

**A pack that lost its rootfs still boots, still prints a guest kernel and still exits zero.**
Packing a machine whose provisioning silently failed produces an artifact that runs perfectly and
contains nothing. That happened in the runbook session behind this packet: a provisioning `exec`
had failed unnoticed and the resulting pack reported `MISSING` for both markers.

The shape that makes it impossible is the one these scripts use: write a marker into the source,
**assert it on the source before packing**, and read it back out of the artifact afterwards.
`pack-machine.sh` exits non-zero rather than exporting a machine that does not carry its marker.

### Reported sizes understate the stub on disk

`pack create` reports a stub smaller than the file it wrote, so its `total:` understates by the
same amount. Measured on v1.14.6:

| host | reported | on disk | understated by |
|---|---|---|---|
| Linux aarch64 | 30737 KB | 39195 KB | 8458 KB |
| macOS arm64 | 29643 KB | 39883 KB | 10240 KB |

The macOS gap is larger because an extra `Signing binary with hypervisor entitlements` step runs
there. The sidecar figures are accurate on both. **Do not size a disk budget or an upload from the
reported total.**

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

**First you have to be able to take the checkpoint, and on macOS that needs `--branchable`.**
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

A machine **created from a pack** checkpoints from v1.18.0 (#1361), and its restore reattaches the
pack's layers: on macOS on v1.18.2 a machine created from `from-vm.smolmachine`, checkpointed,
restored and packed again gave an artifact carrying the marker written after the pack.

A machine restored from a checkpoint packs, runs, and carries its rootfs. This is the case
[#1174](https://github.com/smol-machines/smolvm/pull/1174) changed, shipped in v1.14.3.

There is **no `machine restore` subcommand**, which is the obvious guess and gives
`unrecognized subcommand`. The restore path is `machine create --from <PATH>`, the same flag that
takes a `.smolmachine`, documented as "Create from a `.smolmachine` pack or restore a
`.smolcheckpoint`".

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
wide, while `--name` is documented as "Machine to prune". `smolvm pack prune`, which clears cached
pack extractions, does take no required argument. Any cleanup line that says `smolvm machine
prune` bare is wrong on this release.

**And the machine form starts the machine to do its work**, observed on Linux aarch64:

```
Starting machine...
Removing unreferenced layers...
No unreferenced layers to remove.
```

So it is worth running while the machine still exists and before deleting it, which is the order
`scripts/cleanup.sh` uses. Run after the delete it is a silent no-op.

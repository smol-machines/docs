---
title: "GPU CUDA: run CUDA workloads against a host GPU"
---

# GPU CUDA: run CUDA workloads against a host GPU

Runs CUDA compute workloads inside a smolvm microVM against a real host NVIDIA GPU, using smolvm's --cuda API remoting. Use when a workload in a machine needs a GPU; when nvidia-smi or /dev/nvidia* is missing inside a --cuda guest; when a CUDA program in a machine exits zero but seems not to touch the device; when the shim will not load in an Alpine image; or when checking whether CUDA is available on a given platform, including Windows. Do not use it for Vulkan graphics (--gpu), which is a separate feature with its own topic, and do not expect it on a Mac, which has no NVIDIA hardware.

Verified on **smolvm v1.14.6** against an **NVIDIA A10** (driver 580.105.08, Linux x86_64,
kernel 6.8.0-1046-nvidia), and on the same version against an **NVIDIA GeForce RTX 4050**
(driver 32.0.15.6626, Windows x86_64). Done means a program in the VM opens the device, creates a context, and moves
data to and from it.

> **The GPU path was not re-run on v1.16.1 or v1.18.2, and the stamp above is deliberately
> unchanged.** There is no NVIDIA hardware on this Mac or on the Lima box, so the GPU path keeps
> its v1.14.6 dates. What was re-run, on **v1.18.2 on 2026-09-24 on macOS arm64 and Linux
> aarch64**, is the no-GPU answer path: the preflight reports `gpu_present=no` without starting
> anything, and `--cuda` on a host with no GPU reaches a CPU emulation device, which the probe
> names rather than passing. See "Re-verified on v1.18.2".
>
> **Read this before trusting a step here.** **The Linux GPU path was re-run end to end on
> v1.14.6**, on a rented A10 instance: the preflight, the probe against the real device with two
> different glibc images, all three eval prompts, and the cleanup. **Windows was re-run on
> v1.14.6 too**, on 2026-09-11 against an RTX 4050: the probe, the two absences and the shim in a
> plain `alpine` guest. The section "What was not run" lists every remaining step individually.

## How this works, and why the checks are shaped this way

The guest gets **no NVIDIA driver and no `/dev/nvidia*`**. A compatibility `libcuda.so.1` is
injected at `/opt/smolvm-cuda` inside the guest and forwards CUDA driver calls over vsock to a host
daemon that owns the device. Nothing is needed on the host beyond a working NVIDIA driver: no extra
packages, no container toolkit, no device plugin.

Because the API is **remoted rather than passed through**, a program can start, link against
`libcuda.so.1` and exit zero without a GPU ever being reached. **Assert a device name and a
transferred result, never an exit code.**

## Procedure

**1. Preflight.**

```bash
scripts/preflight.sh
```

Read-only: it starts no VM and touches no NVIDIA state. It reports the GPU and driver version,
whether your user can open `/dev/kvm`, and the host's own `libcuda` count. `result=blocked` with
`gpu_present=no` is the answer that saves the most time, because the failure without it names
neither CUDA nor the GPU.

**If the question is "can this machine run CUDA", the preflight answers it and nothing else needs
to run.** Do not reach for the probe to decide that: on a host with no NVIDIA GPU the probe now
starts a VM, reaches a CPU emulation device and returns a passing round trip, which reads like a
yes. Verified on macOS arm64 on v1.16.1 and v1.18.2: `gpu_present=no`, `unsupported=cuda`, and the
note `no Apple Silicon or Intel Mac has an NVIDIA GPU, so --cuda has nothing to reach here`.

**2. Run the probe.**

```bash
scripts/run-cuda-probe.sh                     # python:3.12-slim
scripts/run-cuda-probe.sh <other glibc image>
```

It mounts `scripts/` into the guest and runs `cuda-probe.py` under `--cuda`, then asserts two
values from the output:

```
device_named=ok
data_roundtrip=ok
result=cuda_ok
```

On the A10 on v1.14.6, `cuda-probe.py`'s own output was:

```
load_shim -> ok /opt/smolvm-cuda/libcuda.so.1
cuInit -> 0
cuDeviceGetCount -> 0 count = 1
cuDeviceGetName -> 0 name = NVIDIA A10
cuCtxCreate -> 0
cuMemGetInfo -> 0 total MiB = 22587
cuMemAlloc   -> 0
cuMemcpyHtoD -> 0
cuMemcpyDtoH -> 0
roundtrip first 16 bytes match: True
cuMemFree    -> 0
```

`roundtrip ... True` is the one that matters. It is the only line that proves bytes reached the
device.

**3. Clean up.** CUDA images are large.

```bash
scripts/cleanup.sh --purge
smolvm machine prune --name <NAME> --all   # any persistent --cuda machine you kept
```

The probe runs are ephemeral and leave nothing to prune; `machine prune` takes a machine name and
is rejected without one.

`--cuda` changes nothing on the host: the shim is injected inside the guest only. Verified after a
full session of CUDA runs plus a Kubernetes install and teardown on the same box, where
`nvidia-smi` still reported the device and a whole-filesystem sweep for `*smolvm*` came back empty.

## Traps

Full detail in `references/traps.md`.

- **A zero exit code proves nothing.** The remoted API is why.
- **A device name and a passing round trip no longer prove a GPU either, as of v1.16.1**, and
  on v1.18.2 on macOS arm64 and Linux aarch64 alike. On a host
  with no NVIDIA hardware the shim answers with a CPU emulation device: `cuInit -> 0`,
  `cuDeviceGetCount -> 0 count = 1`, `cuDeviceGetName -> 0 name = smolvm CPU emulation device`,
  `total MiB = 1024`, and `roundtrip first 16 bytes match: True`. **The device name is the
  discriminator.** `scripts/run-cuda-probe.sh` now reports `device_kind=cpu_emulation` and
  `result=cpu_emulation_not_gpu` for it instead of `result=cuda_ok`.
- **`nvidia-smi` is absent inside the guest and that is correct.** So is `/dev/nvidia*`. Neither is
  a useful check.
- **Use a glibc image and load the shim by absolute path.** The shim is glibc, so an Alpine guest
  cannot load it, and relying on the loader path picks up whatever the image carries.
- **A fresh GPU cloud instance does not have KVM access for your user**, and the installer says the
  install succeeded anyway. `sg kvm -c` applies the group without a logout.
- **`agent did not become ready within 30 seconds` from the probe is about memory, not the GPU.**
  The probe asks for 8192 MiB. On v1.18.2 a Linux aarch64 host with no NVIDIA GPU failed that way,
  reached the CPU emulation device with the same probe at 1024 MiB, and failed the same way on a
  plain `machine run --mem 8192` with no `--cuda` at all. An earlier version of this packet read
  that failure as the missing GPU; the preflight is still what answers the GPU question.
- **`--cuda` and `--gpu` are different features.** `--cuda` is compute over vsock; `--gpu` is
  Vulkan over virtio-gpu, which reached a Venus device on macOS arm64 on v1.18.2 and is covered by
  `docs/gpu-vulkan`. On Windows `--gpu` is accepted and silently does nothing.

## Security defaults, and why they are the defaults

- **The guest never gets the device, and that is the isolation.** No `/dev/nvidia*` is passed
  through, so a workload in the machine cannot reach the driver directly, reprogram it, or see
  another VM's device state through it. What it gets is a forwarded API surface.
- **What that surface exposes is still real.** A remoted CUDA call runs against the host's driver
  and the host's memory allocator, so treat a `--cuda` machine as having a channel to a privileged
  host component. The VM boundary is what makes that acceptable; it is not zero authority.
- **Nothing here needs root or a container toolkit on the host.** If a procedure asks you to
  install a device plugin or run the CLI as root to get CUDA working, it is not this procedure.
- **The scripts wrap the public CLI only**, mount only this packet's own `scripts/` directory into
  the guest, and cleanup deletes only names it recorded under the `smolskill-` prefix.

## Platform arms

- **Linux x86_64 with an NVIDIA GPU**: **verified on an A10 on v1.14.6** (driver 580.105.08,
  kernel 6.8.0-1046-nvidia), preflight through cleanup, with the probe run against two glibc
  images.
- **Windows x86_64 with an NVIDIA GPU**: **verified on an RTX 4050 on v1.14.6**, on 2026-09-11
  (driver 32.0.15.6626), including the device name and a 1 MiB device round trip.
  `references/windows.md`. **This contradicts three documentation pages**, which this branch
  corrects.
- **macOS arm64 and Intel**: **not applicable.** No Mac has an NVIDIA GPU, so `--cuda` has nothing
  to reach. The preflight says so rather than letting a run time out.
- **Linux aarch64**: no NVIDIA hardware on the hosts available here. The preflight and the probe
  against the CPU emulation device were run on v1.18.2.
- **Multi-GPU, GPU forks and clones, and a real training or inference workload**: not run anywhere.

## Eval prompts, and what they produced

The first two need a GPU host and are recorded from the earlier runs; the third was run in this
session. Which is which is stated per prompt.

**1. "Run a CUDA workload in a smolvm machine and prove it reached the GPU." (re-run on v1.14.6
on the A10)**

```
load_shim -> ok /opt/smolvm-cuda/libcuda.so.1
cuInit -> 0
cuDeviceGetCount -> 0 count = 1
cuDeviceGetName -> 0 name = NVIDIA A10
cuCtxCreate -> 0
cuMemGetInfo -> 0 total MiB = 22587
cuMemAlloc   -> 0
cuMemcpyHtoD -> 0
cuMemcpyDtoH -> 0
roundtrip first 16 bytes match: True
cuMemFree    -> 0
```

**2. "`nvidia-smi` is not in my `--cuda` guest and there is no `/dev/nvidia0`. Is the GPU
working?" (re-run on v1.14.6 on the A10)**

Both absences are correct. Inside a `--cuda` guest on `python:3.12-slim`:

```
--- /opt/smolvm-cuda ---
libcublas.so.11
libcublas.so.12
libcublas.so.13
libcublasLt.so.11
libcublasLt.so.12
libcublasLt.so.13
libcuda.so
libcuda.so.1
--- /dev/nvidia* ---
ls: cannot access '/dev/nvidia*': No such file or directory
--- nvidia-smi ---
nvidia-smi: not present in the image
--- SMOLVM_CUDA env ---
SMOLVM_CUDA_ZEROCOPY=1
```

The driver API is the check, and the probe above is what runs it.

**3. "Can this machine run CUDA?" (re-run on v1.14.6; the A10 answer is new, the two negative
answers are from hosts with no NVIDIA hardware)**

On the A10, where the answer is yes:

```
platform=linux-x86_64
accel=kvm
accel_access=ok
gpu_present=yes
gpu=NVIDIA A10, 580.105.08
host_libcuda=1
guest_needs_glibc_image=yes
guest_shim_path=/opt/smolvm-cuda/libcuda.so.1
result=ready
```

And where it is no:

macOS 26.6.2 arm64:

```
platform=darwin-aarch64
gpu_present=no
unsupported=cuda,vulkan
note=no Apple Silicon or Intel Mac has an NVIDIA GPU, so --cuda has nothing to reach here. This is a hardware fact, not a smolvm limitation.
result=blocked
```

Lima `linux-kvm`, Ubuntu 24.04 aarch64:

```
platform=linux-aarch64
accel_access=ok
gpu_present=no
note=no nvidia-smi on this host, so there is no GPU for the remoting daemon to own
host_libcuda=0
result=blocked
```

and running the probe anyway, to record what a user sees when they skip the preflight:

```
Starting ephemeral machine (vm-5d98e4be)...
Error: agent operation failed: start machine: agent operation failed: wait for ready:
agent did not become ready within 30 seconds
device_named=FAIL
data_roundtrip=FAIL
result=FAILED
```

The error names neither CUDA nor the missing device.

## Re-verified on v1.18.2, the no-GPU path

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64). Neither host has NVIDIA hardware, so
this covers the answer a GPU-less host gives and nothing about the GPU path.

**The preflight, both hosts:** `gpu_present=no` and `result=blocked`, with the macOS note that no
Mac has an NVIDIA GPU and the Linux note that there is no `nvidia-smi` for the daemon to own.

**The probe.** macOS, as shipped:

```
  cuDeviceGetName -> 0 name = smolvm CPU emulation device
  cuMemGetInfo -> 0 total MiB = 1024
  roundtrip first 16 bytes match: True
device_named=ok
data_roundtrip=ok
device_kind=cpu_emulation
result=cpu_emulation_not_gpu
```

Linux aarch64 at the probe's own `--mem 8192`: `agent did not become ready within 30 seconds`.
The same probe with `--mem 1024` gave the same five lines as macOS, and a plain
`machine run --mem 8192 --net --image alpine` with no `--cuda` failed exactly as the probe did.
That box could not boot guests above 2048 MiB in time that day, on v1.16.1 as well, so the timeout
is the host's memory and the missing GPU plays no part in it. The trap above and the probe's own
failure text now say so.

## Re-verified on v1.14.6

Run 2026-09-11 PT against v1.14.6 from the published release, installed into an isolated data root
on a rented **NVIDIA A10** instance: 30 vCPU Intel Xeon Platinum 8358, 222 GiB memory, kernel
6.8.0-1046-nvidia, driver 580.105.08, 23028 MiB of device memory.

**The GPU path is no longer written from an earlier run.** preflight, probe, all three eval
prompts and cleanup were executed in the packet's own order:

```
preflight            result=ready, gpu_present=yes, gpu=NVIDIA A10, 580.105.08, host_libcuda=1
probe, default image device_named=ok, data_roundtrip=ok, result=cuda_ok
probe, second image  device_named=ok, data_roundtrip=ok, result=cuda_ok
cleanup --purge      machines=clean, vm_processes=none
```

The probe was run against **two** glibc images, `python:3.12-slim` and `python:3.12-bookworm`, and
both reported `name = NVIDIA A10` and `total MiB = 22587` with the 1 MiB round trip returning the
same bytes.

**The host is untouched by `--cuda`, and that is now measured rather than quoted.** After the
session `nvidia-smi` reported `NVIDIA A10, 580.105.08, 23028 MiB, 0 MiB` used, a whole-filesystem
sweep for `*smolvm*` outside the install prefix and the data root returned nothing, and the eight
NVIDIA kernel modules were still loaded.

**The KVM precondition in the traps reproduced on this instance.** A fresh box has `/dev/kvm` as
`root:kvm` with the login user outside the group, so the preflight reported `KVM_DENIED` until the
group was granted. The single-command `sg kvm -c` form the traps recommend was not the route used
here; a group change plus a new login session was.

**One step failed as written on v1.14.6 and is now fixed.** The cleanup section said `smolvm
machine prune` bare, which the CLI rejects:

```
$ smolvm machine prune
Usage: smolvm machine prune --name <NAME>
```

Its help reads as host-wide ("Remove unused images and layers to free disk space") while the
command prunes one machine's unreferenced layers, `--all` its cached images. The section now names
the machine and says the ephemeral probe runs leave nothing to prune.

## What was not run

The Linux GPU path was re-run on v1.14.6, and the Windows one on 2026-09-11. What remains unrun:

- **The preflight and the cleanup on Windows.** `scripts/*.sh` are POSIX shell and do not run
  there, so the 2026-09-11 v1.14.6 run issued the probe and the eval prompts by hand.
- **`--cuda` with a CUDA base image** (`nvidia/cuda:...`), and the `apt-get install -y python3`
  those images need. Both probe runs used a Python image, which is what the packet recommends.
- **The `sg kvm -c` single-command remedy.** The `KVM_DENIED` state it addresses did reproduce on
  a fresh instance; the fix applied was a group change and a new session.

Never run anywhere, then or now:

- **GPU forks and clones.** `introduction/concepts/gpu.md` sells this as a reason for the remoting
  design, and a CUDA clone has its own shorter 10 s ready timeout.
- **Multi-GPU**, and contention between two machines sharing one device.
- **A real workload.** These are driver-API assertions, not a training or inference run, and say
  nothing about throughput or how much of the CUDA API surface is implemented.

## Related packets

- `install` for the KVM group precondition, which a fresh GPU instance fails.
- `teardown` for the cleanup script. CUDA images are large enough that `machine prune` is worth it.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can run CUDA workloads inside a smolvm machine.
# Read-only: starts no VM, touches no NVIDIA state, changes no group membership.
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
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; the GPU path was last exercised on an A10 on $VERIFIED_VERSION, so check each step's output against the binary"
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
emit platform "$(printf '%s' "$kernel" | tr '[:upper:]' '[:lower:]')-$arch"

case "$kernel" in
    Darwin)
        emit accel hvf
        if [ "$(sysctl -n kern.hv_support 2>/dev/null)" = "1" ]; then emit accel_access ok; else emit accel_access denied; fi
        emit gpu_present no
        emit unsupported "cuda"
        blocked=1
        note "no Apple Silicon or Intel Mac has an NVIDIA GPU, so --cuda has nothing to reach here. This is a hardware fact, not a smolvm limitation."
        ;;
    Linux)
        emit accel kvm
        # A fresh cloud GPU instance fails this, and the installer warns and
        # continues, so the install succeeds and the first VM fails.
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            emit accel_access ok
        else
            emit accel_access denied
            blocked=1
            note "your user cannot open /dev/kvm. Fix without logging out: sudo usermod -aG kvm \$USER, then run the next command through sg kvm -c '...'"
        fi
        emit unsupported "vulkan"
        ;;
    *)
        emit accel unknown
        emit accel_access unknown
        note "this script covers macOS and Linux. CUDA does work on Windows, against the documentation; see references/windows.md, written from a run and not re-run by this packet."
        blocked=1
        ;;
esac

if command -v nvidia-smi >/dev/null 2>&1; then
    gpu="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"
    if [ -n "$gpu" ]; then
        emit gpu_present yes
        emit gpu "$gpu"
    else
        emit gpu_present no
        blocked=1
        note "nvidia-smi is installed but reported no device"
    fi
elif [ "$kernel" = "Linux" ]; then
    emit gpu_present no
    blocked=1
    note "no nvidia-smi on this host, so there is no GPU for the remoting daemon to own"
fi

# The host's own libcuda is what the remoting daemon forwards to. The guest gets
# none, and that is the design.
if command -v ldconfig >/dev/null 2>&1; then
    emit host_libcuda "$(ldconfig -p 2>/dev/null | grep -c 'libcuda\.so\.1')"
fi

emit guest_needs_glibc_image yes
emit guest_shim_path /opt/smolvm-cuda/libcuda.so.1

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/run-cuda-probe.sh`

```bash
#!/usr/bin/env bash
# Run the CUDA driver-API probe inside a --cuda machine and assert its values.
#
# usage: run-cuda-probe.sh [<image>]      (default python:3.12-slim)
#
# The image must be glibc. The injected shim is glibc, so an Alpine (musl) guest
# cannot load it. python:3.12-slim is small and already has Python, which CUDA
# base images do not.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${1:-python:3.12-slim}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

out="$("$SMOLVM" machine run --cuda --net --mem 8192 \
    -v "$here:/probe" --image "$IMAGE" -- python3 /probe/cuda-probe.py 2>&1)"
printf '%s\n' "$out" | sed 's/^/  /'

fail=0
check() {
    if printf '%s' "$out" | grep -q "$2"; then
        printf '%s=ok\n' "$1"
    else
        printf '%s=FAIL\n' "$1"
        fail=1
    fi
}

# A device NAME, not a zero return code: on a remoted API a program links and
# exits zero without a GPU ever being reached.
check device_named 'name = '
# And the round trip, which is the only proof that bytes reached the device.
check data_roundtrip 'roundtrip first 16 bytes match: True'

# v1.16.1 and later answer on a host with no NVIDIA GPU with a CPU emulation device, which
# passes both checks above. The device name is what tells them apart.
if printf '%s' "$out" | grep -qi 'name = .*emulation'; then
    printf 'device_kind=cpu_emulation\n'
    printf 'result=cpu_emulation_not_gpu\n'
    printf 'The guest reached a device and the round trip returned, but the device is\n'
    printf 'smolvm CPU emulation, not an NVIDIA GPU. Nothing here was accelerated. Run\n'
    printf 'scripts/preflight.sh: gpu_present=no says the same thing without starting a VM.\n'
    exit 1
fi
printf 'device_kind=gpu\n'

if [ "$fail" -eq 0 ]; then
    printf 'result=cuda_ok\n'
else
    printf 'result=FAILED\n'
    printf 'Run scripts/preflight.sh. The three causes, and none of them says so in the error:\n'
    printf '  - A guest too large for this host. The probe asks for 8192 MiB, and a host that cannot\n'
    printf '    boot that inside the fixed 30 s fails with "agent did not become ready within 30\n'
    printf '    seconds". Run smolvm machine run --mem 8192 --net --image alpine -- true: if that\n'
    printf '    fails the same way, it is the host, not CUDA.\n'
    printf '  - A musl image. The injected shim is glibc, so an Alpine guest cannot load it.\n'
    printf '  - A machine started without --cuda, in which case /opt/smolvm-cuda does not exist.\n'
fi
exit "$fail"
```

### `scripts/cuda-probe.py`

```python
#!/usr/bin/env python3
"""Prove a smolvm --cuda guest reaches a real GPU, and that data moves.

Run this inside the guest. It uses the CUDA driver API through ctypes, so it
needs no CUDA toolkit, no torch and no nvidia-smi.

Why it is shaped this way. CUDA in smolvm is REMOTED, not passed through: the
guest gets no NVIDIA driver and no /dev/nvidia*, and a compatibility
libcuda.so.1 forwards driver calls over vsock to a host daemon that owns the
device. A program can therefore start, link against libcuda.so.1 and exit zero
without a GPU ever being reached, so an exit code proves nothing. The two
assertions that mean something are a device NAME and a byte-for-byte round trip
through device memory.
"""
import ctypes
import sys

# Load by absolute path rather than by soname. The shim is injected at a fixed
# location in the guest, and relying on the loader path picks up whatever the
# image happens to carry.
SHIM = "/opt/smolvm-cuda/libcuda.so.1"

try:
    lib = ctypes.CDLL(SHIM)
except OSError as exc:
    print(f"load_shim -> FAILED {exc}")
    print("If this says 'not found', the machine was started without --cuda.")
    print("If it names a musl or ld-linux problem, use a glibc image: the shim is glibc,")
    print("so an Alpine guest cannot load it. python:3.12-slim works and has Python already.")
    sys.exit(1)

print(f"load_shim -> ok {SHIM}")

rc = lib.cuInit(0)
print("cuInit ->", rc)

count = ctypes.c_int(-1)
print("cuDeviceGetCount ->", lib.cuDeviceGetCount(ctypes.byref(count)), "count =", count.value)

buf = ctypes.create_string_buffer(128)
print("cuDeviceGetName ->", lib.cuDeviceGetName(buf, 128, 0), "name =", buf.value.decode())

ctx = ctypes.c_void_p()
print("cuCtxCreate ->", lib.cuCtxCreate_v2(ctypes.byref(ctx), 0, 0))

free, total = ctypes.c_size_t(), ctypes.c_size_t()
print("cuMemGetInfo ->", lib.cuMemGetInfo_v2(ctypes.byref(free), ctypes.byref(total)),
      "total MiB =", total.value // (1024 * 1024))

# The assertion that matters: 1 MiB to the device and back, unchanged.
N = 1024 * 1024
src = (ctypes.c_ubyte * N)(*([7] * 16 + [0] * (N - 16)))
dptr = ctypes.c_void_p()
print("cuMemAlloc   ->", lib.cuMemAlloc_v2(ctypes.byref(dptr), ctypes.c_size_t(N)))
print("cuMemcpyHtoD ->", lib.cuMemcpyHtoD_v2(dptr, src, ctypes.c_size_t(N)))
dst = (ctypes.c_ubyte * N)()
print("cuMemcpyDtoH ->", lib.cuMemcpyDtoH_v2(dst, dptr, ctypes.c_size_t(N)))
print("roundtrip first 16 bytes match:", list(dst[:16]) == [7] * 16)
print("cuMemFree    ->", lib.cuMemFree_v2(dptr))
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

PACKET="gpu-cuda"
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

## CUDA traps

### A zero exit code proves nothing on a remoted API

**This is the trap the whole packet is shaped around.** CUDA in smolvm is remoted, not passed
through: the guest gets no NVIDIA driver and no `/dev/nvidia*`, and a compatibility `libcuda.so.1`
forwards driver calls over vsock to a host daemon that owns the device. A program can therefore
start, link against `libcuda.so.1`, and exit zero without a GPU ever being reached.

Assert a **device name** and a **computed or copied result**. `scripts/cuda-probe.py` asserts both:
`cuDeviceGetName` returning a real name, and a 1 MiB host to device to host round trip returning
the same bytes.

### `nvidia-smi` is absent inside a `--cuda` guest, and that is correct

So is `/dev/nvidia*`. Both are the documented remoting design, not a fault, and neither is a useful
check. Use the driver API.

### Use a glibc image, and load the shim by absolute path

The injected shim is glibc, so an Alpine (musl) guest cannot load it. `python:3.12-slim` is small
and already has Python.

Load it as `/opt/smolvm-cuda/libcuda.so.1` rather than by soname: relying on the loader path picks
up whatever the image happens to carry, and the shim is at a fixed location.

**CUDA base images do not ship `python3`**, so `nvidia/cuda:...-base-...` needs
`apt-get install -y python3` in the guest first, or a `-devel` image. That is a reason to prefer a
small glibc image over a CUDA one for a probe.

### A fresh GPU cloud instance does not have KVM access for your user

`/dev/kvm` is `crw-rw---- root:kvm` and your account is not in the `kvm` group. The installer warns
and continues, so the install succeeds and the first VM fails. Apply the group without logging out:

```bash
sudo usermod -aG kvm "$USER"
sg kvm -c 'smolvm machine run --mem 2048 --net --image alpine -- echo OK'
```

### On a host with no NVIDIA GPU, the failure names neither CUDA nor the GPU

Observed on Ubuntu 24.04 aarch64 on 2026-09-07, running `machine run --cuda` on a host with no
NVIDIA hardware:

```
Starting ephemeral machine (vm-5d98e4be)...
Error: agent operation failed: start machine: agent operation failed: wait for ready:
agent did not become ready within 30 seconds
```

**That message reads exactly like host load**, and there is no mention of CUDA, the shim or a
missing device. `scripts/preflight.sh` reports `gpu_present=no` before you run anything, which is
the only thing that tells you whether a GPU is there.

**Re-measured on v1.18.2, 2026-09-24, and the missing GPU was not the cause.** On the same kind of
host, Lima `linux-kvm` with no NVIDIA hardware, `scripts/run-cuda-probe.sh` at its `--mem 8192`
failed with the message above; the same probe at `--mem 1024` reached `smolvm CPU emulation
device` and returned `result=cpu_emulation_not_gpu`; and `machine run --mem 8192 --net --image
alpine` with no `--cuda` failed with the same message. That box booted 2048 MiB and not 2560 that
day. So the timeout is the guest's size on that host, and on v1.16.1 and later a GPU-less host
answers `--cuda` with the emulation device instead.

### Large CUDA images may not pull

`nvidia/cuda:12.4.1-base-ubuntu22.04` failed after 582 s with `crane blob failed ... unexpected
EOF` on the Windows host's network. That is a transfer failure, not a CUDA one, but it is another
reason to prefer a small image.

### Memory: give the machine real headroom

The verified runs used `--mem 8192`. On a small host, see the ready-timeout trap in the `install`
packet: the 30 s limit is a hard-coded constant and no flag raises it for `machine run` or
`machine start`.

### `--cuda` changes nothing on the host

The remoting shim is injected at `/opt/smolvm-cuda` **inside the guest only**, and no host NVIDIA
state is touched. Verified after a full session of CUDA runs plus a Kubernetes install and teardown
on the same box: `nvidia-smi` still reported the device, and a whole-filesystem sweep for
`*smolvm*` came back empty.

### `--cuda` and `--gpu` are different features

`--cuda` is compute over vsock. `--gpu` is Vulkan graphics over virtio-gpu; on the hosts tested
through v1.16.1 the host renderer reported the Venus capset at version 0, and on v1.18.2 on macOS
arm64 a guest reached `Virtio-GPU Venus (Apple M4)`. `docs/gpu-vulkan` has it. They share nothing
but the word GPU. On Windows `--gpu` is accepted and silently does nothing.

### Docs drift for the CUDA path

None found for `--cuda` itself: `introduction/concepts/gpu.md` describes the remoting design, the
absence of `/dev/nvidia*` and the `libcuda.so.1` shim accurately.

The drift is about **Windows**, where three pages say GPU acceleration is unavailable and CUDA
works. See `references/windows.md`.

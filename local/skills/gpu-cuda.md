---
title: "GPU CUDA: run CUDA workloads against a host GPU"
---

# GPU CUDA: run CUDA workloads against a host GPU

Runs CUDA compute workloads inside a smolvm microVM against a real host NVIDIA GPU, using smolvm's --cuda API remoting. Use when a workload in a machine needs a GPU; when nvidia-smi or /dev/nvidia* is missing inside a --cuda guest; when a CUDA program in a machine exits zero but seems not to touch the device; when the shim will not load in an Alpine image; or when checking whether CUDA is available on a given platform, including Windows. Do not use it for Vulkan graphics (--gpu), which is a separate feature that works on no tested host, and do not expect it on a Mac, which has no NVIDIA hardware.

## What it does

Preflight, run a probe, clean up. The probe mounts the packet's own scripts into the guest, runs a CUDA program under `--cuda`, and asserts two values from its output: that a device was named, and that a data round trip came back.

Both assertions exist because of how the feature works. The guest gets no NVIDIA driver and no `/dev/nvidia*`. A compatibility `libcuda.so.1` is injected inside the guest and forwards CUDA driver calls over vsock to a host daemon that owns the device, so nothing is needed on the host beyond a working NVIDIA driver: no extra packages, no container toolkit, no device plugin. Because the API is remoted rather than passed through, a program can start, link against `libcuda.so.1` and exit zero without a GPU ever being reached. Assert a device name and a transferred result, never an exit code.

The absences are correct, not symptoms: `nvidia-smi` is not in the guest, `/dev/nvidia*` does not exist, and neither is a useful check. The shim is glibc, so an Alpine guest cannot load it, and it should be loaded by absolute path rather than through whatever the image's loader picks up. On a host with no NVIDIA GPU the error names neither CUDA nor the GPU: it reads exactly like host load, which is why the preflight is worth running first. CUDA images are large, so cleanup is worth doing.

The docs cover the remoting design and its tradeoffs under [CUDA API remoting](/docs/introduction/concepts/gpu#cuda-api-remoting).

## What it checks first

- The GPU and its driver version, and `result=blocked` with `gpu_present=no` when there is none
- Whether your user can open `/dev/kvm`. A fresh GPU cloud instance does not have that access, and the installer reports the install succeeded anyway
- The host's own `libcuda` count

The preflight is read-only: it starts no VM and touches no NVIDIA state. Enabling `--cuda` changes nothing on the host, because the shim is injected inside the guest only.

## What it is not for

Vulkan graphics, which is `--gpu`, a separate feature over virtio-gpu; on Windows `--gpu` is accepted and silently does nothing. A Mac, which has no NVIDIA hardware for the remoting daemon to own. For both paths and how they differ, see [GPU](/docs/introduction/concepts/gpu).

## Platforms

| Platform | State |
|---|---|
| Linux x86_64 with an NVIDIA GPU | Verified on an A10, in the run the packet is built from. Not re-run |
| Windows x86_64 with an NVIDIA GPU | Verified on an RTX 4050, including a 1 MiB device round trip. Not re-run |
| macOS arm64 and Intel | Not applicable. No Mac has an NVIDIA GPU, and the preflight says so rather than letting a run time out |
| Linux aarch64 | No NVIDIA hardware on the hosts behind the packet. Only the preflight and the failure path were run |

No GPU host was available when the packet was written, so every step that needs one is written from those earlier runs. The packet lists each unrun step individually. Multi-GPU, GPU forks and clones, and a real training or inference workload were not run anywhere: these are driver-API assertions, and they say nothing about throughput or how much of the CUDA API surface is implemented.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill gpu-cuda
```

The procedure is [`skills/gpu-cuda/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/gpu-cuda/SKILL.md).

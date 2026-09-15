---
title: GPU
---

# GPU

Local smolvm has two GPU paths for different workloads: Vulkan graphics through virtio-gpu and CUDA compute through API remoting.

## Vulkan

The Vulkan path presents a paravirtualized GPU to the guest through virtio-gpu and Venus. It fits accelerated graphics workloads such as headless browsers, WebGL, and OpenGL ES through ANGLE.

Vulkan support depends on the host graphics stack. It is not available on native Windows: the current release accepts `--gpu` there without effect, and the guest gets no `/dev/dri`.

Enable it with `--gpu`, `gpu = true` in a Smolfile, or `gpu: true` / `gpu=True` in the local SDK:

```bash
smolvm machine run --gpu --net --image alpine -- vulkaninfo --summary
```

On macOS, the release bundles virglrenderer and MoltenVK. On Linux, install virglrenderer and the Vulkan driver for the host GPU; for example:

```bash
# Debian or Ubuntu
sudo apt install virglrenderer0 mesa-vulkan-drivers
```

The guest also needs a Vulkan loader and the Venus virtio ICD. Some images require `VK_ICD_FILENAMES` to point at that ICD explicitly, for example `/usr/share/vulkan/icd.d/virtio_icd.x86_64.json` in an x86_64 guest.

### Nix and NixOS hosts

The release tarball does not ship virglrenderer, and libkrun loads it at
runtime rather than linking it, so the library has to be reachable by the
dynamic loader. A Nix install of smolvm (`nix run github:smol-machines/smolvm`)
sets the package's own library path only, and on NixOS there is no system-wide
loader cache to fall back on, so `--gpu` cannot find virglrenderer unless you
put it on the path yourself:

```bash
export LD_LIBRARY_PATH="$(nix build --no-link --print-out-paths nixpkgs#virglrenderer)/lib:$(nix build --no-link --print-out-paths nixpkgs#libepoxy)/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

On NixOS, append `/run/opengl-driver/lib` as well so the host GL and Vulkan
drivers are visible. On a non-NixOS host, wrap the command with
[nixGL](https://github.com/nix-community/nixGL) for the same reason, for
example `nixGL smolvm machine run --gpu ...`; nixGL alone is not enough, since
its wrappers do not add virglrenderer. Using the nixpkgs virglrenderer rather
than the distribution's keeps it in one closure with the Mesa that nixGL
provides, and nixpkgs ships a newer virglrenderer with Venus enabled than
Debian does. This recipe was reported working on Debian 13 with an AMD GPU
([smolvm#907](https://github.com/smol-machines/smolvm/issues/907)).

### When virglrenderer is missing

Since v1.12.0 a `--gpu` start checks for `libvirglrenderer.so.1` and
`libepoxy.so.0` before the VM boots and fails with a message that names them:

```text
Linux Vulkan GPU support (--gpu) requires a compatible libvirglrenderer.so.1
and host Vulkan driver. Install virglrenderer plus your Mesa/Vulkan driver ...
```

Older releases died later, on the first GPU call, with
`symbol lookup error: ... libkrun.so: undefined symbol: virgl_set_debug_callback`.
That error is the same missing library, not a version mismatch inside the
bundled libraries.

### Debugging the GPU path

`SMOLVM_GPU_DEBUG=1` on the process that starts the machine keeps the boot
process's stderr in a `gpu-debug.log` beside the machine's console log, so
virglrenderer and MoltenVK errors are captured instead of discarded (Linux and
macOS). `--gpu-vram <MiB>` sets the GPU shared-memory region, default 4096; it
is ignored without `--gpu`.

## CUDA API remoting

The CUDA path does not pass an NVIDIA device into the VM. The guest has no NVIDIA driver and no `/dev/nvidia*` devices. Compatibility libraries implement the CUDA and NVML interfaces and send calls over vsock to a host daemon that owns the real NVIDIA driver and GPU.

This design allows multiple machines to share a host GPU and lets a warm CUDA machine be branched. A branch reconnects to the host daemon and can reuse prepared GPU state.

Enable this separate path with `--cuda` or `cuda: true` / `cuda=True` in the local SDK. The host needs a compatible NVIDIA GPU and driver with `libcuda.so.1` available. It works on Linux hosts and on Windows hosts with WHP, where it was verified on an RTX 4050 laptop. The guest image does not need an NVIDIA kernel driver.

The [gpu-cuda](/docs/local/skills/gpu-cuda) skill packet is a procedure for running a workload on this path, including why an exit code proves nothing when the API is remoted.

## Tradeoffs

CUDA remoting adds transport and marshalling work to each API call. Workloads with many small, latency-sensitive calls can see more overhead than workloads dominated by larger kernels and transfers.

The remoting layer must implement the CUDA API calls a workload uses. Unsupported calls can fail even when direct GPU access would support them. The host still needs a compatible NVIDIA GPU and driver.

GPU sharing is not hardware partitioning. Machines can contend for GPU memory and scheduling.

Only expose GPU access to workloads you trust under the host's GPU isolation model. The VM still isolates CPU, memory, and filesystem access, but the remoting daemon and shared GPU remain part of the trusted computing base.

::: warning Hosted cloud does not provide GPU machines
Everything on this page applies to local smolvm and the embedded SDK target.
The cloud create API has no GPU resource fields, and the SDK does not send
`resources.gpu`, `resources.gpuVramMib`, or `resources.cuda` to that backend —
setting them for a cloud machine has no effect. Run smolvm on your own GPU host
instead.
:::

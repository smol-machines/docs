---
title: GPU
---

# GPU

Local smolvm has two GPU paths for different workloads: Vulkan graphics through virtio-gpu and CUDA compute through API remoting.

## Vulkan

The Vulkan path presents a paravirtualized GPU to the guest through virtio-gpu and Venus. It fits accelerated graphics workloads such as headless browsers, WebGL, and OpenGL ES through ANGLE.

Vulkan support depends on the host graphics stack. It is not currently available on native Windows.

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

## CUDA API remoting

The CUDA path does not pass an NVIDIA device into the VM. The guest has no NVIDIA driver and no `/dev/nvidia*` devices. Compatibility libraries implement the CUDA and NVML interfaces and send calls over vsock to a host daemon that owns the real NVIDIA driver and GPU.

This design allows multiple machines to share a host GPU and lets a warm CUDA machine be forked. A fork reconnects to the host daemon and can reuse prepared GPU state.

Enable this separate path with `--cuda` or `cuda: true` / `cuda=True` in the local SDK. The host needs a compatible NVIDIA GPU and driver with `libcuda.so.1` available. The guest image does not need an NVIDIA kernel driver.

## Tradeoffs

CUDA remoting adds transport and marshalling work to each API call. Workloads with many small, latency-sensitive calls can see more overhead than workloads dominated by larger kernels and transfers.

The remoting layer must implement the CUDA API calls a workload uses. Unsupported calls can fail even when direct GPU access would support them. The host still needs a compatible NVIDIA GPU and driver.

GPU sharing is not hardware partitioning. Machines can contend for GPU memory and scheduling.

Only expose GPU access to workloads you trust under the host's GPU isolation model. The VM still isolates CPU, memory, and filesystem access, but the remoting daemon and shared GPU remain part of the trusted computing base.

These GPU paths are documented for local smolvm. Hosted GPU availability in smol cloud is not currently a documented public product surface.

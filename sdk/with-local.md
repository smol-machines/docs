---
title: Use SDK in Local
---

# Use SDK in Local

The local target runs a microVM through the engine embedded in the `smolmachines` package. Select `target: "local"` explicitly when an environment may also contain cloud credentials.

## Platform requirements

The prebuilt local SDK supports:

- macOS 11 or later on Apple Silicon
- Linux x86_64 or arm64 with glibc 2.34 or later
- Linux kernel 5.4 or later, with access to `/dev/kvm`

Common supported Linux distributions include Ubuntu 22.04+, Debian 12, RHEL 9, and Amazon Linux 2023.

The local SDK is not currently prebuilt for Intel Macs, native Windows, or Linux systems using glibc earlier than 2.34. Use the [cloud target](/docs/sdk/with-cloud) from those hosts.

Check Linux KVM access with:

```bash
ls -la /dev/kvm
```

If your user lacks access, add it to the `kvm` group and start a new login session:

```bash
sudo usermod -aG kvm "$USER"
```

## No separate engine install

The npm package and Python wheel include the local runtime libraries, boot helper, and guest root filesystem. You do not need to:

- Install the `smolvm` CLI
- Run `smolvm serve`
- Start a background daemon

`Machine.create()` boots the embedded engine in process.

## Select local explicitly

```ts
import { Machine } from "smolmachines";

const machine = await Machine.create(
  { resources: { cpus: 2, memoryMb: 1024, network: true } },
  { target: "local" },
);
```

```python
from smol import ConnectOptions, Machine, MachineConfig, ResourceSpec

machine = Machine.create(
    MachineConfig(resources=ResourceSpec(cpus=2, memory_mb=1024, network=True)),
    ConnectOptions(target="local"),
)
```

## Run an OCI image

Use `run(image, command)` to pull an OCI image and run a command in it:

```ts
const result = await machine.run(
  "node:22-alpine",
  ["node", "-e", "console.log(process.version)"],
);
result.assertSuccess();
```

```python
result = machine.run(
    "python:3.12-alpine",
    ["python", "-c", "import sys; print(sys.version)"],
)
result.assert_success()
```

The image pull runs inside the guest, so `run()` with an uncached registry image needs `resources.network` enabled. Beyond the pull, enable it only when the guest workload needs DNS or outbound network access; guest networking is off by default.

## Mount a host directory

Local machines can bind an absolute host path into the guest. Mounts are writable by default.

```ts
const machine = await Machine.create(
  {
    mounts: [
      {
        source: "/absolute/path/to/project",
        target: "/workspace",
        readOnly: true,
      },
    ],
  },
  { target: "local" },
);
```

```python
from smol import MachineConfig, MountSpec

config = MachineConfig(
    mounts=[
        MountSpec(
            source="/absolute/path/to/project",
            target="/workspace",
            read_only=True,
        )
    ]
)
```

Only mount paths the workload needs. Code in the machine can read or modify every writable path you expose.

::: tip `/workspace` and host mounts
Every image-based machine exposes `/workspace` backed by the machine's storage
disk, which persists across exec sessions and stop/start. Mounting a host
directory at `/workspace` takes priority: your host directory is used instead of
the storage-disk workspace. Any other mount target leaves `/workspace` intact.
:::

Files written through a writable mount are created on the host with the ownership produced by the guest process, which may be root. Prefer a dedicated directory and a read-only mount when the workload does not need to modify it.

## Local-only methods

These methods apply to the local target:

- `run()` pulls an image and executes a command in it
- `pullImage()` / `pull_image()` caches an OCI image
- `listImages()` / `list_images()` lists cached images

`endpoint()` and the public `url()` workflow require the cloud control plane. For a local service, publish a host-to-guest port with `PortSpec` and connect to the host port directly.

See [Machine API](/docs/sdk/machine-api) for configuration and lifecycle methods.

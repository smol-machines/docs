---
title: Use SDK on Cloud
---

# Use SDK on Cloud

The cloud target uses the same `Machine` API as local and sends operations to smol cloud. It does not start a local microVM, so the host does not need KVM, Hypervisor.framework, or a separate hypervisor installation.

## Create an account and API key

Create an account in the [smol cloud console](/console), then create a durable API key. Cloud API keys begin with `smk_`.

Set the key in the canonical SDK environment variable:

```bash
export SMOL_CLOUD_TOKEN="smk_..."
```

The SDK reads:

- `SMOL_CLOUD_TOKEN` for authentication
- `SMOL_CLOUD_URL` to override the API base URL

The default API base URL is `https://api.smolmachines.com`. Most applications should not override it.

The SDK can also reuse an authenticated `smol` CLI session. Use a durable API key for CI and unattended workloads.

## Create a cloud machine

A cloud machine requires an OCI image.

::: code-group

```ts [TypeScript]
import { Machine } from "smolmachines";

const machine = await Machine.create(
  {
    image: "python:3.12-alpine",
    resources: {
      cpus: 2,
      memoryMb: 1024,
      network: true,
    },
  },
  { target: "cloud" },
);

try {
  const result = await machine.exec([
    "python",
    "-c",
    "print('ready for work')",
  ]);
  result.assertSuccess();
  console.log(result.stdout);
} finally {
  await machine.delete();
}
```

```python [Python]
from smol import ConnectOptions, Machine, MachineConfig, ResourceSpec

machine = Machine.create(
    MachineConfig(
        image="python:3.12-alpine",
        resources=ResourceSpec(
            cpus=2,
            memory_mb=1024,
            network=True,
        ),
    ),
    ConnectOptions(target="cloud"),
)

try:
    result = machine.exec(["python", "-c", "print('ready for work')"])
    result.assert_success()
    print(result.stdout)
finally:
    machine.delete()
```

:::

You may pass credentials directly instead of using environment variables:

```ts
const connection = {
  target: "cloud" as const,
  apiKey: "smk_...",
  baseUrl: "https://api.smolmachines.com",
};
```

```python
connection = ConnectOptions(
    target="cloud",
    api_key="smk_...",
    base_url="https://api.smolmachines.com",
)
```

Avoid hard-coding keys in source control.

## State and readiness

`Machine.create()` waits until the cloud machine is ready before returning. A state of `"started"` only means the VM process launched. It does not mean the guest agent or a published service is ready.

`Machine.connect()` attaches without waiting. Call the readiness method before sending work:

```ts
const machine = await Machine.connect("mach-...", { target: "cloud" });
await machine.waitUntilReady();
```

```python
machine = Machine.connect("mach-...", ConnectOptions(target="cloud"))
machine.wait_until_ready()
```

Use `ready()` for the current readiness signal and `readyAt()` / `ready_at()` for the first ready timestamp.

## Reach a service in the machine

Declare a port when creating the machine. The cloud control plane allocates the external host port.

```ts
const machine = await Machine.create(
  {
    image: "node:22-alpine",
    ports: [{ host: 8080, guest: 8080 }],
  },
  { target: "cloud" },
);

const response = await machine.fetch(8080, "/healthz");
console.log(await response.text());
```

```python
from smol import PortSpec

config = MachineConfig(
    image="python:3.12-alpine",
    ports=[PortSpec(host=8080, guest=8080)],
)
machine = Machine.create(config, ConnectOptions(target="cloud"))
body = machine.request(8080, "/healthz")
```

`endpoint()` returns an authenticated HTTP URL, WebSocket URL, and request headers for clients that need direct control. `url()` returns the public ingress URL for the first published port when one is available.

## Cloud-specific configuration

Cloud `MachineConfig` supports:

- `image`: required base OCI image
- `autoStopSeconds` / `auto_stop_seconds`: stop after an idle period
- `ttlSeconds` / `ttl_seconds`: delete after a fixed period
- `forkable`: prepare a machine as a live fork base
- `env`: machine workload environment variables
- `workdir`: machine workload working directory

Restricted egress belongs under `resources`, not at the top level:

```ts
const config = {
  image: "python:3.12-alpine",
  resources: {
    allowHosts: ["api.example.com"],
    allowCidrs: ["10.0.0.0/8"],
  },
};
```

```python
config = MachineConfig(
    image="python:3.12-alpine",
    resources=ResourceSpec(
        allow_hosts=["api.example.com"],
        allow_cidrs=["10.0.0.0/8"],
    ),
)
```

`MountSpec` maps host directories into local machines. Cloud persistent volumes use the Cloud API.

`run()`, `pullImage()` / `pull_image()`, and `listImages()` / `list_images()` are local-only. Create a cloud machine from an image and use `exec()` instead.

For concurrent Python applications, use `AsyncMachine`. The default `Machine` API remains synchronous.

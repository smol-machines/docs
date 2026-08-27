---
title: Machine API
---

# Machine API

`Machine` controls a microVM through either the embedded local engine or smol cloud. This page covers the public SDK class in the current `smolmachines` release. It is not the in-guest agent API or the standalone Cloud REST API.

TypeScript methods are asynchronous. Python's default `Machine` is synchronous; use `AsyncMachine` when one event loop needs to drive many machines concurrently.

## Create and connect

### `Machine.create`

Creates, starts, and returns a machine.

```ts
const machine = await Machine.create(config?, connection?);
```

```python
machine = Machine.create(config=None, conn=None)
```

Cloud creation requires `MachineConfig.image` and waits for readiness before returning. Set the target explicitly when the process may contain cloud credentials.

### `Machine.connect`

Attaches to an existing machine without creating one.

```ts
const machine = await Machine.connect(id, connection?);
```

```python
machine = Machine.connect(machine_id, conn=None)
```

For local, pass the name of a persisted machine. For cloud, pass the `mach-...` machine ID. `connect()` does not wait for readiness; call `waitUntilReady()` or `wait_until_ready()` before use.

## Identity, state, and readiness

| TypeScript | Python | Result |
|---|---|---|
| `machine.name` | `machine.name` | Machine name or identifier |
| `await machine.state()` | `machine.state()` | `"created"`, `"started"`, `"running"`, or `"stopped"` |
| `await machine.ready()` | `machine.ready()` | Whether the machine can accept work |
| `await machine.readyAt()` | `machine.ready_at()` | RFC 3339 ready timestamp, or null |
| `await machine.waitUntilReady(options?)` | `machine.wait_until_ready(timeout_s=120, interval_s=1)` | Wait until ready or raise |

State and readiness are separate. On cloud, `"started"` means only that the VM process launched. `ready: true` means the guest agent is reachable and every published port is accepting connections. `create()` waits for readiness; `connect()` does not. Check the application's own health endpoint separately when accepting a connection is not enough to establish application health.

TypeScript readiness options:

```ts
await machine.waitUntilReady({
  timeoutMs: 120_000,
  intervalMs: 1_000,
});
```

## Execute commands

Commands are argv arrays, not shell strings.

### `exec`

Executes a command directly in the machine. Supported on local and cloud.

```ts
const result = await machine.exec(["sh", "-lc", "echo $MODE"], {
  env: { MODE: "test" },
  workdir: "/workspace",
  timeout: 60,
});
```

```python
from smol import ExecOptions

result = machine.exec(
    ["sh", "-lc", "echo $MODE"],
    ExecOptions(
        env={"MODE": "test"},
        workdir="/workspace",
        timeout=60,
    ),
)
```

### `run`

Pulls an OCI image if needed and runs a command in it. Local only.

```ts
const result = await machine.run(
  "python:3.12-alpine",
  ["python", "-c", "print(40 + 2)"],
);
```

```python
result = machine.run(
    "python:3.12-alpine",
    ["python", "-c", "print(40 + 2)"],
)
```

For cloud, set `MachineConfig.image` during creation and use `exec()`.

### Stream output

`execStream()` / `exec_stream()` yields stdout, stderr, exit, and error events as they arrive. It is supported on the local target. For cloud command streaming, use the Cloud REST API's Server-Sent Events response.

```ts
for await (const event of machine.execStream(["sh", "-lc", "make test"])) {
  if (event.kind === "stdout" || event.kind === "stderr") {
    process.stdout.write(event.data);
  }
}
```

```python
for event in machine.exec_stream(["sh", "-lc", "make test"]):
    if event["kind"] in ("stdout", "stderr"):
        print(event["data"], end="")
```

### `ExecResult`

| TypeScript | Python | Meaning |
|---|---|---|
| `exitCode` | `exit_code` | Process exit code |
| `stdout`, `stderr` | `stdout`, `stderr` | UTF-8 text output |
| `stdoutBytes`, `stderrBytes` | `stdout_bytes`, `stderr_bytes` | Byte output |
| `stdoutTruncated`, `stderrTruncated` | `stdout_truncated`, `stderr_truncated` | Whether cloud text output hit its limit |
| `success` | `success` | Exit code is zero |
| `output` | `output` | Combined text output |
| `assertSuccess()` | `assert_success()` | Raise `ExecutionError` on a nonzero exit |

Cloud responses can truncate captured text output. Check the truncation fields and use streaming execution or a file for large output.

## Read and write files

Supported on local and cloud:

```ts
await machine.writeFile("/workspace/config.json", '{"enabled":true}');
const data = await machine.readFile("/workspace/config.json");
```

```python
machine.write_file("/workspace/config.json", '{"enabled": true}')
data = machine.read_file("/workspace/config.json")
```

`writeFile()` / `write_file()` accepts an optional numeric file mode.

Write to a path on the machine filesystem, such as `/workspace`, when the file must outlive the current run. `/tmp` is memory-backed: it holds its contents while the machine runs, and is empty again after a stop and start.

## Images

Local only:

| TypeScript | Python | Result |
|---|---|---|
| `await machine.pullImage(image)` | `machine.pull_image(image)` | Pulled `ImageInfo` |
| `await machine.listImages()` | `machine.list_images()` | Cached `ImageInfo` objects |

`ImageInfo` contains `reference`, `digest`, `size`, `architecture`, and `os`.

## Ports and ingress

### `url`

`url()` returns the public ingress URL for the first published cloud port. It returns `null` / `None` for local machines, machines without a published port, or cloud machines whose host port is not allocated.

### `endpoint`

Cloud only. Builds authenticated HTTP and WebSocket connection details for a published guest port without making a request:

```ts
const { httpUrl, wsUrl, headers } = machine.endpoint(8080, "/healthz");
```

```python
endpoint = machine.endpoint(8080, "/healthz")
print(endpoint.http_url, endpoint.ws_url, endpoint.headers)
```

### HTTP convenience methods

```ts
const response = await machine.fetch(8080, "/healthz");
```

```python
body = machine.request(
    8080,
    "/healthz",
    method="GET",
    data=None,
    timeout_s=30,
)
```

The port must be declared in `MachineConfig.ports`, and the service must listen on the guest port.

## Lifecycle

| TypeScript | Python | Behavior |
|---|---|---|
| `await machine.stop()` | `machine.stop()` | Stops the machine without deleting storage |
| `await machine.delete()` | `machine.delete()` | Stops the machine and permanently deletes its storage |

Use `try` / `finally` in TypeScript:

```ts
const machine = await Machine.create(undefined, { target: "local" });
try {
  await machine.exec(["echo", "work"]);
} finally {
  await machine.delete();
}
```

Python `Machine` is a context manager:

```python
from smol import ConnectOptions

with Machine.create(conn=ConnectOptions(target="local")) as machine:
    machine.exec(["echo", "work"])
```

## Forking

The SDK exposes `fork()` for cloud machines. Create the source machine with `forkable: true`, then clone its live state:

```ts
const clone = await golden.fork("clone-1");
```

```python
clone = golden.fork("clone-1")
```

Pass optional port mappings when a clone needs pinned host ports:

```ts
const clone = await golden.fork("clone-1", [{ host: 18080, guest: 8080 }]);
```

```python
from smol import PortSpec

clone = golden.fork(
    "clone-1",
    ports=[PortSpec(host=18080, guest=8080)],
)
```

When ports are omitted, the control plane allocates fresh host ports so concurrent clones do not collide.

Cloud forks are node-local and require a forkable source machine. They do not provide portable snapshots or live migration between local and cloud. For local forks, use the `smolvm` CLI.

## Configuration types

### `ConnectOptions`

| TypeScript | Python | Description |
|---|---|---|
| `target` | `target` | `"local"` or `"cloud"`; select explicitly when both are configured |
| `baseUrl` | `base_url` | Cloud API base URL |
| `apiKey` | `api_key` | Cloud API key |

Cloud authentication also reads `SMOL_CLOUD_TOKEN`. The base URL override is `SMOL_CLOUD_URL`.

### `MachineConfig`

| TypeScript | Python | Target | Description |
|---|---|---|---|
| `name` | `name` | Both | Name; generated when omitted |
| `image` | `image` | Both | Required for cloud; optional for local |
| `mounts` | `mounts` | Local | Host-directory mounts |
| `ports` | `ports` | Both | Host-to-guest or published port mappings |
| `resources` | `resources` | Both | CPU, memory, disk, network, and local GPU settings |
| `persistent` | `persistent` | Local | Keep the local machine record |
| `autoStopSeconds` | `auto_stop_seconds` | Cloud | Stop after an idle period |
| `ttlSeconds` | `ttl_seconds` | Cloud | Delete after a fixed period |
| `forkable` | `forkable` | Cloud | Prepare as a live fork base |
| `env` | `env` | Cloud | Workload environment at creation |
| `workdir` | `workdir` | Cloud | Workload working directory at creation |

### `ResourceSpec`

| TypeScript | Python | Target | Description |
|---|---|---|---|
| `cpus` | `cpus` | Both | vCPU count; omitted values use the target's default |
| `memoryMb` | `memory_mb` | Both | Memory in MiB; omitted values use the target's default |
| `network` | `network` | Both | Guest outbound networking. Local default `false`. On cloud it only turns access **on**: omitting it and setting `false` both leave the control-plane default, which is open — restrict a cloud machine with `allowHosts` / `allowCidrs` instead |
| `storageGb` | `storage_gb` | Both | Storage disk size in GiB; local SDK default `20` |
| `overlayGb` | `overlay_gb` | Local | Overlay disk size in GiB; local SDK default `10` |
| `allowHosts` | `allow_hosts` | Cloud | Enable networking restricted to these hostnames and subdomains |
| `allowCidrs` | `allow_cidrs` | Cloud | Enable networking restricted to these IP ranges |
| `gpu` | `gpu` | Local Vulkan | Enable virtio-gpu/Venus; default `false` |
| `gpuVramMib` | `gpu_vram_mib` | Local Vulkan | VRAM allocation; omitted values use the engine default |
| `cuda` | `cuda` | Local CUDA remoting | Enable CUDA API remoting; default `false` |

### `MountSpec`

Local host-directory mount:

```ts
{
  source: "/absolute/host/path",
  target: "/workspace",
  readOnly: false,
}
```

```python
MountSpec(
    source="/absolute/host/path",
    target="/workspace",
    read_only=False,
)
```

Set `readOnly` / `read_only` explicitly for every mount. Use read-only mounts for source code and writable mounts only for directories the guest must change.

### `PortSpec`

```ts
{ host: 8080, guest: 8080 }
```

```python
PortSpec(host=8080, guest=8080)
```

## Python `AsyncMachine`

Use `AsyncMachine` when synchronous calls would block an event loop:

```python
import asyncio
from smol import AsyncMachine, ConnectOptions, MachineConfig

async def main():
    async with await AsyncMachine.create(
        MachineConfig(image="alpine:3.20"),
        ConnectOptions(target="cloud"),
    ) as machine:
        result = await machine.exec(["echo", "hello"])
        print(result.stdout)

asyncio.run(main())
```

It mirrors the synchronous API with awaitable I/O methods. `endpoint()` remains synchronous because it only builds connection data.

## Errors

SDK errors derive from `SmolError` and include a machine-readable `code`. For handling patterns and exit-code semantics, see the [Error handling guide](/docs/guides/error-handling).

- `ExecutionError`: a command assertion failed
- `NotSupportedError`: the selected target does not support the operation
- `InvalidConfigError`: the configuration is invalid

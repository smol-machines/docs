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

For local, pass the name of a persisted machine, a paused one included. For cloud, pass the `mach-...` machine ID. `connect()` does not wait for readiness; call `waitUntilReady()` or `wait_until_ready()` before use.

`Machine.probe(connection?)` (`Machine.probe(conn)` in Python) checks a cloud connection before any machine exists: it throws unless the key is accepted and the base URL answers with a machine list.

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

On cloud, `background: true` (`ExecOptions(background=True)`) starts the command detached and returns at once with its `pid`, leaving it running after the call ends.

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

`execStream()` / `exec_stream()` yields stdout, stderr, exit, and error events as they arrive. It is supported on the local target and on cloud machines. A client that is not using an SDK can read the Cloud REST API's Server-Sent Events response directly.

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

### Jobs

Cloud only. `startJob(command, options?)` (`start_job` in Python) runs a command detached and returns a `Job` at once; its output and exit code stay in the machine, so the caller can disconnect and come back. Unlike `exec`, a job survives a dropped connection, so prefer it for anything that runs longer than a few minutes. The machine does not auto-stop while a job runs.

```ts
const job = await machine.startJob(["sh", "-c", "make test"], { timeout: 3600 });
const done = await job.wait();
const stdout = await job.readAll("stdout");
```

```python
job = machine.start_job(["sh", "-c", "make test"], timeout=3600)
done = job.wait()
stdout = job.read_all("stdout")
```

The options are `env`, `workdir`, `user` and `timeout` in seconds, after which the job is stopped with `SIGTERM`. `wait()` returns the final state: `exited` with its `exitCode`, or `lost` when the machine stopped or restarted while the job ran. `output()` reads a slice of stdout or stderr from an offset, `cancel()` sends `SIGTERM` and records exit code `143`, and `machine.jobs()` lists the machine's jobs, newest first. A string command runs through `sh -c`, so the image needs `sh`. The routes behind these are in the [API reference](/docs/cloud/api-reference#commands-and-sessions).

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

### Publish a port on a running machine

`publish({ guest })` (`publish(guest)` in Python) publishes a guest port without a restart and returns the mapping in effect; without `host`, a free host port is picked. `unpublish({ guest })` stops publishing it, and connections already open carry on. `ports()` lists what is published. A running local machine takes a TCP port at once; a UDP port, or a machine not on virtio-net networking, needs it stopped. On cloud the node picks the host port and ports are TCP.

### Port links

Cloud only. `portLinks()` (`port_links()`) returns a login-free URL for each published port, keyed by guest port, for a client that cannot send an API key. Anyone holding a link reaches the port, so treat it as a credential. `revokePortLinks()` (`revoke_port_links()`) revokes them all, and the next call issues new ones.

## Lifecycle

| TypeScript | Python | Behavior |
|---|---|---|
| `await machine.stop()` | `machine.stop()` | Stops the machine without deleting storage |
| `await machine.start(options?)` | `machine.start()` | Boots a stopped machine from its disk, not its previous RAM |
| `await machine.pause()` | `machine.pause()` | Saves RAM and disk durably, then stops at that point |
| `await machine.resume(options?)` | `machine.resume()` | Resumes the saved execution |
| `await machine.delete()` | `machine.delete()` | Stops the machine and permanently deletes its storage |

`start()` and `resume()` wait for readiness; pass `{ waitUntilReady: false }`, or `wait_until_ready=False` in Python, to return as soon as the request is accepted.

Three more are cloud only: `info()` returns the machine's full cloud record, `logs(tail)` the last lines of its console log (100 by default), and `exportArtifact()` (`export_artifact()`) exports the stopped machine as a `.smolmachine` in your registry namespace. `Machine.deleteCheckpoint(id)` (`Machine.delete_checkpoint(id)`) deletes a durable cloud checkpoint, or a local checkpoint file by path; a cloud checkpoint a machine was restored from, or that holds a paused machine's saved execution, is refused until that machine is gone.

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

## Branching

The SDK exposes `branch()` on both targets. Create the source machine as branchable, `branchable: true` in TypeScript and
`branchable=True` in Python, then clone its live state:

```ts
const clone = await source.branch("clone-1");
```

```python
clone = source.branch("clone-1")
```

Pass optional port mappings when a clone needs pinned host ports:

```ts
const clone = await source.branch("clone-1", [{ host: 18080, guest: 8080 }]);
```

```python
from smol import PortSpec

clone = source.branch(
    "clone-1",
    ports=[PortSpec(host=18080, guest=8080)],
)
```

When ports are omitted, the control plane allocates fresh host ports so concurrent clones do not collide.

Cloud branches are node-local and require a branchable source machine. They do not provide portable checkpoints or live migration between local and cloud.

Local branching runs through the embedded engine, so it needs no CLI: a local source created
`branchable` branches with the same call, and the child reads what the source wrote. `resize()`
grows a local machine in place, and `branchBatch()` / `branch_batch()` makes several children at
once. `checkpoint()` is exposed on both targets, but for a checkpoint of a local machine use the
`smolvm` CLI: through the embedded engine it currently fails with
`read CPU features: No such file or directory`.

`Machine.list()` returns the machines on a target, each with its name, state and labels. Labels are
set at create time and come back on the summary, which is how a caller finds its own machines
again:

```ts
const all = await Machine.list({ target: "local" });
```

A machine created with `detach` keeps running after the process that made it exits, and
`restoreCheckpoint()` takes a `keepIdentity` flag with the same meaning as the CLI's
`--keep-identity`.

## Configuration types

### `ConnectOptions`

| TypeScript | Python | Description |
|---|---|---|
| `target` | `target` | `"local"` or `"cloud"`; select explicitly when both are configured |
| `baseUrl` | `base_url` | Cloud API base URL |
| `apiKey` | `api_key` | Cloud API key |
| `fetch` | | TypeScript only: the `fetch` cloud requests go through, for a proxy, retries or tracing; the global `fetch` by default |

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
| `branchable` | `branchable` | Both | Prepare as a live branch source |
| `env` | `env` | Cloud | Workload environment at creation |
| `workdir` | `workdir` | Cloud | Workload working directory at creation |

### `ResourceSpec`

| TypeScript | Python | Target | Description |
|---|---|---|---|
| `cpus` | `cpus` | Both | vCPU count; omitted values use the target's default |
| `memoryMb` | `memory_mb` | Both | Memory in MiB; omitted values use the target's default |
| `network` | `network` | Both | Unrestricted guest outbound networking. Local default `false`. On cloud it only turns access **on**: omitting it and setting `false` both leave the control-plane default, which is open. To allow only specific destinations, set `allowHosts` / `allowCidrs` instead of this flag |
| `storageGb` | `storage_gb` | Both | Storage disk size in GiB; local SDK default `20` |
| `overlayGb` | `overlay_gb` | Local | Overlay disk size in GiB; local SDK default `10` |
| `allowHosts` | `allow_hosts` | Both | Enable networking restricted to these hostnames and their subdomains. The gateway intercepts the machine's DNS and allows the addresses it answers with, so a host served from another domain (a CDN) needs its own entry |
| `allowCidrs` | `allow_cidrs` | Both | Enable networking restricted to these IP ranges |
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

::: warning Host mounts are local only
`MountSpec` binds a path on your own machine, so it applies to the local and
self-hosted targets. Smol cloud has no host filesystem to bind from, so a cloud
machine keeps its data on its own filesystem. See
[Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking).
:::

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

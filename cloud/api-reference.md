---
title: Cloud API Reference
---

# Cloud API Reference

The Cloud API is the hosted REST interface for smol cloud.

- Base URL: `https://api.smolmachines.com`
- Generated OpenAPI: [smolmachines.com/openapi.json](/openapi.json)
- Interactive client: [API Explorer](/docs/cloud/api-explorer)

Use the generated OpenAPI document for the routes and schemas it includes. It is generated from the service, so it still lists volume routes; those are not a supported part of the API and a machine created with a `mounts` field comes up without the storage. Specialized operations and newly added fields can land ahead of the website's generated snapshot, so use this page and the linked lifecycle guides for behavior that the schema does not yet describe.

## Authentication

Create an API key in the [console](/console/keys) and send it as a bearer token:

```http
Authorization: Bearer smk_your_key_here
```

For shell examples:

```bash
export SMOL_CLOUD_TOKEN="smk_your_key_here"
export SMOL_CLOUD_URL="https://api.smolmachines.com"
```

Keep API keys on trusted servers. Use separate keys for development, CI, and production, and revoke keys that are no longer needed.

## Core resources

### Machines

Machines are persistent cloud microVMs. The core lifecycle is:

```text
POST   /v1/machines
GET    /v1/machines
GET    /v1/machines/{id}
POST   /v1/machines/{id}/start
POST   /v1/machines/{id}/stop
DELETE /v1/machines/{id}
```

Machine creation accepts an OCI image or a `.smolmachine` registry reference as its source. Specify CPU, memory, network policy, environment, working directory, lifecycle limits, and other supported fields in the create request.

When `resources` is omitted, a machine currently defaults to 4 vCPUs and 8192 MB of memory. When `network` is omitted, outbound access defaults to **open** — set `network.mode` explicitly (`blocked` or `allowCidrs`) when egress policy matters. Note a `blocked` machine also cannot pull its image, which runs in-guest, unless the image is already cached on its node. Larger machines cost more, so pass `resources` explicitly (for example `{"cpus": 1, "memoryMb": 256}`) rather than relying on the default. Disks can be configured up to 16 TiB where capacity is available. Check the OpenAPI document for the current request limits.

### Commands and sessions

Run a command with:

```text
POST /v1/machines/{id}/exec
```

`command` accepts a shell string or an argv array. Requests can also include `cwd`, `env`, `stdin`, `timeoutSeconds`, `stream`, and `background` for detached execution. Verify the generated schema for the deployment you target before relying on optional fields.

The response carries each output stream twice: as UTF-8 text (`stdout`/`stderr`, capped at 1 MiB) and as byte-exact base64 (`stdoutB64`/`stderrB64`). Pass `?output=text` or `?output=b64` to receive only one family and halve the response size; the default returns both.

Sessions preserve a working directory and environment across related exec calls:

```text
GET    /v1/machines/{id}/sessions
POST   /v1/machines/{id}/sessions
POST   /v1/machines/{id}/sessions/{sessionId}/exec
DELETE /v1/machines/{id}/sessions/{sessionId}
```

### Interactive terminal

The console's terminal is a WebSocket you can open yourself, to give your own product a real shell in a machine: full-screen programs, colors, prompts, and resizing all work.

```text
GET /v1/machines/{id}/exec/interactive   (WebSocket upgrade)
```

| Query parameter | Meaning |
|---|---|
| `cmd` | Program to run, as a single path with no arguments. Defaults to `/bin/sh`. `command` is accepted too. |
| `cols`, `rows` | Initial terminal size. |
| `access_token` | Your API key, for clients that cannot set an `Authorization` header on a WebSocket, such as browsers. Servers should send the bearer header instead. |

The key needs the `machine:exec` scope. A stopped machine is started before the terminal opens.

Once connected, frames mean:

| Direction | Frame | Meaning |
|---|---|---|
| you → machine | binary | Keystrokes, as raw bytes |
| you → machine | text `{"type":"resize","cols":120,"rows":40}` | The terminal was resized |
| you → machine | text `{"type":"stdin","data":"ls\n"}` | Text input; any other text frame is also typed as input |
| machine → you | binary | Terminal output, including ANSI escape codes |
| machine → you | text `{"type":"exit","code":0}` | The program exited; the socket closes next |

This maps directly onto [xterm.js](https://xtermjs.org/):

```js
import { Terminal } from '@xterm/xterm';

const term = new Terminal();
term.open(document.getElementById('terminal'));

const url = new URL(`wss://api.smolmachines.com/v1/machines/${machineId}/exec/interactive`);
url.search = new URLSearchParams({
  cmd: '/bin/bash',
  cols: String(term.cols),
  rows: String(term.rows),
  access_token: apiKey,
}).toString();

const ws = new WebSocket(url);
ws.binaryType = 'arraybuffer';
const encoder = new TextEncoder();

ws.onmessage = (event) => {
  if (typeof event.data === 'string') {
    const msg = JSON.parse(event.data);
    if (msg.type === 'exit') term.write(`\r\n[exited with ${msg.code}]\r\n`);
  } else {
    term.write(new Uint8Array(event.data));
  }
};
term.onData((data) => ws.send(encoder.encode(data)));
term.onResize(({ cols, rows }) => ws.send(JSON.stringify({ type: 'resize', cols, rows })));
```

From a server, the same session with Node's `ws` package:

```js
import WebSocket from 'ws';

const ws = new WebSocket(
  `wss://api.smolmachines.com/v1/machines/${machineId}/exec/interactive?cmd=/bin/sh&cols=120&rows=40`,
  { headers: { Authorization: `Bearer ${process.env.SMOL_CLOUD_TOKEN}` } },
);
ws.on('open', () => ws.send(Buffer.from('uname -a\n')));
ws.on('message', (data, isBinary) => {
  if (isBinary) process.stdout.write(data);
  else if (JSON.parse(data.toString()).type === 'exit') ws.close();
});
```

Behavior to plan for:

- **Closing the socket ends the program.** Nothing keeps running once you disconnect. For a session you can come back to, set `cmd` to a script that runs `exec tmux new -A -s main` (with `tmux` installed in the machine) and reconnect to the same session.
- **A connection lasts at most one hour.** Reconnect before then; with `tmux`, reconnecting lands you back where you were.
- **Quiet sessions are kept alive.** The server pings every 30 seconds, which WebSocket clients answer automatically. A client that stops answering for 90 seconds is treated as gone and its session ends, so a machine is not kept awake by a connection nobody is using.
- **Several terminals can be open at once.** Each has its own session and does not block the others or `exec` calls.
- **Treat a key in a browser as visible.** Anyone who can read the page can read an `access_token`, and query strings can appear in proxy logs. Have your backend mint a key for that user with `"scopes": ["machine:exec"]` and `"expiresInDays": 1` through `POST /v1/apikeys`, and revoke it when the session ends.

For command output without a terminal, such as an agent running a build, `POST /v1/machines/{id}/exec` with `"stream": true` returns output as Server-Sent Events and is simpler to consume.

### Files

The API supports file upload and download for a machine. Use the current OpenAPI or API Explorer for the path shape and request encoding.

Upload targets follow the machine's filesystem layout. Write to `/workspace` or another path on the storage disk when the file must survive a stop and start; `/tmp` is memory-backed and is empty after the machine restarts. An upload whose target resolves through a symlink into a memory-backed path fails instead of writing the file. See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking).

### Operational endpoints

The Cloud API also provides endpoints for:

- Running Python or JavaScript through `/code`
- Machine events and logs
- Per-machine usage and cached images
- Sharing a machine through scoped share links
- Branching a branchable machine
- Exporting a machine to a `.smolmachine` artifact

Use the OpenAPI document or Explorer to inspect the exact routes, request bodies, and feature availability for your account.

### Usage and account

Use `/v1/usage` for usage over a time range and `GET /v1/machines/{id}/usage` for one machine's totals and cost. The API also exposes account and billing-meter endpoints where enabled. Plan limits and pricing can change; use the [pricing page](/pricing) for current public rates.

::: tip
`exec` calls are never charged. They are metered for the event timeline but
priced at $0, so they do not appear among the priced usage dimensions. They are
still subject to the per-tenant rate limit, so a burst can return `429`.
:::

Metering semantics to build billing on:

- Uptime, base, and disk accrue in near real time. CPU and memory accrue through a metering rollup that samples every few minutes, so a mid-life `/usage` read is a lower bound on the eventual cost — not the settled number.
- Stop and delete take a synchronous final metering sample, so usage is fully settled the moment a machine ends.
- `DELETE /v1/machines/{id}?includeUsage=true` returns `200` with the settled usage and cost in the response body — the recommended pattern for short-lived machines (create, run a job, delete, bill from the DELETE response). Without the flag, DELETE returns `204` as before.
- `GET /v1/machines/{id}/usage` keeps working for 30 days after a machine is deleted.

The [cloud-usage](/docs/guides/skills/cloud-usage) skill packet reads these totals and reconciles one machine's bill against its uptime and the published rate.

### API keys

The API supports listing, creating, and revoking keys:

```text
GET    /v1/apikeys
POST   /v1/apikeys
DELETE /v1/apikeys/{id}
```

The plaintext value of a newly created key is shown once.

## Readiness and lifecycle

Do not treat `state: "started"` as application readiness. Poll `GET /v1/machines/{id}` until `ready` is `true` before executing dependent work or connecting to a published service. `ready` flips once the machine answers a probe — its published port accepts connections, or, for machines with no published port, its guest agent responds — normally within a few seconds of start; `readyAt` records when. Exec does not require readiness: it auto-starts a stopped machine and waits for the agent itself.

Starting a machine blocks until the boot completes, which normally takes a few seconds. Pass `?detach=true` to return `202 Accepted` immediately and boot in the background, then poll `GET /v1/machines/{id}` until the state is `started` or `error`. Under a burst this keeps a client's own request timeout from cancelling a start that is still queued. `exec` has the same option under a different name: `background` in the request body.

Stopping a machine preserves its stored state. Deleting it removes the machine. See the lifecycle page for billing and storage details.

## Plan limits

Three ceilings apply to every tenant, and all three come from the plan the
account is on rather than from the platform:

- **How many machines you may hold** — counted across every state, not just
  running ones, so a stopped machine still occupies a slot until it is deleted.
- **How many may run at once** — counted over `started` and `creating`.
- **How large one machine may be** — vCPU, memory, and disk, applied per
  machine at create time.

Read your own ceilings rather than assuming them. `GET /v1/account` returns
`effectiveMaxMachines` alongside the plan it came from, and the plan object
carries `maxConcurrentMachines`, `maxCpus`, `maxMemoryMb`, and `maxDiskGb`:

```bash
curl -fsSL https://api.smolmachines.com/v1/account \
  -H "Authorization: Bearer $SMOL_API_KEY"
```

The published plans and their ceilings are listed on the
[pricing page](/pricing). Limits differ between plans; the per-unit rates do
not, so moving up a plan buys headroom rather than a different price.

Exceeding a ceiling is refused at create time with `422` and a body naming the
plan, the limit, and where to change it — nothing is started, so nothing is
charged:

```
machine count quota exceeded: your Standard plan allows 20 machines; upgrade at https://smolmachines.com/pricing
concurrency limit reached: your Standard plan allows 20 machines running at once; upgrade at https://smolmachines.com/pricing
```

::: tip
A count refusal usually means machines were left behind rather than that the
ceiling is genuinely too low. Ephemeral work should delete its machine when it
finishes, and `autoStopSeconds` stops an idle machine but does not delete it —
a stopped machine still holds its slot.
:::

## Errors and request IDs

Use the HTTP status code first. Error bodies may be plain text. For guest exit codes and SDK error patterns, see [Error handling](/docs/guides/error-handling).

Common statuses include:

- `400`: invalid request
- `401`: missing or invalid credentials
- `403`: insufficient scope
- `404`: resource not found or not owned by the caller
- `409`: conflicting resource
- `402`: billing or budget restriction
- `422`: quota, capacity, or validation constraint
- `429`: rate limit exceeded
- `500`: server error
- `503`: service or feature unavailable

Every response includes `x-request-id`. A safe client-provided ID is echoed; otherwise the service generates one. Record it with the status and response body when reporting a failed request.

## Branches and snapshots

Branch routes are specialized cloud operations. They do not move a running local VM into cloud or provide a portable cross-architecture restore format. Machine snapshots are not implemented in the cloud API: the snapshot routes return `501`. To capture a stopped machine's disk state, export it to a `.smolmachine` artifact instead (`POST /v1/machines/{id}/export`, or `smol cloud export`).

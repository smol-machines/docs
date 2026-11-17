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
POST   /v1/machines/{id}/pause
POST   /v1/machines/{id}/resume
DELETE /v1/machines/{id}
```

`pause` saves the machine's memory and disks durably, then stops it; `resume` starts it again from that point, under the same id. Both need `machine:create`, and each answers `409` when the machine is in no state to do it: not pausable, or no saved execution ready.

Machine creation accepts an OCI image or a `.smolmachine` registry reference as its source. Specify CPU, memory, network policy, environment, working directory, lifecycle limits, and other supported fields in the create request.

When `resources` is omitted, a machine currently defaults to 4 vCPUs and 8192 MB of memory. When `network` is omitted, outbound access defaults to **open**, so set `network.mode` explicitly (`blocked` or `allowCidrs`) when egress policy matters. Note a `blocked` machine also cannot pull its image, which runs in-guest, unless the image is already cached on its node. Larger machines cost more, so pass `resources` explicitly (for example `{"cpus": 1, "memoryMb": 256}`) rather than relying on the default. Disk per machine is capped by the plan, which `effectiveMaxDiskGb` shows; 16 TiB is the most any request can ask for. Check the OpenAPI document for the current request limits.

`resources.diskDurability` is `full` (the default), where a guest `fsync` waits for the node's disk, or `deferred`, which is faster for fsync-heavy work and can lose recent writes if the node crashes; a branch keeps its source's.

Machine and session responses list `env` with every value replaced by `[REDACTED]`. Values reach the machine but are never read back, so do not copy a response's `env` into a new create.

`nestedVirt: true` exposes the host's virtualization extensions so the guest can run its own hypervisor. It is included with the Startup and Enterprise plans; on any other plan the create is refused with `422` `nested_virt_unavailable`, naming the plan. It is also refused with the same code when no node offers it.

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

A job runs a command detached and keeps its stdout, stderr and exit code in the machine, so a client
can disconnect and come back for them:

```text
POST /v1/machines/{id}/jobs
GET  /v1/machines/{id}/jobs
GET  /v1/machines/{id}/jobs/{job_id}
GET  /v1/machines/{id}/jobs/{job_id}/output
POST /v1/machines/{id}/jobs/{job_id}/cancel
```

`POST` takes `command`, with optional `cwd`, `env`, `user` and `timeoutSeconds`, and returns `202`
at once; it wakes a stopped machine, and a running job keeps the machine from auto-stopping. A job's
`state` is `running`, `exited` with its `exitCode`, or `lost` when the machine stopped or restarted
while it ran. Read output with `?stream=stdout` or `stderr` from an `offset`, asking again from
`nextOffset` until `eof`. Cancel sends `SIGTERM`, and a cancelled or timed-out job records exit
code `143`. The image needs `sh`.

Both reads take `?wait=<seconds>` to long-poll instead of polling: a job read holds until the job
stops running, and an output read until there is output past `offset` or the job ends, for at most
30 seconds (a larger value is treated as 30). Past 4 waits at once per machine, 64 per account or 128
per node, a read can answer a retryable `429`.

A resumable exec is owned by the machine's node rather than by the connection that started it, so a dropped connection or a control plane restart does not end it. It suits long commands an agent runs and reads back:

```text
POST   /v1/machines/{id}/execs
GET    /v1/machines/{id}/execs
GET    /v1/machines/{id}/execs/{execId}?after=<next>&wait=<seconds>
POST   /v1/machines/{id}/execs/{execId}/stdin
POST   /v1/machines/{id}/execs/{execId}/resize
GET    /v1/machines/{id}/execs/{execId}/attach   (WebSocket upgrade)
DELETE /v1/machines/{id}/execs/{execId}
```

`POST` takes `command` and optionally `execId`, `cwd`, `env`, `user`, `stdin`, `timeoutSeconds` (600 by default, none for an `interactive` or `tty` exec), `interactive`, `tty` and `waitSeconds`. Choose `execId` (8 to 64 of `A-Z`, `a-z`, `0-9`, `_` and `-`) before the first try: a retry with the same id answers `200` with the exec the first try started, never running the command twice. With `waitSeconds`, at most 25, the answer carries the first output, so a short command takes one request. Read the rest with `?after=` set to the last answer's `next` until `done`, which carries `exitCode`, then `DELETE` it. A read answering `503` means the control plane is restarting: read again. A machine whose node has no resumable execs answers `501`; use `exec`. They need the `machine:exec` scope.

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
- **Treat a key in a browser as visible.** Anyone who can read the page can read an `access_token`, and query strings can appear in proxy logs. Give the page a key of its own, created in the console with only the `machine:exec` scope and a short expiry, and revoke it when the session ends.

For command output without a terminal, such as an agent running a build, `POST /v1/machines/{id}/exec` with `"stream": true` returns output as Server-Sent Events and is simpler to consume.

### Files

`PUT /v1/machines/{id}/files/{path}` uploads the request body as a file, and `GET` on the same path downloads one. `{path}` is the absolute guest path without its leading slash, so `/workspace/data.csv` is `files/workspace/data.csv`. Both need the `machine:files` scope:

```bash
curl --fail-with-body -X PUT --data-binary @data.csv \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/files/workspace/data.csv?mode=0644" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
curl --fail -o data.csv "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/files/workspace/data.csv" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

An upload answers `204` and creates the parent directories. Any path in the machine's filesystem can be written, `/etc` included; the file gets mode `0644` and belongs to the user the image's workload runs as, unless `mode`, `uid` or `gid` in the query say otherwise. `/proc`, `/sys` and `/dev` are refused with `422`, and so are `/etc/resolv.conf` and `/etc/smolvm-host-trust`, which the node manages.

Request bodies are capped: 1 MiB on the JSON API, 1 GiB on a file upload to `/v1/machines/{id}/files/...` that declares its `Content-Length` and 100 MiB on one that does not (100 MiB either way on a node whose engine is older than smolvm 1.31.0), and 10 MiB per request through the connect route. A larger body is refused.

Upload targets follow the machine's filesystem layout. Write to `/workspace` or another path on the storage disk when the file must survive a stop and start; `/tmp` is empty after the machine restarts. An upload whose target resolves through a symlink into a memory-backed path succeeds, and the file is gone after a restart. See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking).

### Operational endpoints

The Cloud API also provides endpoints for:

- Running Python or JavaScript through `/code`
- Machine events and logs
- Per-machine usage and cached images
- Sharing a machine through scoped share links
- Branching a branchable machine, `POST /v1/machines/{id}/branches`, below
- Exporting a machine to a `.smolmachine` artifact
- Resizing a machine's vCPUs, memory or disk, `POST /v1/machines/{id}/resize` with any of `cpus`, `memoryMb` and `diskGb`: in place on a started machine, and at the next start or resume on a stopped or paused one. Memory and disk only grow; any other state answers `409`
- Resetting the idle clock without running anything, `POST /v1/machines/{id}/keepalive`
- Changing labels in any state, `PATCH /v1/machines/{id}/labels`, and finding machines by them with `GET /v1/machines?label=key=value`
- Minting a short-lived token that opens only one machine's connect bridge, `POST /v1/machines/{id}/connect-token`
- Replacing a machine's published ports, live while it runs, `PUT /v1/machines/{id}/ports` with `{"ports": [{"port": 8080}]}`
- Replacing a machine's outbound network policy, `PUT /v1/machines/{id}/network` with the create's `network` object: live from one allow list to another on a started machine, otherwise at the next start
- Replacing a machine's credential bindings before its first start, `PUT /v1/machines/{id}/credentials`
- Opening a machine's published app to anyone without a login, and closing it again, `POST` and `DELETE /v1/machines/{id}/public`
- Getting or revoking login-free port links, one URL per published port, `POST` and `DELETE /v1/machines/{id}/port-links`
- Listing every checkpoint the account owns, `GET /v1/checkpoints`, and uploading a `.smolcheckpoint` file captured outside the cloud with `POST /v1/checkpoints` and then `POST /v1/checkpoints/{id}/complete`
- Rolling a machine back in place to its newest or a named checkpoint, keeping its id and name, `POST /v1/machines/{id}/rollback`

[Change a machine after create](/docs/cloud/lifecycle-storage-networking#change-a-machine-after-create) puts every setting that changes on an existing machine in one table, with what applies at once and what waits for a restart.

### Groups

A group runs one image as several identical machines behind one name and rolls new versions out across them:

```text
GET    /v1/groups
POST   /v1/groups
GET    /v1/groups/{name}
DELETE /v1/groups/{name}
POST   /v1/groups/{name}/scale
POST   /v1/groups/{name}/redeploy
POST   /v1/groups/{name}/promote
GET    /v1/groups/{name}/logs
```

`POST /v1/groups` deploys `image` under `name`, or rolls out a new deployment when the name exists:

```json
{
  "name": "web",
  "image": "nginx",
  "port": 80,
  "cpus": 1,
  "memoryMb": 512,
  "health": {"type": "http", "path": "/", "port": 80},
  "strategy": {"type": "rolling", "batchSize": 1, "useHealthCheck": true}
}
```

`port` is 8080, `cpus` 1 and `memoryMb` 512 when left out. The body also takes `env` as a list of `{"key", "value"}` pairs, `network` (a boolean), `domain`, `coLocateWith`, `stopGraceSecs` (10 by default) and `publicIngress`, which opens the group's port without a login and is `false` by default. `health` checks each instance by `http`, `tcp` or `exec`, every `intervalSecs` (10) with `timeoutSecs` (2) and `retries` (3). `strategy` is one of:

- `rolling`, the default: replaces `batchSize` instances at a time (1), waiting `waitSeconds` (5) between batches, or for the health check with `useHealthCheck`.
- `canary`: starts `canaryCount` new instances first and replaces the rest once they are healthy. With `autoPromote` false, `POST .../promote` does that step.
- `blueGreen`: starts a complete new set, switches traffic to it at once, then removes the old one.

`scale` takes `{"count": N}`, `redeploy` pulls the image again and rolls the instances, `logs` returns, as plain text, the last 200 lines of `/var/log/messages` (or `dmesg`) from one running instance, and `DELETE` stops and removes every instance. Deploy, scale, redeploy, promote and delete need the `group:write` scope, which an API key can carry; the reads need only a valid key.

### Managed agents

A managed agent is a coding agent that smol cloud runs in a machine of its own. You send it turns, read what it did, and rewind or branch it to the state after any turn:

```text
GET    /v1/agents
POST   /v1/agents
GET    /v1/agents/{name}
DELETE /v1/agents/{name}
POST   /v1/agents/{name}/turns
GET    /v1/agents/{name}/turns/{turn}/events
POST   /v1/agents/{name}/turns/{turn}/cancel
POST   /v1/agents/{name}/rewind
POST   /v1/agents/{name}/branch
POST   /v1/agents/{name}/pause
POST   /v1/agents/{name}/resume
```

`POST /v1/agents` (`machine:create`) answers `202` and sets the machine and harness up in the background: `status` reads `starting`, then `ready` or `failed`. The body takes `name` and optionally:

| Field | Meaning |
|---|---|
| `harness` | `claude-code` (the default), `codex`, `opencode` or `command` |
| `model` | Optional for `codex`; required as `provider/model` for `opencode` |
| `image`, `program` | For the `command` harness: the image (`alpine:3.20` by default) and the program, which gets the prompt appended |
| `credential` | A stored credential holding the model API key, so the machine never holds it. Its variable must be the one the harness reads, such as `ANTHROPIC_API_KEY`, and its hosts must include the provider's |
| `allowHosts`, `openNetwork` | Hosts the agent may reach beyond its model provider and package registry, or `true` for unrestricted outbound access. The `command` harness needs one of them, or the create answers `422` |
| `checkpoints` | Checkpoint after every turn so the agent can be rewound or branched; `true` by default |
| `cpus`, `memoryMb`, `arch` | 2 vCPUs and 2048 MiB by default; an agent with checkpoints runs on `amd64` unless `arch` says otherwise |

`POST .../turns` (`machine:exec`) takes `prompt`, and optionally `env` for this turn's process and `timeoutSeconds`, 1800 by default; it answers `202` with the turn number, and the turn runs whether or not a client stays connected. An `Idempotency-Key` header makes a retry safe. Values in `env` reach the machine and any checkpoint taken during or after the turn, so pass a model key through `credential` instead. `GET .../turns/{turn}/events` streams the turn's events as server-sent events, then `done`; `?after=` replays only the events numbered above it. A second turn while one runs answers `409`.

`rewind` takes `{"turn": N}` and restores the agent to the state right after that turn; `branch` takes `{"turn": N, "name": "..."}` and starts a new agent from it (`fork` is the same route under its older name). `pause` checkpoints and stops the agent's machine, and the next turn or `resume` starts it again. `DELETE` removes the agent, its machine and the checkpoints no other agent shares. Reads need `machine:read`, `DELETE` needs `machine:delete`, `turns` needs `machine:exec`, `cancel` needs both `machine:create` and `machine:exec`, and the rest `machine:create`.

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

When the prepaid balance runs out, running work continues for 48 hours, with an email at the start and before the end. Then running machines are stopped, and requests that start or create work are refused with `402` (`payment_required`, detail "balance exhausted"). Reads, stop and delete still work. A plan with a monthly budget, or the egress budget, refuses the same way when reached. `PATCH /v1/account` from a signed-in session, with `lowBalanceThresholdMicros`, sets the low-balance email (`0` turns it off), and auto-recharge, set from [billing](/console/billing), charges the card on file a chosen amount when the balance falls to a threshold.

The [cloud-usage](/docs/guides/skills/cloud-usage) skill packet reads these totals and reconciles one machine's bill against its uptime and the published rate.

### Metrics export

smol cloud can push every running machine's metrics to an OpenTelemetry collector you name, as OTLP over HTTP with JSON encoding, every 30 seconds. `PUT /v1/account/telemetry` sets the destination:

```json
{"otlpEndpoint": "https://otlp.example.com", "headers": {"Authorization": "Bearer <collector token>"}}
```

Exports go to `<otlpEndpoint>/v1/metrics` with those headers, at most 16. Header values are stored sealed and never returned. The endpoint must be an `http://` or `https://` URL with no query, and one that names a loopback, link-local, private, carrier-grade NAT or cloud metadata address is refused with `400`.

Setting or removing the destination needs the `billing:write` scope, which no API key can carry, and the console has no control for it yet, so today only a signed-in session can set it. It is refused from inside a sub-organization, so a sub-organization has no export of its own, and its machines are not in its parent's export. `GET /v1/account/telemetry` (`machine:read` or `usage:read`) shows the endpoint, the header names, the interval, when the collector last accepted an export and, after a failure, why the last one failed; it answers `404` when no destination is set. `DELETE` stops the exports.

Each running machine is one OTLP resource with `service.name` `smol-machine`, `service.namespace` and `smol.account` set to the account, `service.instance.id`, and its id, name, node, the machine it was branched from and each of its labels as `smol.machine.label.<key>`. Its metrics, under the scope `smolmachines.cloud`, are CPU time and CPU limit, host memory (`smol.machine.memory.pss` and `.rss`), disk used and disk size, bytes sent out, open connections, and the guest's CPU, memory and IO pressure stalls. A reading a node does not report is left out rather than sent as zero, and an account with no running machine still gets an empty export each interval. Each node that hosts one of the account's machines is a resource of its own, `service.name` `smol-node`, carrying the host's CPU pressure as `smol.node.cpu.pressure`.

### API keys

Keys are listed, created and revoked through these routes:

```text
GET    /v1/apikeys
POST   /v1/apikeys
DELETE /v1/apikeys/{id}
```

Each needs the `members:write` scope, which a signed-in owner or admin holds and a newly created key
cannot carry: a key may hold only `machine:`, `volume:`, `usage:read` and `group:write` scopes. So
keys are managed from the [console](/console), and a call with an API key gets a `403` naming the
missing scope. The plaintext value of a newly created key is shown once.

Shared accounts, their members and invitations, and sub-organizations have routes under `/v1/org`, described on [Organizations](/docs/cloud/organizations).

## Readiness and lifecycle

Do not treat `state: "started"` as application readiness. Poll `GET /v1/machines/{id}` until `ready` is `true` before executing dependent work or connecting to a published service. `ready` flips once the machine answers a probe — its published port accepts connections, or, for machines with no published port, its guest agent responds — normally within a few seconds of start; `readyAt` records when. Exec does not require readiness: it auto-starts a stopped machine and waits for the agent itself.

Starting a machine blocks until the boot completes, which normally takes a few seconds. Pass `?detach=true` to return `202 Accepted` immediately and boot in the background, then poll `GET /v1/machines/{id}` until the state is `started` or `error`. Under a burst this keeps a client's own request timeout from cancelling a start that is still queued.

Stopping a machine preserves its stored state. Deleting it removes the machine. See the lifecycle page for billing and storage details.

## Plan limits

Three ceilings apply to every tenant, and all three come from the plan the
account is on rather than from the platform:

- **How many machines you may hold**: counted across every state, not just
  running ones, so a stopped machine still occupies a slot until it is deleted.
- **How many may run at once**: counted over `started`, `creating` and `pausing`,
  leaving out a source frozen as a branch base.
- **How large one machine may be**: vCPU, memory, and disk, applied per
  machine at create time.

Read your own ceilings rather than assuming them. `GET /v1/account` returns
the ones that apply to you now as `effectiveMaxMachines`, `effectiveMaxCpus`,
`effectiveMaxMemoryMb`, `effectiveMaxDiskGb` and `effectiveMaxConcurrentMachines`,
with `runningMachines` counted the way that limit counts them: starting,
running or pausing machines across the organization tree, not stopped or
frozen ones. The plan object beside them carries the plan's own
`maxConcurrentMachines`, `maxCpus`, `maxMemoryMb` and `maxDiskGb`. On the free
plan an account without a card is held to 4 vCPU per machine and 4 running
machines, which `effectiveMaxCpus` and `effectiveMaxConcurrentMachines` show:

```bash
curl -fsSL https://api.smolmachines.com/v1/account \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

The published plans and their ceilings are listed on the
[pricing page](/pricing). Limits differ between plans; the published per-unit
rates do not, so moving up a published plan buys headroom rather than a
different price. An Enterprise contract may carry its own rates.

Exceeding the machine count or size ceiling is refused at create with `422`, and
the running ceiling when a machine starts, also with `422`, with a body naming the
plan, the limit, and where to change it. Nothing is started, so nothing is charged:

```text
machine count quota exceeded: your Standard plan allows 20 machines; upgrade at https://smolmachines.com/pricing
concurrency limit reached: your Standard plan allows 20 machines running at once; upgrade at https://smolmachines.com/pricing
```

An account without a card on file runs up to 4 machines at once of up to
4 vCPU each, and its refusals say so. Adding a card lifts both to the plan's
limits once the account has paid or is a day old; with a prepaid card, or one
already on another account, only once it has paid:

```text
concurrency limit reached: an account without a card can run 4 machines at once; add a card at https://smolmachines.com/console/usage to run up to your plan's limit
machine size exceeds what an account without a card can run, up to 4 vCPU, 16 GB memory and 50 GB disk per machine (requested 8 vCPU, 8 GB); add a card at https://smolmachines.com/console/usage to use your plan's full limit
concurrency limit reached: a new account can run 4 machines at once until its first payment or its first day; add credit at https://smolmachines.com/console/usage to run up to your plan's limit now
concurrency limit reached: an account whose card is prepaid or already on another account can run 4 machines at once until its first payment; add credit at https://smolmachines.com/console/usage to run up to your plan's limit
```

A plan an account subscribed to itself runs the free plan's concurrent machines
and vCPUs per machine until its first payment or subscription is a week old;
email hello@smolmachines.com to lift them sooner.

::: tip
A count refusal usually means machines were left behind rather than that the
ceiling is genuinely too low. Ephemeral work should delete its machine when it
finishes, and `autoStopSeconds` stops an idle machine but does not delete it —
a stopped machine still holds its slot.
:::

## Errors and request IDs

Use the HTTP status code first. An `exec` whose command failed still answers `200`; read `exitCode`. Error bodies are RFC 9457 `application/problem+json`: a stable `code`, a `detail` sentence, and `retryable`, which is true for `408`, `429`, `502`, `503` and `504`; those also carry `Retry-After` in seconds. An exec whose machine stopped under it returns `503` with code `machine_interrupted`: the command may have partly run, and a retry runs it again. Two other refusals are worth retrying after a wait: a branch answers `409` "branches of this source made no progress ...; retry" while it waits behind its siblings, and a create answers `422` "no ready <arch> node" while no node of that architecture is up. For guest exit codes and SDK error patterns, see [Error handling](/docs/guides/error-handling).

[Error handling](/docs/guides/error-handling#rest-api-errors) says what each status means.

Every response includes `x-request-id`. A safe client-provided ID is echoed; otherwise the service generates one. Record it with the status and response body when reporting a failed request.

## Checkpoints and branches

Checkpoints capture any running machine, guest RAM and processes included, into durable storage: `POST /v1/machines/{id}/checkpoints` captures one, `GET /v1/machines/{id}/checkpoints` lists them, `POST /v1/checkpoints/{id}/restore` creates a stopped machine from one, which runs with the network its checkpoint was captured with (start it to resume it); the body takes `name` and optionally `labels`, `env`, `autoStopSeconds`, `idleAction` and `ports`, as [Branches and checkpoints](/docs/cloud/lifecycle-storage-networking#branches-and-checkpoints) describes, and `DELETE /v1/checkpoints/{id}` (`machine:delete`) deletes one, answering `409` while a machine still references it. A checkpoint whose contents do not match its checksum is refused with `422` ("the checkpoint is corrupt"), which a retry cannot help, so capture or upload it again. Starting a restored machine checks this, and so does `POST /v1/checkpoints/{id}/complete` for an upload of up to 32 MiB. See [Branches and checkpoints](/docs/cloud/lifecycle-storage-networking#branches-and-checkpoints) for the lifecycle and the CLI equivalents.

A machine is branchable when it is created with `"branchable": true` or started with `POST /v1/machines/{id}/start?branchable=true`. `POST /v1/machines/{id}/branches` (`machine:create`) creates a running copy-on-write child of it:

```bash
curl --fail-with-body -X POST "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/branches" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "try-1"}'
```

The body takes `name` and optionally `ports` (the source's guest ports when empty), `branchable` to let the child branch again, `freezeSource`, `keepMachineId` to keep the source's `/etc/machine-id` in the child, `labels` (the source's when left out), `expectedBusyCpus`, and `waitForCapacitySeconds`, at most 300, to keep retrying a branch refused for capacity. `POST /v1/machines/{id}/branches/batch` takes `count` or `names`, at most 64 children, with the same options; it is all or nothing, and a refusal for capacity may carry `childrenFit`.

Branch routes are specialized cloud operations. They do not move a running local VM into cloud or provide a portable cross-architecture restore format. `POST /v1/machines/{id}/snapshot` is not implemented and returns `501`; use a checkpoint to capture a running machine, or export a stopped machine's disk to a `.smolmachine` artifact (`POST /v1/machines/{id}/export`, or `smol cloud export`).

`GET /v1/capacity` (`machine:read`) sizes a fan-out before it starts: it returns how many machines you have and how many are started, the memory configured across started machines, and, for each running branchable machine, its memory and, when its node reports it, the node's branch headroom (`nodeHeadroomMib`). A branch its source's node cannot hold is refused with a retryable `503` `insufficient_capacity`, whose body carries `node.requiredMib`, `node.headroomMib` and `retryAfterSeconds`.

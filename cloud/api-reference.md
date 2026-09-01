---
title: Cloud API Reference
---

# Cloud API Reference

The Cloud API is the hosted REST interface for smol cloud.

- Base URL: `https://api.smolmachines.com`
- Generated OpenAPI: [smolmachines.com/openapi.json](/openapi.json)
- Interactive client: [API Explorer](/docs/cloud/api-explorer)

Use the generated OpenAPI document for the routes and schemas it includes. Specialized operations and newly added fields can land ahead of the website's generated snapshot, so use this page and the linked lifecycle guides for behavior that the schema does not yet describe.

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

Machine creation accepts an OCI image or a `.smolmachine` registry reference as its source. Specify CPU, memory, network policy, environment, working directory, lifecycle limits, mounts, and other supported fields in the create request.

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

### Files

The API supports file upload and download for a machine. Use the current OpenAPI or API Explorer for the path shape and request encoding.

Upload targets follow the machine's filesystem layout. Write to `/workspace` or another path on the storage disk when the file must survive a stop and start; `/tmp` is memory-backed and is empty after the machine restarts. An upload whose target resolves through a symlink into a memory-backed path fails instead of writing the file. See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking).

### Volumes

Cloud volumes are managed resources:

```text
GET    /v1/volumes
POST   /v1/volumes
GET    /v1/volumes/{id}
DELETE /v1/volumes/{id}
```

Attach a volume through the machine create request. See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking).

### Operational endpoints

The Cloud API also provides endpoints for:

- Running Python or JavaScript through `/code`
- Machine events and logs
- Per-machine usage and cached images
- Sharing a machine through scoped share links
- Forking a forkable machine
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

Stopping a machine preserves its stored state. Deleting it removes the machine. See the lifecycle page for billing and storage details.

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

## Forks and snapshots

Fork routes are specialized cloud operations. They do not move a running local VM into cloud or provide a portable cross-architecture restore format. Machine snapshots are not implemented in the cloud API: the snapshot routes return `501`. To capture a stopped machine's disk state, export it to a `.smolmachine` artifact instead (`POST /v1/machines/{id}/export`, or `smol cloud export`).

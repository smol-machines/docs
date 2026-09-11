---
title: "Local API: drive smolvm over HTTP"
---

# Local API: drive smolvm over HTTP

Drives smolvm programmatically over its local HTTP API (smolvm serve) instead of the CLI: create machines, exec and stream commands, move files in and out, and tear them down. Use when building a client, harness, agent tool or MCP backend over smolvm; when a create call is accepted but the machine behaves as if a field was ignored; when a file uploaded over the API has disappeared; when an exec that failed still returned HTTP 200; or when choosing between the Unix socket and loopback TCP. Do not use it as a substitute for the CLI in a shell script, and do not bind the listener beyond loopback: the API has no authentication of any kind.

## What it does

Preflight, start the server, export the OpenAPI spec, run a whole machine lifecycle over HTTP, clean up. Done means a machine went through create, start, exec, stream, a file round trip, stop and delete, and the machine list is empty again at the end.

Two rules run through it and they are the same shape: a 200 is not a result. A failing guest command still returns HTTP 200, so assert `exitCode` from the body rather than the status; the docs cover the general separation of command failures from infrastructure failures in [Error Handling](/docs/guides/error-handling). And an upload issued before the workload container is running returns 200 with the resolved path and byte count for a file that is then unreadable, so upload only after the container is up.

Exporting the spec before writing a request body is the step that saves the most time, because the field names are the schema's and not the CLI's flags: `network` not `net`, `memoryMb` not `memory`, and `cmd` for the workload you would pass after `--`. Unknown fields are accepted with a 200 and ignored, so a `memory` where the schema wants `memoryMb` silently gives you the default.

Cleanup order matters. Stopping the server does not stop machines, it orphans them, so recorded machines are deleted first, then the server is stopped, then the socket is removed.

## What it checks first

- That there is no authentication of any kind. The preflight reports `auth=none`, which is not a warning about your setup: `serve start` has no TLS, certificate, token or auth flag, so the transport you pick is the access control

The Unix socket is the packet's default for that reason, and its file permissions are a real boundary. Loopback TCP is for when a client needs a URL; treat that port as equivalent to a shell on the host. The packet puts its socket under its own state directory rather than in a world-traversable temporary directory.

## What it is not for

Replacing the CLI in a shell script. Binding the listener beyond loopback, for the reason above. For choosing between this API and the embedded SDK, see [Local API and smolvm serve](/docs/local/local-api-smolvm-serve); for the same lifecycle through the CLI, [dev-env](/docs/local/skills/dev-env).

## Platforms

| Platform | State |
|---|---|
| macOS arm64 | Verified, over the Unix socket |
| Linux aarch64 | Verified, over the Unix socket |
| Linux x86_64 | Verified in the material behind the packet over both transports, not re-run |
| Windows x86_64 | Recorded from one earlier run, not re-run. Loopback TCP only, no Unix socket form was attempted, and 400 and 404 return empty bodies there, so a wrong field name gets no diagnostic at all |

Loopback TCP is accepted by the packet's own server script and takes the same code path, but every run behind the packet used the Unix socket.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill local-api
```

The procedure is [`skills/local-api/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/local-api/SKILL.md). For the endpoint list and the deployment boundary, see [Local API and smolvm serve](/docs/local/local-api-smolvm-serve).

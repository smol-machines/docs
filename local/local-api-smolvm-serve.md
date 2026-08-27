---
title: Local API and smolvm serve
---

# Local API and smolvm serve

`smolvm serve` exposes local machine operations over HTTP. Use it for integrations that need a long-running local REST endpoint or already depend on the older `smolvm-sdk` client.

For new Node.js and Python applications, use the embedded `smolmachines` SDK instead. It runs the local engine in-process and can use the same Machine API with smol cloud. It does not require `smolvm serve`.

## Start the local server

Listen on loopback:

```bash
smolvm serve start --listen 127.0.0.1:8080
```

Or listen on a Unix socket:

```bash
smolvm serve start --listen "$XDG_RUNTIME_DIR/smolvm.sock"
```

Generate the OpenAPI specification for the installed version:

```bash
smolvm serve openapi
```

## Selected HTTP endpoints

| Method | Path | Operation |
|---|---|---|
| `POST` | `/api/v1/machines` | Create a machine |
| `GET` | `/api/v1/machines` | List machines |
| `GET` | `/api/v1/machines/:name` | Get one machine |
| `POST` | `/api/v1/machines/:name/start` | Start a machine |
| `POST` | `/api/v1/machines/:name/stop` | Stop a machine |
| `DELETE` | `/api/v1/machines/:name` | Delete a machine |
| `POST` | `/api/v1/machines/:name/exec` | Execute a command |
| `POST` | `/api/v1/machines/:name/exec/stream` | Stream execution over SSE |
| `PUT` | `/api/v1/machines/:name/files/*path` | Upload a file |
| `GET` | `/api/v1/machines/:name/files/*path` | Download a file |
| `GET` | `/api/v1/machines/:name/logs` | Stream logs over SSE |
| `POST` | `/api/v1/machines/:name/images/pull` | Pull an OCI image |

The HTTP API covers common lifecycle, execution, file, image, volume, export, and fork operations. It does not have complete parity with every CLI command or interactive CLI behavior. Use the generated OpenAPI document as the wire-level reference for your installed release.

## Choose an integration

### Recommended: embedded `smolmachines` SDK

Use npm or PyPI package `smolmachines` for new Node.js and Python applications.

- The local engine is embedded through native bindings
- No separate server process is required
- The API can target local machines or smol cloud
- This is the current SDK path in the [`smol`](https://github.com/smol-machines/smol) repository

See [SDK Quick Start](/docs/sdk) and [Use SDK in Local](/docs/sdk/with-local) for installation and code examples.

### Legacy REST client: `smolvm-sdk`

The older [`smolvm-sdk`](https://github.com/smol-machines/smolvm-sdk) repository publishes npm and PyPI packages named `smolvm`, plus a Go REST client. These clients send HTTP requests to a running `smolvm serve` process.

Use this path when:

- An existing integration already uses the local REST API
- A separate local runtime process is part of the deployment design
- The application language cannot use the embedded Node.js or Python packages

Do not confuse the package names:

| Package | Connection model | Recommended use |
|---|---|---|
| `smolmachines` | Embedded local engine; optional cloud transport | New Node.js and Python applications |
| `smolvm` from `smolvm-sdk` | HTTP client to `smolvm serve` | Existing or server-oriented REST integrations |

## Security and deployment boundary

The local server does not provide authentication. Bind it to loopback or a protected Unix socket. Do not expose port 8080 to an untrusted network.

If another host or user must reach the API, place it behind an authenticated, encrypted proxy and enforce host-level account isolation. Anyone who can call the API can ask the runtime to create machines and execute workloads with the capabilities granted to the server process.

`smolvm serve` is a per-host runtime API. It is not the standalone smol cloud fleet control plane.

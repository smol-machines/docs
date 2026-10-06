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

### One server to a host, unless you move a second port

Every `smolvm serve` also binds a fixed guest ingress port, `127.0.0.1:10081`, which `--listen`
does not move. A second server on the same host therefore fails at start whatever address it was
given:

```text
Error: config operation failed: bind guest rollout ingress: 127.0.0.1:10081: Address already in use
```

Set `SMOLVM_GUEST_ROLLOUT_HOST_PORT` to a free port for the second server, and the two run side by
side.

### Operator flags

| Flag | What it does |
|---|---|
| `--allow-nested-virt` | Permit machines created with `nestedVirt`. Off by default, because it exposes the host kernel's nested virtualization to the guest; turning it off again also stops existing nested machines from starting |
| `--egress-watchlist PATH` | Record, without blocking, guest traffic to destinations named in a file of `<label> dns-sha256:<hex>` or `<label> ip-sha256:<hex>` lines. Matches come back as `egressSignals` on the machine, the file is re-read when it changes, and it applies to virtio-net machines |
| `--shutdown-grace SECS` | Seconds in-flight requests get once the server stops accepting connections, five by default and capped at 3600. Connections are refused for the whole grace, so to restart without cutting off a long `exec`, wait for `GET /inflight` on the loopback door to report nothing in flight |
| `--mtls-client-cn CN` | Require this subject CN on the mTLS client certificate. Only applies when serve TLS is configured; unset, every certificate the client CA signed is accepted for every route |

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

The HTTP API covers common lifecycle, execution, file, image, volume, export, and branch operations. It does not have complete parity with every CLI command or interactive CLI behavior. Use the generated OpenAPI document as the wire-level reference for your installed release.

A create body is validated strictly: an unknown field is refused with `422` and a message naming
the field and listing the ones it accepts, and so is a known field of the wrong type. A field this
release does not have is refused rather than dropped in silence.

## Choose an integration

### Recommended: embedded `smolmachines` SDK

Use npm or PyPI package `smolmachines` for new Node.js and Python applications.

- The local engine is embedded through native bindings
- No separate server process is required
- The API can target local machines or smol cloud
- This is the current SDK path in the [`smol`](https://github.com/smol-machines/smol) repository

See [SDK Quick Start](/docs/sdk) and [Use SDK in Local](/docs/sdk/with-local) for installation and code examples.

### Legacy REST client: `smolvm-sdk`

The older [`smolvm-sdk`](https://github.com/smol-machines/smolvm-sdk) repository holds npm, Python and Go REST clients for a running `smolvm serve` process. Its npm and Python packages are named `smolvm` in source, but the `smolvm` on npm is an empty placeholder and the `smolvm` on PyPI is a different project, so neither registry installs these clients.

Use this path when:

- An existing integration already uses the local REST API
- A separate local runtime process is part of the deployment design
- The application language cannot use the embedded Node.js or Python packages

Do not confuse the package names:

| Package | Connection model | Recommended use |
|---|---|---|
| `smolmachines` | Embedded local engine; optional cloud transport | New Node.js and Python applications |
| The `smolvm-sdk` clients, named `smolvm` in source | HTTP client to `smolvm serve` | Existing or server-oriented REST integrations |

## Security and deployment boundary

The local server does not provide authentication. Bind it to loopback or a protected Unix socket. Do not expose port 8080 to an untrusted network.

If another host or user must reach the API, place it behind an authenticated, encrypted proxy and enforce host-level account isolation. Anyone who can call the API can ask the runtime to create machines and execute workloads with the capabilities granted to the server process.

`smolvm serve` is a per-host runtime API. It is not the standalone smol cloud fleet control plane.

A machine `serve` starts cannot reach a private, carrier-NAT or loopback address even when its `allowedCidrs` names one: `serve` raises the egress floor for every machine it starts, and no allow-list entry lowers it. To lift it, set `SMOLVM_EGRESS_FLOOR` before starting `serve`: `metadata` keeps only the link-local range that holds cloud metadata blocked, and `off` blocks nothing. Neither is the CLI's default, which also blocks the host's loopback.

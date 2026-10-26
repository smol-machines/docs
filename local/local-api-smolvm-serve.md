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

Every `smolvm serve` also binds a guest ingress port, `127.0.0.1:10081` by default, which `--listen`
does not move. A second server on the same host therefore fails at start whatever address it was
given:

```text
Error: config operation failed: bind guest rollout ingress: 127.0.0.1:10081: Address already in use
```

Give the second server its own port with `--guest-rollout-port PORT`, or
`SMOLVM_GUEST_ROLLOUT_HOST_PORT`, and the two run side by side. A running machine keeps the port it
started with.

### Operator flags

| Flag | What it does |
|---|---|
| `--cache-disk-dir DIR` | Directory of cache disk bases the API may attach, named by file name in `cacheDisk` on create and never by path. `POST /api/v1/machines/:name/cache-disk/publish` writes a stopped machine's cache, base and writes together, into it as a new base under a new name. Unset, the API refuses cache disks |
| `--cache-disk-max-gb GiB` | Most the bases in `--cache-disk-dir`, which it requires, may hold: past it the least recently used unattached bases are removed and fetched again when needed. Half that directory's filesystem by default, and a tenth of the filesystem is always kept free |
| `--allow-nested-virt` | Permit machines created with `nestedVirt`. Off by default, because it exposes the host kernel's nested virtualization to the guest; turning it off again also stops existing nested machines from starting |
| `--egress-watchlist PATH` | Record guest traffic to destinations named in a file of `<label> dns-sha256:<hex>` or `<label> ip-sha256:<hex>` lines, and block it on a line that ends in `block`: a matching lookup is answered as nonexistent and a matching connection is dropped. Matches come back as `egressSignals` on the machine, the file is re-read when it changes, and it applies to virtio-net machines. A TLS server name is matched like a DNS name, and a stratum login is recorded as the signal `stratum` |
| `--shutdown-grace SECS` | Seconds in-flight requests get once the server stops accepting connections, five by default and capped at 3600. Connections are refused for the whole grace, so to restart without cutting off a long `exec`, wait for `GET /inflight` on the loopback door to report nothing in flight |
| `--mtls-client-cn CN` | Require this subject CN on the mTLS client certificate. Only applies when serve TLS is configured; unset, every certificate the client CA signed is accepted for every route |
| `--mtls-allow-peer-blobs` | With `--mtls-client-cn`, also accept other certificates the client CA signed, but only on the peer blob routes under `/p2p/`, for sibling hosts that fetch cached layers from this one |
| `--local-image-dir DIR` | Directory of local images the API may create machines from: `docker save` or OCI archives and unpacked rootfs directories. A request's `image` path must resolve inside it; unset, the API accepts registry images only |
| `--restore-cache-entries N` | Restored checkpoints kept extracted after their machines are gone, so restoring one again reuses it; 32 by default, `0` keeps none |
| `--restore-cache-gib GiB` | Space those kept checkpoints may hold together, 256 GiB by default |
| `--prepared-checkpoint-cache-gib GiB` | Space for captured checkpoints kept on this host, so restoring one here skips the download; 64 GiB by default, and `SMOLVM_PREPARED_CHECKPOINT_CACHE_MAX_BYTES` takes precedence when set |
| `--cors-origin ORIGIN` | Allowed CORS origin, repeatable; `localhost:8080` and `localhost:3000` by default |
| `--json-logs` | Write logs as structured JSON for a log aggregator |

## Selected HTTP endpoints

| Method | Path | Operation |
|---|---|---|
| `POST` | `/api/v1/machines` | Create a machine |
| `GET` | `/api/v1/machines` | List machines |
| `GET` | `/api/v1/machines/:name` | Get one machine |
| `POST` | `/api/v1/machines/:name/start` | Start a machine |
| `POST` | `/api/v1/machines/:name/stop` | Stop a machine |
| `DELETE` | `/api/v1/machines/:name` | Delete a machine |
| `PUT` | `/api/v1/machines/:name/ports` | Replace a machine's published ports, live while it runs; a taken host port answers `409` `PORT_IN_USE` |
| `GET`, `POST`, `DELETE` | `/api/v1/machines/:name/mounts` | List, add or remove host directories mounted into a running machine; `POST` takes `source`, `target` and `readonly`, `DELETE` takes `?target=`, and a stopped machine answers `409` |
| `POST` | `/api/v1/machines/:name/exec` | Execute a command |
| `POST` | `/api/v1/machines/:name/exec/stream` | Stream execution over SSE |
| `PUT` | `/api/v1/machines/:name/files/*path` | Upload a file: up to 1 GiB with a `Content-Length`, 100 MiB without, `413` beyond. `?uid=`, `?gid=` and `?mode=` (octal) set its owner and permissions; with no owner it belongs to the workload's user |
| `GET` | `/api/v1/machines/:name/files/*path` | Download a file |
| `GET` | `/api/v1/machines/:name/logs` | Stream logs over SSE |
| `POST` | `/api/v1/machines/:name/images/pull` | Pull an OCI image |
| `POST` | `/api/v1/pools` | Create a warm pool of branched workers from a branchable source |
| `GET`, `DELETE` | `/api/v1/pools/:name` | Read or delete a pool |
| `PUT` | `/api/v1/pools/:name/size` | Change how many clean workers a pool keeps ready |
| `POST` | `/api/v1/pools/:name/leases` | Lease one clean worker |
| `POST` | `/api/v1/pools/:name/leases/:lease/heartbeat` | Extend a lease |
| `POST` | `/api/v1/pools/:name/leases/:lease/complete` | Finish a lease; the pool replaces its worker |

A warm pool keeps `desiredReady` workers branched from a source machine and ready to hand out. The source must be started `branchable` and its workload must reach its branch point by running under `smolvm-branch-ready`; until it does, the pool stays provisioning. A lease takes an `idempotencyKey`: repeating a request with the same key and the same body returns the same lease, and the same key with a different body is refused with `409`. A lease expires unless heartbeated, 300 seconds by default, and completing it retires the worker while the pool branches a fresh one.

The HTTP API covers common lifecycle, execution, file, image, volume, export, and branch operations. It does not have complete parity with every CLI command or interactive CLI behavior. Use the generated OpenAPI document as the wire-level reference for your installed release.

A branch request waits for the source up to 60 seconds plus 20 seconds per GiB of its memory, at most 540 seconds, then answers a retryable `503`.

A start takes `branchable`, `branchPoolSize` and `cudaVramLimitMib` in its JSON body or its query string; when both carry one, the query string wins.

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

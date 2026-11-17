---
title: Cloud Lifecycle, Storage, and Networking
---

# Cloud Lifecycle, Storage, and Networking

Cloud machines keep their filesystem across commands and stop/start cycles. Network access and published ports are explicit parts of the machine configuration.

The `curl` examples assume `SMOL_CLOUD_TOKEN` and `SMOL_CLOUD_URL` are set as shown in [Cloud Quick Start](/docs/cloud). `smol` commands need the [`smol` CLI](/docs/local/smol-cli-reference), signed in, which uses its own configured endpoint.

## Lifecycle

### Create

`POST /v1/machines` creates a machine record. New machines begin stopped.

Add `"start": true` to create it running instead: the create goes through the same checks as a start and answers `201` with the started machine, and `"waitReady": true` with it also waits for the machine to be ready. When that start fails, the machine the request created is deleted and the error says so; only then is the same create safe to retry. Such a request lasts a whole boot, so a client with a short timeout should set `name` and, when a retry answers `409`, find the machine with `GET /v1/machines?name=<name>` rather than create it again.

### Find a machine again

`labels` on the create, at most 32 key and value pairs, tag a machine for finding later. `GET /v1/machines?label=team=docs` lists the machines carrying that label; repeat `label` to require several. `GET /v1/machines?name=<name>` returns the one machine with that name, or an empty list. `PATCH /v1/machines/{id}/labels` changes them in any state: a string sets or replaces a key, `null` removes it, and keys left out keep their values:

```bash
curl --fail -X PATCH "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/labels" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"labels": {"team": "docs", "tier": null}}'
```

### Start

`POST /v1/machines/{id}/start` starts a stopped machine. An exec request also starts a stopped machine automatically. `?waitReady=true` holds the start's answer until the machine is ready, so the response already carries a working URL.

Starting and ready are separate conditions:

- `state: "started"` means the VM process launched
- `ready: true` means its published port is accepting connections, or, with no published port, that the guest agent answers. With several published ports only the first is probed

Poll the machine until `ready` is true before sending dependent work. Probe the application's own health endpoint separately when accepting a connection is not enough to establish application health.

### Stop

`POST /v1/machines/{id}/stop` stops compute while preserving the machine filesystem. Installed packages and files remain available after the next start.

Current public pricing states that stopped machines have no base, CPU, or memory charge. Stored disk continues to bill. Check the [pricing page](/pricing) for current rates.

### Delete

`DELETE /v1/machines/{id}` removes the machine. Export any required data first. Deleting the machine ends billing for its machine storage.

### Automatic cleanup

The create request can include:

- `autoStopSeconds`: stop the machine after this many seconds of inactivity. Activity is anything dispatched to the machine (exec, sessions, file transfers, ingress traffic), and an in-flight exec keeps the machine alive even past the timeout. The timer is checked by a sweep that runs every 15 seconds, and each machine's deadline carries a fixed offset of up to a quarter of the timeout, at most 60 seconds, so expect the stop up to about 75 seconds after the idle deadline.
  A machine that publishes a port and sets no `autoStopSeconds` can still be stopped when idle by the platform's default timeout, unless its plan includes always-on. Set `autoStopSeconds` yourself to choose the timeout; a machine with no published port is not stopped this way.
  `0` means never auto-stop. On a plan without always-on, `0` together with `ports` is refused with `422` while an idle default is in force.
- `idleAction`: what the idle timeout does. `stop`, the default, ends the machine's processes. `pause` saves the machine, memory included, so its processes carry on when it resumes, and a paused machine with a published port resumes on its next request. Records show it as `idleAction`.
- `ttlSeconds`: hard lifetime limit: the machine is deleted this many seconds after creation regardless of activity, on the same sweep and offset.
- `ephemeral`: the machine is deleted (not kept as stopped) once it stops.

`POST /v1/machines/{id}/keepalive` counts as activity without running anything, and answers with `idleDeadline`, when the machine will idle out if nothing else touches it, or `null` when it never auto-stops. Only a started machine can be kept alive; any other answers `409`.

Both timers take a final metering sample before acting, so an auto-stopped or expired machine's last window of CPU and memory is still billed and visible in `/usage`.

## Change a machine after create

These settings change on a machine that already exists. Where no SDK method or `smol` command is named, send the HTTP request; each needs the `machine:create` scope.

| Setting | Route | SDK and CLI | When it applies |
|---|---|---|---|
| Published ports | `PUT /v1/machines/{id}/ports`, [below](#ingress-and-published-ports) | `publish()` and `unpublish()` in Node and Python, `Publish` and `Unpublish` in Go; no Rust `Machine` method and no `smol` command | Started: at once, no restart. Stopped: at the next start |
| Outbound network | `PUT /v1/machines/{id}/network`, [below](#change-the-network-of-an-existing-machine) | None | Started: one allow list for another, at once; to or from `open` needs a stop first. Stopped: at the next start. A restored machine runs with the network its checkpoint was captured with |
| vCPUs, memory, disk | `POST /v1/machines/{id}/resize` | `resize()` in Node, Python and Rust; not in Go, and not `smol machine resize` | Started: in place. Stopped or paused: at the next start or resume. Memory and disk only grow |
| Labels | `PATCH /v1/machines/{id}/labels`, [above](#find-a-machine-again) | None | Any state, at once |
| Credential values | `PUT /v1/credentials/{name}`, [below](#credentials-the-machine-never-holds) | Node, Python and Rust store a credential's `value` when a create passes one | Running machines that bind it: from their next request |
| Credential bindings | `PUT /v1/machines/{id}/credentials` | None | Only while the machine has no copy on a node and nothing to restore; otherwise `409` |
| Public ingress | `POST` and `DELETE /v1/machines/{id}/public` | None | At once; needs a published port and a name of lowercase letters, digits and hyphens, else `422` |
| Idle clock | `POST /v1/machines/{id}/keepalive` | None | Started machines only |

Nothing changes `env`, `source`, `command`, `workdir`, `autoStopSeconds`, `idleAction`, `ttlSeconds`, `ephemeral`, `cacheDisk`, `remoteMounts` or `nestedVirt` on an existing machine. Create a new machine with the values you need, or checkpoint this one and restore it with new `env`, `autoStopSeconds`, `idleAction` or `labels`, as [Branches and checkpoints](#branches-and-checkpoints) describes.

## Machine storage

The machine filesystem persists across exec and stop/start. It is appropriate for packages, caches, checked-out repositories, and other state tied to one machine.

### Paths that do not persist

Some guest paths do not survive a restart. They keep their contents across exec calls while the machine runs, and are empty again after a stop and start, including a stop triggered by `autoStopSeconds`.

| Path | Backing | Across exec | Across stop/start |
|---|---|---|---|
| `/workspace` | Storage disk | Persists | Persists |
| Image filesystem (`/root`, `/etc`, `/usr`, and so on) | Storage disk | Persists | Persists |
| `/tmp` | Emptied at each start | Persists | Empty |
| `/run`, `/dev/shm` | Memory | Persists | Empty |

Write anything that must survive a restart to `/workspace` or another path on the machine filesystem. Treat `/tmp` as scratch space for a single run.

Credentials and configuration are a common case. A configuration path that is a symlink into `/tmp` is emptied whenever the machine stops, so a long-running agent that re-reads it after an idle stop finds nothing there. Keep those files on the machine filesystem instead.

Stopping is not a backup. Delete removes the machine, and a recovery point only brings a machine back after its node is lost, so keep important source data and outputs in an external system of record.

### Mount an S3 bucket

`remoteMounts` on the create mounts S3-compatible buckets inside the machine. A bucket is reachable from any node, so it does not tie the machine to one:

```json
{
  "source": {"type": "image", "reference": "python:3.12-alpine"},
  "env": {"AWS_ACCESS_KEY_ID": "...", "AWS_SECRET_ACCESS_KEY": "..."},
  "remoteMounts": [{"source": "s3://my-bucket/prefix", "mountPath": "/data", "readonly": true}]
}
```

Credentials come from the machine's `env`: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and optionally `AWS_ENDPOINT_URL` for a service such as R2 or MinIO and `AWS_REGION`. Without them the bucket is read anonymously, which suits public datasets. The machine's agent mounts the bucket from inside the guest, as on a [local machine](/docs/local/machine-lifecycle-cli-reference#mount-an-s3-bucket), so the machine's network must reach the bucket's endpoint. A source that is not an `s3://` URL with a bucket name, or a `mountPath` that is not absolute, is refused with `400`.

### Recovery points

A stop through the API or the idle timeout exports the machine's filesystem, without `/workspace`, as a recovery point, at no charge. If its node is lost, the next start creates the machine from its latest point, so its files outside `/workspace` come back as of that stop and `/workspace` comes back empty. A machine running when its node died loses its memory and what it wrote since that point.

`GET /v1/machines/{id}` shows the point as `recovery` (`reference`, `at`, `sizeBytes`), and a failed or skipped export as `recoveryError`; an earlier point still stands. Ephemeral machines, branches and branch bases take none, and the label `smol.recovery: off` (`labels` on the create request) opts a machine out. An account's points are capped in total: past the cap a stop takes no new point, and `recoveryError` says so.

## Cache disks

A cache disk is a disk image many machines start from, each through its own copy-on-write layer,
so a dependency or build cache is filled once and shared. Cache disks come with the Pro plan and
above; on other plans the routes answer `402`, naming the plan.

A cache disk is published in immutable versions. Version 0 is an empty filesystem, 20 GiB unless
`sizeGb` says otherwise, mounted at `/cache` unless `mountPath` does. A machine created with
`cacheDisk` starts from the latest version, or the one it names, and writes only to its own layer.
Publishing that machine's cache disk once it has stopped adds the next version, which later
machines start from:

```ts
import { CacheDisk, Machine } from "smolmachines";

await CacheDisk.create({ name: "deps" }, { target: "cloud" });
const machine = await Machine.create(
  { image: "node:22", cacheDisk: { cache: "deps" } },
  { target: "cloud" },
);
await machine.exec(["sh", "-c", "cd /cache && npm install"]);
await machine.stop();
await machine.publishCacheDisk();
```

In Python the same steps are `CacheDisk.create("deps")`, `MachineConfig(cache_disk=CacheDiskRef("deps"))`
and `publish_cache_disk()`.

| Method | Path | Operation |
|---|---|---|
| `POST` | `/v1/cache-disks` | Create a cache disk |
| `GET` | `/v1/cache-disks` | List cache disks, each with its versions newest first |
| `GET` | `/v1/cache-disks/{id}` | Get one cache disk by id or name |
| `DELETE` | `/v1/cache-disks/{id}` | Delete a cache disk and every version; refused while a machine runs with it |
| `POST` | `/v1/machines/{id}/cache-disk/publish` | Publish a stopped machine's cache disk as the next version |

Restoring a checkpoint keeps the disks it was captured with, so a new cache disk cannot be attached
to a restore. To restore one checkpoint with a different cache for each machine, create the source
with the cache disk as a slot (`slot: true`): it is attached unmounted, and a restore then mounts
any cache no larger than it at the slot's path (`cacheDisk` on restore).

## Outbound networking

Set `network.mode` explicitly so behavior does not depend on a changing default.

Block all outbound traffic:

```json
{"network": {"mode": "blocked"}}
```

Allow unrestricted outbound traffic:

```json
{"network": {"mode": "open"}}
```

Allow only selected hosts and CIDR ranges:

```json
{
  "network": {
    "mode": "allowCidrs",
    "hosts": ["api.example.com", "github.com"],
    "cidrs": ["203.0.113.0/24"]
  }
}
```

An allow list must include every package host, API, and redirect target the workload needs at runtime. The image's own registry is folded in for the pull; see [Cloud Examples](/docs/cloud/examples). Prefer `blocked` or `allowCidrs` for untrusted workloads.

To change the policy of a machine that already exists, see [Change an existing machine's network](#change-an-existing-machine-s-network).

### Change the network of an existing machine

`PUT /v1/machines/{id}/network` replaces a machine's policy, with the same `network` object a create takes as its whole body:

```bash
curl --fail-with-body -X PUT "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/network" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"mode": "allowCidrs", "hosts": ["api.example.com"], "cidrs": []}'
```

It answers `200` with the machine. What it accepts depends on the machine's state:

- On a started machine, an allow list replaces another allow list at once, without a restart, from the machine's next connection or DNS lookup; a new list of only CIDRs leaves names the machine already looked up reachable until their DNS TTL expires. Lifting the allow list (`open`), or adding one to a machine running with `open`, answers `409` until the machine is stopped.
- On a stopped machine, any change applies at its next start, except turning networking off. `blocked` on a machine that has run answers `422`; restrict it with `allowCidrs`, or create a new machine with `blocked`.
- On a machine created with `POST /v1/machines` that has never started, any policy is recorded for its first start, `blocked` included. A machine restored from a checkpoint runs with the network its checkpoint was captured with.

An allow list with no host and no CIDR answers `400`, and so does a malformed CIDR or host. `blocked` on a machine that binds credentials answers `422`. A frozen branch base, or a machine in any other state, such as `creating` or `paused`, answers `409`. No SDK method or `smol` command changes a cloud machine's network yet.

### Credentials the machine never holds

Store a secret once with `PUT /v1/credentials/github`, giving the variable a machine sees, the hosts the value may go to, and the value:

```json
{"envVar": "GITHUB_TOKEN", "hosts": ["api.github.com"], "value": "ghp_..."}
```

A machine created with `"credentials": ["github"]` sees a placeholder in `GITHUB_TOKEN`. Its node replaces the placeholder with the value only on HTTPS requests to the listed hosts, which are exact names: no wildcards or IP addresses. The value is never returned: `GET /v1/credentials` lists names, variables and hosts. After `DELETE /v1/credentials/{name}` a bound machine fails to start until the credential is stored again.

Storing a new value under the same name hands it to the running machines that bind it at once, from their next request. The response says where it went: `runningMachines.live` lists the machines using it now, and `runningMachines.nextStart` the ones that keep the old value until they next start, each with a `reason`: `engine_too_old` for a node older than smolvm 1.34.0, or `node_error`. Stopped machines are not listed, because every start hands a machine the current value.

A credential can set a whole request header instead of filling a placeholder. With `setHeader`, the node sets that header to the value on every HTTPS request to the hosts, replacing whatever the machine sent, so the value carries its own scheme and `envVar` can be left out:

```json
{"hosts": ["api.example.com"], "value": "Bearer sk_...", "setHeader": "authorization"}
```

A machine's bindings are fixed when its node first boots it. `PUT /v1/machines/{id}/credentials` with `{"credentials": ["github"]}` replaces them only while the machine has no copy on a node: before its first start, or after it lost its node copy with nothing to restore. Any other machine answers `409` and keeps its bindings, so a started machine that needs a new binding is a new machine. Naming the bindings a machine already has succeeds in any state. An unknown name answers `422`, and so does a binding on a machine whose network is `blocked`.

## Ingress and published ports

Publish a guest port in the create request:

```json
{
  "source": {"type": "image", "reference": "nginx"},
  "ports": [{"port": 80}],
  "public": false
}
```

Each cloud machine can publish up to 16 guest ports. A published port is a guest port declaration; use the returned URL or authenticated connect route to reach it. The machine record's `url` is the ingress URL of its first published port, `null` until the machine is started and its port answers; port links, below, give one URL for each port.

The service must listen on `0.0.0.0` inside the machine, not `127.0.0.1`. A service listening only on the machine's localhost cannot be reached through a published port.

With `public: false`, use the authenticated connect route where it is enabled:

```bash
curl --fail \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/connect/80" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

The connect route also accepts WebSocket upgrades for clients that need a bidirectional connection.

Set `public: true` only when the service should be reachable without the caller's API authorization. Public ingress exposes application traffic, so the application must provide any authentication and authorization it needs.

To change the ports of a machine that already exists, send the whole new list to `PUT /v1/machines/{id}/ports`:

```bash
curl --fail-with-body -X PUT "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/ports" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"ports": [{"port": 8080}, {"port": 3000}]}'
```

A started machine serves new ports at once and stops serving removed ones, without a restart; a stopped machine takes them at its next start. A port kept from before keeps its host port, and a `hostPort` in the request is ignored. An empty list removes every port, and more than 16 answers `422`. In the SDKs, `machine.publish({ guest: 3000 })` (`machine.publish(3000)` in Python) adds one port and `unpublish()` removes one; the `smol` CLI has no command for it.

A client that cannot send an API key, such as a sandbox framework that calls its tunnel URLs directly, can use port links instead. `POST /v1/machines/{id}/port-links` returns a login-free URL for each published port, `https://p<port>-<token>.<appsDomain>`. Anyone holding a link reaches the port, so treat it as a credential. The machine keeps one token, so asking again returns the same links and a port published later is reached with the same token; `DELETE /v1/machines/{id}/port-links` revokes every link at once.

### Custom domains

To serve a machine or group on a domain you own, claim it with `POST /v1/custom-domains`, giving `domain`, `targetKind` (`machine` or `group`) and `targetId`, or from [Domains](/console/domains) in the console. The response lists the DNS records to create: a TXT record at `_smolmachines-challenge.<domain>` holding a token, and a CNAME target for a subdomain (an apex domain gets an A record target where one is offered). Then call `POST /v1/custom-domains/{domain}/verify`; the first account to pass the TXT check owns the name, and other claims on it are dropped. `DELETE /v1/custom-domains/{domain}` removes it.

Traffic on a verified domain is public, with no smol cloud login. An account holds at most 10 unverified claims and sends at most 30 claims an hour, and an unverified claim lapses after 7 days.

## Change an existing machine's network

Egress, published ports and public access all change on a machine that already exists. There is no need to create a new one.

| Change | API | SDK (Node / Python / Go) | MCP tool |
|---|---|---|---|
| What the machine may reach outbound | `PUT /v1/machines/{id}/network` | `setNetworkPolicy(policy)` / `set_network_policy(policy)` / `SetNetworkPolicy(ctx, policy)` | `smol_set_network` |
| Which guest ports are published | `PUT /v1/machines/{id}/ports` | `publish`, `unpublish`, `ports` | `smol_publish_port`, `smol_unpublish_port` |
| Public access with no login | `POST` / `DELETE /v1/machines/{id}/public` | | |
| An anonymous share token | `POST` / `DELETE /v1/machines/{id}/share` | | |

### Egress

Send the machine's whole new policy as the body, in the same form as `network` on create:

```bash
curl -X PUT "https://api.smolmachines.com/v1/machines/$ID/network" \
  -H "Authorization: Bearer $SMOL_API_KEY" -H "Content-Type: application/json" \
  -d '{"mode": "allowCidrs", "hosts": ["api.github.com"], "cidrs": ["10.0.0.0/8"]}'
```

- A started machine whose policy is an allow list takes a new allow list at once, from its next connection or lookup.
- Switching a started machine to or from `open` needs it stopped first. The call answers `409` until it is; stop it, set the policy, and start it.
- A stopped machine takes any change at its next start.
- A machine that has run cannot be switched to `blocked` (`422`), because its VM was made with networking on. Restrict it to an allow list instead. A machine that has never run takes `blocked` for its first start, unless it binds credentials.

In the SDKs the policy is `"allow-all"`, `"deny-all"`, or an allow list: `{ allowHosts, allowCidrs }` in Node, `{"allow_hosts": [...], "allow_cidrs": [...]}` in Python, and `AllowList(hosts, cidrs)` in Go.

### Published ports

`PUT /v1/machines/{id}/ports` takes the whole new list of guest ports, as described under [Ingress and published ports](#ingress-and-published-ports). A started machine serves new ports at once and stops serving removed ones, without a restart.

### Public access

`POST /v1/machines/{id}/public` serves the machine's app URL to anyone, with no smol cloud login and no token, and `DELETE` returns it to the login gate. `POST /v1/machines/{id}/share` mints (or rotates) an anonymous share token for the app URL instead, and `DELETE` revokes it. Either grants access only to the machine's published app port, never to the API, exec, or another machine.

## Running a command as a chosen user

`smol cloud exec` takes `--user`, a name from the image or a numeric `uid[:gid]`,
which overrides the image's `USER` for that command:

```bash
smol cloud exec -n myapp --user 1000:1000 -- id
```

The control plane has to carry the field for this to mean anything, and an older
one drops unknown fields silently, which would run the command as the image's
default account with nothing to show it was ignored. The CLI therefore checks
that the control plane echoed the user back, and refuses rather than guessing:

```text
the control plane did not honour --user 1000:1000: it predates that field and
would have run the command as the image's default account. It needs upgrading
before --user can be used on cloud machines.
```

Seeing that means the deployment is behind, not that the flag is wrong.

## Branches and checkpoints

Checkpoints are how you save a cloud machine and get back to a known-good state. A checkpoint captures a running machine, guest RAM and processes included, into durable cloud storage, and can be pulled down as a `.smolcheckpoint` artifact. Any running machine can be captured; only branching needs a machine created branchable.

```bash
smol cloud checkpoint create myapp
smol cloud checkpoint ls myapp
smol cloud checkpoint download CHECKPOINT_ID -o ./myapp.smolcheckpoint
smol cloud checkpoint restore CHECKPOINT_ID --name myapp-restored
smol cloud checkpoint rm CHECKPOINT_ID
```

`restore` creates and starts a new machine from the checkpoint. A restored machine runs with the network its checkpoint was captured with, an allow list included, so capture the checkpoint from a machine that has the access the restored one should have. `POST /v1/checkpoints/{id}/restore` takes `name`, and with it `labels`, `env` for processes started after the restore, `autoStopSeconds`, `idleAction` and `ports`. The machine binds the credentials its checkpoint's machine bound, publishes the checkpoint's ports unless `ports` is given, and has no labels or env unless they are given. `ports`, when given, must list exactly the checkpoint's guest ports; anything else answers `422`. The API restore leaves the machine stopped; start it to resume. A downloaded artifact can also be restored locally with `smolvm machine create --from`, subject to the host requirements in [Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots). Neither branching nor checkpoint provides a cross-architecture restore format.

To return the same machine to a checkpoint instead, `POST /v1/machines/{id}/rollback` replaces its running state with its newest checkpoint, or the one `checkpointId` names, and starts it again. It keeps the machine's id, name, network policy and credentials, discards the work done since, and is refused while the machine has live branches.

### Move a local machine to the cloud

`smol machine move --name NAME` moves a running local machine to the cloud, processes and all: it pauses the machine, uploads the saved execution as a checkpoint and resumes it as a cloud machine. Commands that name the machine then reach the cloud copy, and the paused one stays here as `local/NAME` until `smol machine resume` runs it again or `smol machine rm` removes it. `--keep-local` leaves the local machine running and sends a copy as of now, and `--as` names the cloud machine. The cloud copy keeps the networking the local machine had; it never gets an allow list it did not have. When a move without `--keep-local` fails, the local machine stays paused with its execution saved, and `smol machine resume --name NAME` continues it here.

With `smol` 1.35, a move has these limits:

- It moves a machine created with `--net` and no allow list. A machine created without networking, or with `--allow-host` or `--allow-cidr`, is refused with `source reference must name a registry image, not a path or local source on the node`.
- When the machine publishes a port, the move waits for that port to accept connections in the cloud copy. If nothing listens within 10 minutes, it deletes the cloud copy; without `--keep-local` the local machine stays paused. Start the service before you move, or move a machine without published ports.
- A move from a Linux host can be refused when the cloud node lacks a CPU feature the local guest was given, such as `FEAT_RPRES`.

Branching creates a copy-on-write child from a running branchable cloud machine. It does not provide local-to-cloud live migration.

For a tree of machines that build on each other, branch rather than checkpoint, because a branch carries its source's disks and cache disk. Branch with `freezeSource` (`freeze_source` in Python) and the source is kept paused as a reusable branch base that no longer counts toward the concurrency cap. A frozen source cannot run commands again; work in its branches, or stop it.

To keep a stopped machine's disk state without its running state, export it to a `.smolmachine` artifact.

## GPU

Hosted cloud machine resource requests currently expose CPU, memory, and disk fields. They do not expose GPU fields. Local smolvm GPU support does not imply hosted cloud GPU availability.

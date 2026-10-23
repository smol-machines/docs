---
title: Cloud Lifecycle, Storage, and Networking
---

# Cloud Lifecycle, Storage, and Networking

Cloud machines keep their filesystem across commands and stop/start cycles. Network access and published ports are explicit parts of the machine configuration.

The command examples assume `SMOL_CLOUD_TOKEN` and `SMOL_CLOUD_URL` are set as shown in [Cloud Quick Start](/docs/cloud).

## Lifecycle

### Create

`POST /v1/machines` creates a machine record. New machines begin stopped.

### Start

`POST /v1/machines/{id}/start` starts a stopped machine. An exec request also starts a stopped machine automatically.

Starting and ready are separate conditions:

- `state: "started"` means the VM process launched
- `ready: true` means the guest agent is reachable and every published port is accepting connections

Poll the machine until `ready` is true before sending dependent work. Probe the application's own health endpoint separately when accepting a connection is not enough to establish application health.

### Stop

`POST /v1/machines/{id}/stop` stops compute while preserving the machine filesystem. Installed packages and files remain available after the next start.

Current public pricing states that stopped machines have no base, CPU, or memory charge. Stored disk continues to bill. Check the [pricing page](/pricing) for current rates.

### Delete

`DELETE /v1/machines/{id}` removes the machine. Export any required data first. Deleting the machine ends billing for its machine storage.

### Automatic cleanup

The create request can include:

- `autoStopSeconds`: stop the machine after this many seconds of inactivity. Activity is anything dispatched to the machine — exec, sessions, file transfers, ingress traffic — and an in-flight exec keeps the machine alive even past the timeout. The timer is checked by a sweep that runs every 15 seconds, so expect the stop to land within about 15 seconds after the idle deadline.
  A machine that publishes a port and sets no `autoStopSeconds` can still be stopped when idle by the platform's default timeout, unless its plan includes always-on. Set `autoStopSeconds` yourself to choose the timeout; a machine with no published port is not stopped this way.
- `ttlSeconds`: hard lifetime limit — the machine is deleted this many seconds after creation regardless of activity, on the same 15-second sweep.
- `ephemeral`: the machine is deleted (not kept as stopped) once it stops.

Both timers take a final metering sample before acting, so an auto-stopped or expired machine's last window of CPU and memory is still billed and visible in `/usage`.

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

Stopping is not a backup. Delete removes the machine, and infrastructure failures can still affect machine-local state. Keep important source data and outputs in an external system of record.

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

An allow list must include every registry, package host, API, and redirect target the workload needs. Prefer `blocked` or `allowCidrs` for untrusted workloads.

### Credentials the machine never holds

Store a secret once with `PUT /v1/credentials/github`, giving the variable a machine sees, the hosts the value may go to, and the value:

```json
{"envVar": "GITHUB_TOKEN", "hosts": ["api.github.com"], "value": "ghp_..."}
```

A machine created with `"credentials": ["github"]` sees a placeholder in `GITHUB_TOKEN`. Its node replaces the placeholder with the value only on HTTPS requests to the listed hosts, which are exact names: no wildcards or IP addresses. The value is never returned: `GET /v1/credentials` lists names, variables and hosts. Replacing a credential reaches bound machines at their next boot, and after `DELETE /v1/credentials/{name}` a bound machine fails to start until the credential is stored again.

## Ingress and published ports

Publish a guest port in the create request:

```json
{
  "source": {"type": "image", "reference": "nginx"},
  "ports": [{"port": 80}],
  "public": false
}
```

Each cloud machine can publish up to 16 guest ports. A published port is a guest port declaration; use the returned URL or authenticated connect route to reach it.

The service must listen on `0.0.0.0` inside the machine, not `127.0.0.1`. A service listening only on the machine's localhost cannot be reached through a published port.

With `public: false`, use the authenticated connect route where it is enabled:

```bash
curl --fail \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/connect/80/" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

The connect route also accepts WebSocket upgrades for clients that need a bidirectional connection.

Set `public: true` only when the service should be reachable without the caller's API authorization. Public ingress exposes application traffic, so the application must provide any authentication and authorization it needs.

To change the ports of a machine that already exists, send the whole new list to `PUT /v1/machines/{id}/ports`. A started machine serves new ports at once and stops serving removed ones, without a restart; a stopped machine takes them at its next start. A port kept from before keeps its host port.

A client that cannot send an API key, such as a sandbox framework that calls its tunnel URLs directly, can use port links instead. `POST /v1/machines/{id}/port-links` returns a login-free URL for each published port, `https://p<port>-<token>.<appsDomain>`. Anyone holding a link reaches the port, so treat it as a credential. The machine keeps one token, so asking again returns the same links and a port published later is reached with the same token; `DELETE /v1/machines/{id}/port-links` revokes every link at once.

### Custom domains

To serve a machine or group on a domain you own, claim it with `POST /v1/custom-domains`, giving `domain`, `targetKind` (`machine` or `group`) and `targetId`, or from [Domains](/console/domains) in the console. The response lists the DNS records to create: a TXT record at `_smolmachines-challenge.<domain>` holding a token, and a CNAME target for a subdomain (an apex domain gets an A record target where one is offered). Then call `POST /v1/custom-domains/{domain}/verify`; the first account to pass the TXT check owns the name, and other claims on it are dropped. `DELETE /v1/custom-domains/{domain}` removes it.

Traffic on a verified domain is public, with no smol cloud login. An account holds at most 10 unverified claims and sends at most 30 claims an hour, and an unverified claim lapses after 7 days.

Verify port and ingress fields in the API Explorer for the deployment you use.

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

`restore` creates and starts a new machine from the checkpoint. A downloaded artifact can also be restored locally with `smolvm machine create --from`, subject to the host requirements in [Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots). Neither branching nor checkpoint provides a cross-architecture restore format.

To return the same machine to a checkpoint instead, `POST /v1/machines/{id}/rollback` replaces its running state with its newest checkpoint, or the one `checkpointId` names, and starts it again. It keeps the machine's id, name, network policy and credentials, discards the work done since, and is refused while the machine has live branches.

`smol machine move --name NAME` moves a running local machine to the cloud, processes and all: it pauses the machine, uploads the saved execution as a checkpoint and resumes it as a cloud machine. Commands that name the machine then reach the cloud copy, and the paused one stays here as `local/NAME` until `smol machine resume` runs it again or `smol machine rm` removes it. `--keep-local` leaves the local machine running and sends a copy as of now, `--as` names the cloud machine, and `--net` or `--no-net` overrides the networking it had. When the upload fails, the local machine stays paused with its execution saved.

Branching creates a copy-on-write child from a running branchable cloud machine. It does not provide local-to-cloud live migration.

For a tree of machines that build on each other, branch rather than checkpoint, because a branch carries its source's disks and cache disk. Branch with `freezeSource` (`freeze_source` in Python) and the source is kept paused as a reusable branch base that no longer counts toward the concurrency cap. A frozen source cannot run commands again; work in its branches, or stop it.

`POST /v1/machines/{id}/snapshot` is not implemented and returns `501`; use a checkpoint to capture a running machine. To keep a stopped machine's disk state without its running state, export it to a `.smolmachine` artifact.

## GPU

Hosted cloud machine resource requests currently expose CPU, memory, and disk fields. They do not expose GPU fields. Local smolvm GPU support does not imply hosted cloud GPU availability.

---
title: Cloud Lifecycle, Storage, and Networking
---

# Cloud Lifecycle, Storage, and Networking

Cloud machines keep their filesystem across commands and stop/start cycles. Network access, published ports, and additional volumes are explicit parts of the machine configuration.

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

`DELETE /v1/machines/{id}` removes the machine. Export any required data first. Deleting the machine ends billing for its machine storage; separately managed volumes must be deleted separately.

### Automatic cleanup

The create request can include:

- `autoStopSeconds`: stop the machine after this many seconds of inactivity. Activity is anything dispatched to the machine — exec, sessions, file transfers, ingress traffic — and an in-flight exec keeps the machine alive even past the timeout. The timer is checked by a sweep that runs every 15 seconds, so expect the stop to land within about 15 seconds after the idle deadline.
- `ttlSeconds`: hard lifetime limit — the machine is deleted this many seconds after creation regardless of activity, on the same 15-second sweep.
- `ephemeral`: the machine is deleted (not kept as stopped) once it stops.

Both timers take a final metering sample before acting, so an auto-stopped or expired machine's last window of CPU and memory is still billed and visible in `/usage`.

## Machine storage

The machine filesystem persists across exec and stop/start. It is appropriate for packages, caches, checked-out repositories, and other state tied to one machine.

### Paths that do not persist

Some guest paths are backed by memory rather than the machine's storage disk. They keep their contents across exec calls while the machine runs, and are empty again after a stop and start — including a stop triggered by `autoStopSeconds`.

| Path | Backing | Across exec | Across stop/start |
|---|---|---|---|
| `/workspace` | Storage disk | Persists | Persists |
| Image filesystem (`/root`, `/etc`, `/usr`, and so on) | Storage disk | Persists | Persists |
| `/tmp`, `/run`, `/dev/shm` | Memory | Persists | Empty |

Write anything that must survive a restart to `/workspace` or another path on the machine filesystem. Treat `/tmp` as scratch space for a single run.

Credentials and configuration are a common case. A configuration path that is a symlink into `/tmp` is emptied whenever the machine stops, so a long-running agent that re-reads it after an idle stop finds nothing there. Keep those files on the machine filesystem instead.

Stopping is not a backup. Delete removes the machine, and infrastructure failures can still affect machine-local state. Keep important source data and outputs in an external system or a supported volume workflow.

## Cloud volumes

Cloud volumes are managed by the Cloud API:

```bash
curl --fail-with-body -X POST "$SMOL_CLOUD_URL/v1/volumes" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"project-data","sizeGb":10}'
```

Attach a volume when creating a machine:

```json
{
  "source": {"type": "image", "reference": "alpine"},
  "mounts": [
    {
      "volume": "project-data",
      "mountPath": "/data",
      "readonly": false
    }
  ]
}
```

Cloud volumes are different from local bind mounts:

- A local bind mount maps a host path into a local smolvm
- A cloud volume is a cloud-managed resource attached by name
- A cloud machine cannot mount an arbitrary path from your laptop

Current attachment constraints:

- A volume is placed on one node. A machine with attached volumes is placed on that node.
- All volumes attached to one machine must be on the same node; otherwise start fails with `422`.
- A volume can be attached to only one machine at a time; an attachment conflict returns `409`.
- Referencing a missing volume returns `400`.
- Deleting a machine detaches its volumes but does not delete them. Delete each volume separately when its data is no longer needed.

Cloud volumes are persistent storage attachments, not backups. Keep critical source data and outputs in an external backup or system of record.

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

## Ingress and published ports

Publish a guest port in the create request:

```json
{
  "source": {"type": "image", "reference": "nginx"},
  "ports": [{"port": 80}],
  "public": false
}
```

Each cloud machine can publish up to four guest ports. A published port is a guest port declaration; use the returned URL or authenticated connect route to reach it.

With `public: false`, use the authenticated connect route where it is enabled:

```bash
curl --fail \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/connect/80/" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

The connect route also accepts WebSocket upgrades for clients that need a bidirectional connection.

Set `public: true` only when the service should be reachable without the caller's API authorization. Public ingress exposes application traffic, so the application must provide any authentication and authorization it needs.

Verify port and ingress fields in the API Explorer for the deployment you use.

## Forks and checkpoints

Fork creates a copy-on-write child from a running forkable cloud machine. It does not provide local-to-cloud live migration.

Machine snapshots are not implemented in the cloud API: the snapshot routes return `501`. To keep a stopped machine's disk state, export it to a `.smolmachine` artifact instead.

Checkpoints capture a running machine, guest RAM and processes included, into durable cloud storage, and can be pulled down as a `.smolcheckpoint` artifact:

```bash
smol cloud checkpoint create myapp
smol cloud checkpoint ls myapp
smol cloud checkpoint download CHECKPOINT_ID -o ./myapp.smolcheckpoint
smol cloud checkpoint restore CHECKPOINT_ID --name myapp-restored
smol cloud checkpoint rm CHECKPOINT_ID
```

`restore` creates and starts a new machine from the checkpoint. A downloaded artifact can also be restored locally with `smolvm machine create --from`, subject to the host requirements in [Forks and Snapshots](/docs/introduction/concepts/forks-and-snapshots). Neither fork nor checkpoint provides a cross-architecture restore format.

## GPU

Hosted cloud machine resource requests currently expose CPU, memory, and disk fields. They do not expose GPU fields. Local smolvm GPU support does not imply hosted cloud GPU availability.

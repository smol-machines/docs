---
name: "cloud-machine"
description: "Creates a smol cloud machine, runs commands in it, moves files in and out, stops and starts it, and deletes it with the settled bill. Use when a task needs a machine on smol cloud rather than a local one; when a create call is rejected for a field that looks right; when an exec that failed still came back as HTTP 200; when a file uploaded over the API cannot be found afterwards; or when deciding what survives a stop and start. Do not use it to install the CLI or hand over a key, which is the cloud-auth packet, and do not use it to scope egress or publish ports, which the machine record exposes but this packet deliberately leaves alone."
---

# A machine on smol cloud, end to end

Verified on **smol v1.14.3** and **smolfleet API 0.1.0** (`apiVersion` 2), macOS 26.6.2 arm64
client, against `https://api.smolmachines.com` on 2026-09-10. Guest architecture served was
`amd64`. One full pass cost **1810 micros (USD 0.0018)** for 157 uptime-seconds.

Done means a marker written before a stop is readable after the start, the guest's own uptime
proves it really rebooted, a file round-tripped through the API, and the machine id is gone from
both the CLI and the API afterwards.

Assumes the credential from the `cloud-auth` packet. **One rule runs through everything here:
a 200 is not a result.** A guest command that exited 42 returns HTTP 200 with the exit code in
the body.

## Procedure

**1. Preflight.** Read-only: creates no machine, bills nothing.

```bash
scripts/preflight.sh
```

It reports the tenant, the plan's machine ceiling, the key's scopes and a **live** machine count.
The scope check is worth reading first: a key missing `machine:exec` fails in the middle of a
lifecycle rather than at the start.

**2. Create and start.**

```bash
scripts/create.sh smolskill-m1
scripts/create.sh smolskill-m1 library/alpine:3.20
```

It records the id in a state file so cleanup is exact even if a later step throws, then polls a
value from inside the guest rather than sleeping. Two things about the request body are not
guessable and cost the most time:

- **`source` is required and is a tagged object.** `{"source":{"type":"image","reference":"library/alpine:3.20"}}`. A top-level `image` field is rejected outright.
- **`cpus` and `memoryMb` live under `resources`.** At the top level they are silently ignored, because unknown fields are accepted and dropped.

The script publishes **no port**. That is deliberate: the CLI publishes 8080 by default, which
both widens the machine's exposure and makes `ready` unreachable for any image that does not
listen there. With no port published, `ready` becomes `true` normally.

**3. Drive the lifecycle and assert what survives.**

```bash
scripts/verify-lifecycle.sh
```

```
guest_exec=ok (MACHINE_UP)
failing_exec_exit_code=ok (42)
file_upload=ok (204)
file_download=ok (ROUNDTRIP-9f3a)
file_in_guest=ok (ROUNDTRIP-9f3a)
workspace_survives=ok (persist-9f3a)
tmp_wiped=ok ()
really_rebooted=ok (uptime 1s)
branchable=false forkable=false
result=lifecycle_ok
```

`really_rebooted` is the load-bearing assertion. It proves the guest restarted rather than the
control plane flipping a state field, which is the failure a `state == "started"` check cannot
see.

**4. Clean up, and take the bill from the delete.**

```bash
scripts/cleanup.sh
scripts/cleanup.sh --reap     # also removes anything left carrying the name prefix
```

```
deleted=mach-... uptime_s=157 micros=1810
settled_micros=1810
api_prefix_machines_left=0
cli_prefix_machines_left=0
over_ceiling=no (ceiling=1000000 micros)
result=clean
```

`DELETE /v1/machines/{id}?includeUsage=true` returns the **settled** bill. A mid-life usage read
is a documented lower bound, so it is the only figure worth recording.

## What survives a stop and start

| Path | Survives | Why |
|---|---|---|
| `/workspace` | yes | the machine's storage disk, `/dev/vda` |
| `/tmp` | **no** | a `tmpfs` sized at half the machine's RAM |

## Moving files

The path is a **suffix on the route, with no leading slash**, and it is relative to the guest
root:

```bash
curl -X PUT  --data-binary @local.txt  "$API/v1/machines/$ID/files/workspace/app.txt"   # 204
curl         "$API/v1/machines/$ID/files/workspace/app.txt"                             # 200
```

The `?path=/workspace/app.txt` query form returns an empty-bodied 404 that reads exactly like
"no such machine". See `references/traps.md`.

## Branching

**Branching works, and it has to be asked for when the machine is created.** A machine created
without it reports `branchable: false` and `capabilities.branch: false`, which is what
`verify-lifecycle.sh` prints for the plain machine it makes. Create with the capability and the
call succeeds:

```python
Machine.create(MachineConfig(..., branchable=True), conn).branch("child-name")
```

Verified on 2026-09-10 through the Python SDK: a branch child ran a command and returned
`FROM_BRANCH`. `branch()` takes the child's name as a required first argument.

`fork` is the older name for the same operation and still works everywhere: the CLI accepts it as
an alias of `branch`, `--forkable` as an alias of `--branchable`, and the SDK keeps a separate
`fork()` method taking `forkable=True` at create. Prefer `branch`.

**The published spec documents no branch route** among its 44 paths, so this is not discoverable
from the schema. That is a known property of this spec rather than a sign the feature is missing;
see `references/traps.md`. Earlier material recorded this call failing with a server 500 on this
deployment, which no longer reproduces.

## Security defaults, and why they are the defaults

- **No published port.** A port is the machine's exposure to the internet, and the machine record
  shows that ingress forwards the caller's `authorization` header, the account key, to whatever
  listens. Publish one deliberately, for a server you wrote, or not at all.
- **Cleanup deletes only ids the packet recorded.** An account is shared, and a cleanup that
  deletes every machine it can see is fine on a personal account and destructive on a team's.
  `--reap` widens that to this packet's name prefix and no further.
- **A spend ceiling is asserted, not assumed.** `cleanup.sh` fails if the settled total crosses
  it. Override with `SMOLSKILL_CEILING_MICROS`.
- **`network.mode: open` is outbound access for the whole machine**, and it is on here because
  the image pull needs it. Scoping egress is a separate concern and is not covered by this
  packet.
- **Nothing here prints the credential.** The scripts read `SMOL_CLOUD_TOKEN` from the
  environment and pass it in a header.

## Platform arms

- **macOS arm64 client**: verified. Guests served were `amd64`.
- **Linux and Windows clients**: **not run.** The HTTP half is `curl` and a URL and depends on
  nothing platform specific; the CLI half was not executed there.

## What was not run

- **Branching from this packet's own scripts.** It was verified through the Python SDK rather
  than raw HTTP, because the published spec documents no route for it. Snapshot, checkpoint and
  export were not exercised at all.
- **Published ports, ingress and egress scoping.** Deliberately out of scope, and the machine
  record's networking fields carry a defect that is not routed around here.
- **`mounts`.** The field exists in the create schema and cloud volumes are not built, so a
  request carrying it is accepted and produces a machine silently missing its storage.
- **The automatic cleanup fields** `autoStopSeconds`, `ttlSeconds` and `ephemeral`. They are in
  the create schema and were not exercised in this pass.
- **The CLI half of the lifecycle.** Everything above was driven over HTTP. `smol cloud ls` is
  used only as the second surface in the leak check.

## Related packets

- `cloud-auth` for the credential this assumes and the scope list to read first.

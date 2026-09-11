# Traps, with the observation behind each

Reproduced on smol v1.14.3 against smolfleet API 0.1.0 on 2026-09-10 unless an item says
otherwise.

## A failing guest command returns HTTP 200

```
POST /v1/machines/{id}/exec  {"command":"sh -c \"echo OUT; echo ERR >&2; exit 42\""}
HTTP=200
{"stdout":"OUT\n","stderr":"ERR\n","exitCode":42,"durationMs":19,...}
```

The exit code is in the body and nowhere else. A client that branches on the status code sees
success for every guest failure there is. The CLI does propagate it: `smol cloud exec ... 'exit 42'`
exits 42.

**Assert `exitCode`.** This is the single most consequential trap in this API for anyone writing
a client.

## The create body is not shaped like the CLI's flags

`source` is required and is a tagged object. A top-level `image` is rejected:

```
{"name":"m","image":"library/alpine:3.20","cpus":1,"memoryMb":512}
-> Failed to deserialize the JSON body into the target type: missing field `source`
   hint: "source" is an object tagged by "type": {"type":"image","reference":"alpine:3.20"}
      or {"type":"smolmachine","reference":"tenants/<tenant>/group:v1","arch":"amd64"}
```

The working shape:

```json
{"name":"smolskill-m1",
 "source":{"type":"image","reference":"library/alpine:3.20"},
 "resources":{"cpus":1,"memoryMb":512},
 "network":{"mode":"open"}}
```

`cpus` and `memoryMb` belong under `resources`. At the top level they are **silently ignored**,
because unknown fields are accepted and dropped, so the machine comes up with defaults and
nothing says why. The error above is the good case; the silent one is worse.

## `POST /v1/machines` does not start the machine

It returns `state: "stopped"` and `capabilities.exec: false`. Call `/start`, or rely on exec's
auto-start. Do not poll for `ready` on a machine nothing has started.

## The files route path is a suffix, not a query parameter

This corrects an earlier reading. The route is:

```
PUT /v1/machines/{id}/files/workspace/app.txt   --data-binary @local.txt   -> 204
GET /v1/machines/{id}/files/workspace/app.txt                             -> 200 + content
```

No leading slash, and the path is relative to the guest root, so `workspace/app.txt` lands at
`/workspace/app.txt`. Verified by reading it back from inside the guest.

The query form is what fails:

```
PUT /v1/machines/{id}/files?path=/workspace/app.txt   -> 404, empty body
GET /v1/machines/{id}/files?path=/workspace/app.txt   -> 404, empty body
```

An empty-bodied 404 is indistinguishable from "no such machine", which is what a client concludes
first. The suffix form's own 404 is informative by comparison:
`file not found: workspace/rt.txt`. The published schema documents no parameter at all for this
route, so the shape is not discoverable from it.

## `ready` is reachable, but only if you publish no port

The runbooks record `ready` never becoming true. That is a consequence of the **CLI publishing
port 8080 by default**: the readiness probe waits for something to accept a connection there, and
an off-the-shelf image serves nothing.

Create over the API with no `ports` field and the machine reports `ready: true` normally
[observed: `ready = True`, `ports = []`]. So the rule is not "ready is useless"; it is
**"ready tracks the published port, so do not publish one you are not serving"**.

For a machine you do publish a port on, `url` stays null and `ready` stays false until the app
accepts a connection. Start the app, then read `url`, not the reverse.

## Both ingress routes forward your account key to the app in the machine

Anything listening on a published port receives the caller's `authorization` header, unchanged.
An app behind a published port must read its own credential from a different header, and anything
logging headers in a machine is logging the tenant key. Recorded 2026-09-08, not re-run here.

## `smol cloud` has no `stop` or `start`

Its verbs are deploy, ls, rm, scale, logs, shell, exec, export, checkpoint, share, unshare. Stop
and start live on `smol machine stop|start --cloud`, and nothing in `smol cloud --help` points
across. Write the `--cloud` flag even though location is "resolved automatically": when a local
machine and a cloud machine share a name it is the difference between stopping the right one and
the other one.

## A bare image reference resolves to your own registry namespace

Through the CLI, `smol cloud deploy alpine:3.20` fails with
`image not found in registry: blob not found: tenants/<tenant>/alpine:3.20`. Use `library/alpine:3.20`
or a full `docker.io/library/alpine:3.20`. The failed deploy prints a machine id before failing
but the record is rolled back, so do not chase that id.

## Take the bill from the delete

`DELETE /v1/machines/{id}?includeUsage=true` returns 200 with settled usage. A mid-life read is a
documented lower bound. One observed pass:

```
uptime_s=157  micros=1810
```

`baseMicros` dominates for a short-lived small machine: you are paying for the machine existing,
not for its CPU. `execMicros` is always 0.

## `periodUsage.machineCount` is not a live count

It is cumulative for the billing period, so it is useless as a leak check. Count `GET /v1/machines`
and check `smol cloud ls` as well: the two are different code paths, and a leak check that trusts
one is how a billed machine survives a run.

## The published schema is behind the API

The generated OpenAPI omits routes that work, including per-machine usage, export and share, and
documents no parameters for the files route. **Do not conclude a route is missing from its absence
in the schema**, and do not conclude a parameter does not exist either.

Branch and fork are the sharpest case. `/health` advertises `machine.branch`,
`machine.branch_batch`, `machine.branch_source_continues`, `machine.lineage` and
`machine.portable_checkpoint`; no branch or fork path exists among the spec's 44; and a machine
created without asking for them reports `branchable: false`, `forkable: false` and
`capabilities.branch: false`. All three of those are true **and both operations work**, provided
the machine was created with `branchable` or `forkable` set. The record's fields report what you
asked for at create time, not what the cluster can do.

So the rule is: read the machine record for what this machine can do, read `/health` for what the
cluster offers, and trust neither the spec's silence nor a record field to tell you a feature does
not exist.

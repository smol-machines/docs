---
title: "Cloud machine: create, drive and delete a cloud machine"
---

# Cloud machine: create, drive and delete a cloud machine

Creates a smol cloud machine, runs commands in it, moves files in and out, stops and starts it, and deletes it with the settled bill. Use when a task needs a machine on smol cloud rather than a local one; when a create call is rejected for a field that looks right; when an exec that failed still came back as HTTP 200; when a file uploaded over the API cannot be found afterwards; or when deciding what survives a stop and start. Do not use it to install the CLI or hand over a key, which is the cloud-auth packet, and do not use it to scope egress or publish ports, which the machine record exposes but this packet deliberately leaves alone.

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

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/lib.sh`

```bash
# Shared by this packet's scripts. Sourced, not run.
# Never echoes the credential.
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
PREFIX="smolskill-"
STATE="${SMOLSKILL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/smol-skills}"
mkdir -p "$STATE"
IDFILE="$STATE/cloud-machines.ids"

api() { # api METHOD PATH [JSON_BODY]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" --max-time 120 \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
      -d "$body" "$API$path"
  else
    curl -sS -X "$method" --max-time 120 \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API$path"
  fi
}

jget() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit(0)
for k in sys.argv[1].split('.'):
    if d is None: break
    d = d.get(k) if isinstance(d, dict) else None
print('' if d is None else d)" "$1"; }

require_token() {
  [ -n "${SMOL_CLOUD_TOKEN:-}" ] && return 0
  echo "credential=FAIL expected=SMOL_CLOUD_TOKEN set actual=unset"; echo "result=cannot_run"; exit 1
}

record() { echo "$1" >> "$IDFILE"; }   # only ids this packet created
```

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Read-only. Creates no machine and bills nothing. Never prints the key.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

health=$(curl -fsS --max-time 20 "$API/health" 2>/dev/null)
[ -n "$health" ] && echo "api_reachable=yes" || { echo "api_reachable=no"; echo "result=blocked"; exit 0; }
echo "api_version=$(printf '%s' "$health" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"

acct=$(api GET /v1/account)
status=$(printf '%s' "$acct" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
echo "tenant_status=${status:-unknown}"
echo "max_machines=$(printf '%s' "$acct" | sed -n 's/.*"effectiveMaxMachines":\([0-9]*\).*/\1/p')"

# Scopes decide whether the lifecycle can complete at all, and they fail late otherwise.
if command -v smol >/dev/null 2>&1; then
  scopes=$(smol auth status 2>/dev/null | sed -n 's/.*Access *//p')
  echo "scopes=${scopes:-unknown}"
  for need in machine:create machine:read machine:exec machine:delete; do
    case "$scopes" in *"$need"*) ;; *) echo "note=this key lacks $need; the lifecycle cannot complete";; esac
  done
else
  echo "scopes=unknown (smol not on PATH)"
fi

# A live count, because periodUsage.machineCount is cumulative for the period.
live=$(api GET /v1/machines | grep -o '"id"' | wc -l | tr -d ' ')
echo "machines_live_now=$live"
echo "recorded_by_this_packet=$( [ -f "$IDFILE" ] && wc -l < "$IDFILE" | tr -d ' ' || echo 0)"

[ "$status" = "active" ] && echo "result=ready" || echo "result=blocked"
```

### `scripts/create.sh`

```bash
#!/usr/bin/env bash
# Creates one cloud machine over HTTP and records its id for cleanup.
# Creates a billable machine. Run cleanup.sh when done.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

NAME="${1:-${PREFIX}m1}"
IMAGE="${2:-library/alpine:3.20}"
case "$NAME" in "$PREFIX"*) ;; *) echo "name=FAIL expected=${PREFIX}* actual=$NAME"; exit 1;; esac

# `source` is required and is a tagged object; `image` at the top level is
# rejected with a deserialize error. cpus and memoryMb live under `resources`.
# No "ports" field: the CLI publishes 8080 by default, which makes `ready`
# unreachable for a non-server image and widens the machine's exposure.
body=$(printf '{"name":"%s","source":{"type":"image","reference":"%s"},"resources":{"cpus":1,"memoryMb":512},"network":{"mode":"open"}}' "$NAME" "$IMAGE")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
if [ -z "$id" ]; then
  echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; echo "result=create_failed"; exit 1
fi
record "$id"
echo "machine_id=$id"
echo "created_state=$(printf '%s' "$resp" | jget state)"

start=$(api POST "/v1/machines/$id/start" '{}')
echo "started_state=$(printf '%s' "$start" | jget state)"

# Poll on a value from inside the guest rather than sleeping a fixed time: the
# record flips to "started" when the control plane says so, not when the guest
# can run a command, and the gap is what a blind sleep gets wrong in both
# directions. Bounded so a machine that never answers fails instead of hanging.
deadline=$(( $(date +%s) + 120 ))
ready=no
while [ "$(date +%s)" -lt "$deadline" ]; do
  out=$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","echo GUEST_UP"]}' 2>/dev/null | jget stdout)
  case "$out" in *GUEST_UP*) ready=yes; break;; esac
  sleep 3
done
echo "guest_answered=$ready"
[ "$ready" = yes ] && echo "result=up" || { echo "result=guest_never_answered"; exit 1; }
```

### `scripts/verify-lifecycle.sh`

```bash
#!/usr/bin/env bash
# Drives one machine through exec, files, stop, start and asserts what survives.
# Asserts values from bodies, never HTTP status: a failed guest command is a 200.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

ID="${1:-$(tail -1 "$IDFILE" 2>/dev/null)}"
[ -n "$ID" ] || { echo "machine=FAIL expected=an id actual=none recorded"; exit 1; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

ex() { api POST "/v1/machines/$ID/exec" "$(printf '{"command":["sh","-c",%s]}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")")"; }
exout() { ex "$1" | jget stdout | tr -d '\n'; }

check guest_exec MACHINE_UP "$(exout 'echo MACHINE_UP')"

# A failing command comes back on HTTP 200. The exit code is in the body and is
# the only place the failure appears, so assert it rather than the status.
r=$(ex 'echo out; echo err >&2; exit 42')
check failing_exec_exit_code 42 "$(printf '%s' "$r" | sed -n 's/.*"exitCode":\([0-9-]*\).*/\1/p')"

# Files are a path SUFFIX on the route, with no leading slash. The ?path= query
# form returns an empty-bodied 404 that reads exactly like "no such machine".
up=$(curl -sS -X PUT --max-time 60 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
     -H 'content-type: application/octet-stream' --data-binary 'ROUNDTRIP-9f3a' \
     -o /dev/null -w '%{http_code}' "$API/v1/machines/$ID/files/workspace/rb-rt.txt")
check file_upload 204 "$up"
check file_download ROUNDTRIP-9f3a "$(curl -sS --max-time 60 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/machines/$ID/files/workspace/rb-rt.txt")"
check file_in_guest ROUNDTRIP-9f3a "$(exout 'cat /workspace/rb-rt.txt')"

# One marker per filesystem. Everything after this is a read.
ex 'echo persist-9f3a > /workspace/rb-marker.txt; echo tmp-9f3a > /tmp/rb-marker.txt' >/dev/null

api POST "/v1/machines/$ID/stop" '{}' >/dev/null
api POST "/v1/machines/$ID/start" '{}' >/dev/null
# Poll on a value from the guest, not on the record's state field: start returns
# when the record flips, which is before the guest can run anything.
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ "$(exout 'echo BACK')" = "BACK" ] && break
  sleep 3
done

check workspace_survives persist-9f3a "$(exout 'cat /workspace/rb-marker.txt 2>/dev/null')"
check tmp_wiped "" "$(exout 'cat /tmp/rb-marker.txt 2>/dev/null')"

# The load-bearing one: it proves the guest really rebooted rather than the
# control plane flipping a state field, which a state check cannot see.
up_s=$(exout 'cut -d. -f1 /proc/uptime')
if [ -n "$up_s" ] && [ "$up_s" -lt 120 ]; then echo "really_rebooted=ok (uptime ${up_s}s)"
else echo "really_rebooted=FAIL expected=uptime under 120s actual=${up_s:-unknown}"; fails=$((fails+1)); fi

# Reported honestly rather than attempted: there is no branch or fork route in
# the published spec, and the machine record says it cannot.
rec=$(api GET "/v1/machines/$ID")
echo "branchable=$(printf '%s' "$rec" | sed -n 's/.*"branchable":\([a-z]*\).*/\1/p') forkable=$(printf '%s' "$rec" | sed -n 's/.*"forkable":\([a-z]*\).*/\1/p')"

[ "$fails" -eq 0 ] && echo "result=lifecycle_ok" || echo "result=lifecycle_failed"
[ "$fails" -eq 0 ]
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Deletes only the machines this packet recorded, takes the settled bill from the
# delete, and proves both surfaces are clean. --reap also removes any machine
# carrying this packet's name prefix, for a run that threw before recording.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
CEILING_MICROS="${SMOLSKILL_CEILING_MICROS:-1000000}"   # USD 1, asserted below

total=0
if [ -f "$IDFILE" ]; then
  while read -r id; do
    [ -n "$id" ] || continue
    # ?includeUsage=true returns the settled bill. A mid-life /usage read is a
    # documented lower bound, so this is the only figure worth recording.
    resp=$(api DELETE "/v1/machines/$id?includeUsage=true")
    micros=$(printf '%s' "$resp" | sed -n 's/.*"totalMicros":\([0-9]*\).*/\1/p')
    secs=$(printf '%s' "$resp" | sed -n 's/.*"totalUptimeSeconds":\([0-9]*\).*/\1/p')
    echo "deleted=$id uptime_s=${secs:-0} micros=${micros:-0}"
    total=$(( total + ${micros:-0} ))
  done < "$IDFILE"
  rm -f "$IDFILE"
fi
echo "settled_micros=$total"

if [ "${1:-}" = "--reap" ]; then
  api GET /v1/machines | python3 -c "
import json,sys
for m in json.load(sys.stdin):
    if (m.get('name') or '').startswith('$PREFIX'): print(m['id'])" | while read -r id; do
    [ -n "$id" ] || continue
    echo "reaped=$id"; api DELETE "/v1/machines/$id" >/dev/null
  done
fi

# Both surfaces, because the CLI list and the API list are different code paths.
left=$(api GET /v1/machines | python3 -c "
import json,sys
print(sum(1 for m in json.load(sys.stdin) if (m.get('name') or '').startswith('$PREFIX')))")
echo "api_prefix_machines_left=$left"
if command -v smol >/dev/null 2>&1; then
  smol cloud ls 2>/dev/null | grep -q "$PREFIX" && echo "cli_prefix_machines_left=some" || echo "cli_prefix_machines_left=0"
else
  echo "cli_prefix_machines_left=skipped"
fi

over=no; [ "$total" -gt "$CEILING_MICROS" ] && over=yes
echo "over_ceiling=$over (ceiling=${CEILING_MICROS} micros)"
[ "$left" -eq 0 ] && [ "$over" = no ] && echo "result=clean" || echo "result=NOT_CLEAN"
[ "$left" -eq 0 ] && [ "$over" = no ]
```

## Traps, with the observation behind each

Reproduced on smol v1.14.3 against smolfleet API 0.1.0 on 2026-09-10 unless an item says
otherwise.

### A failing guest command returns HTTP 200

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

### The create body is not shaped like the CLI's flags

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

### `POST /v1/machines` does not start the machine

It returns `state: "stopped"` and `capabilities.exec: false`. Call `/start`, or rely on exec's
auto-start. Do not poll for `ready` on a machine nothing has started.

### The files route path is a suffix, not a query parameter

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

### `ready` is reachable, but only if you publish no port

The runbooks record `ready` never becoming true. That is a consequence of the **CLI publishing
port 8080 by default**: the readiness probe waits for something to accept a connection there, and
an off-the-shelf image serves nothing.

Create over the API with no `ports` field and the machine reports `ready: true` normally
[observed: `ready = True`, `ports = []`]. So the rule is not "ready is useless"; it is
**"ready tracks the published port, so do not publish one you are not serving"**.

For a machine you do publish a port on, `url` stays null and `ready` stays false until the app
accepts a connection. Start the app, then read `url`, not the reverse.

### Both ingress routes forward your account key to the app in the machine

Anything listening on a published port receives the caller's `authorization` header, unchanged.
An app behind a published port must read its own credential from a different header, and anything
logging headers in a machine is logging the tenant key. Recorded 2026-09-08, not re-run here.

### `smol cloud` has no `stop` or `start`

Its verbs are deploy, ls, rm, scale, logs, shell, exec, export, checkpoint, share, unshare. Stop
and start live on `smol machine stop|start --cloud`, and nothing in `smol cloud --help` points
across. Write the `--cloud` flag even though location is "resolved automatically": when a local
machine and a cloud machine share a name it is the difference between stopping the right one and
the other one.

### A bare image reference resolves to your own registry namespace

Through the CLI, `smol cloud deploy alpine:3.20` fails with
`image not found in registry: blob not found: tenants/<tenant>/alpine:3.20`. Use `library/alpine:3.20`
or a full `docker.io/library/alpine:3.20`. The failed deploy prints a machine id before failing
but the record is rolled back, so do not chase that id.

### Take the bill from the delete

`DELETE /v1/machines/{id}?includeUsage=true` returns 200 with settled usage. A mid-life read is a
documented lower bound. One observed pass:

```
uptime_s=157  micros=1810
```

`baseMicros` dominates for a short-lived small machine: you are paying for the machine existing,
not for its CPU. `execMicros` is always 0.

### `periodUsage.machineCount` is not a live count

It is cumulative for the billing period, so it is useless as a leak check. Count `GET /v1/machines`
and check `smol cloud ls` as well: the two are different code paths, and a leak check that trusts
one is how a billed machine survives a run.

### The published schema is behind the API

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

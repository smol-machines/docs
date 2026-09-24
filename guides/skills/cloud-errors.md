---
title: "Cloud errors: handle every failure the API returns"
---

# Cloud errors: handle every failure the API returns

Provokes every failure the smol cloud API can return and shows what a client must branch on, including the failures that arrive as HTTP 200. Use when writing a client, harness or agent tool against the cloud API; when a call succeeded by status but the work did not happen; when a 422 needs to be told apart from a schema bug, a wrong type and a quota refusal; or when deciding which failures are safe to retry. Do not use it to drive a normal machine lifecycle, which is the cloud-machine packet, and do not expect it to cover billing suspension or rate limiting, which cannot be provoked on a healthy account.

Verified on **smolfleet API 0.1.0** and **smol v1.14.3**, macOS 26.6.2 arm64 client, on
2026-09-10. One pass cost **89 micros (USD 0.00009)** for 7 uptime-seconds; most of the packet
costs nothing, because most failures happen before a machine exists.

Two rules, and both are the same shape: **the status code is not the result.**

1. **A failing guest command returns HTTP 200.** The exit code is in the body and nowhere else.
2. **The status does not tell you the body's format.** `401` is JSON with a `code` field.
   `400`, `403`, `404`, `409`, `422` and `501` are plain text.

## Procedure

**1. The failures that need no machine.** Free.

```bash
scripts/provoke-http.sh
```

```
unknown_key_401=ok (401)
nonexistent_path_401=ok (401)
missing_scope_403=ok (403)
not_json_400=ok (400)
missing_field_422=ok (422)
wrong_type_422=ok (422)
no_such_machine_404=ok (404)
result=all_provoked
```

**2. The failures that arrive as 200.** Creates one small machine.

```bash
scripts/provoke-exec.sh
scripts/cleanup.sh --reap
```

```
duplicate_name_409=ok (409)
nonzero_exit_status=ok (200)   nonzero_exit_code=ok (42)
timeout_status=ok (200)        timeout_exit_code=ok (124)
missing_binary_status=ok (200) missing_binary_exit_code=ok (255)
result=all_provoked
```

## What to branch on

| Situation | Status | Body | What a client must do |
|---|---|---|---|
| Bad or missing key | `401` | JSON, `{"code":"unknown_key"}` | Stop. Do not retry with the same key |
| Any path without a key | `401` | empty | You cannot probe routes unauthenticated |
| Missing scope | `403` | text, names the scope | Stop. The key needs minting again |
| Body is not JSON | `400` | text | Fix the request |
| Body parses, schema unsatisfied | `422` | text | Fix the request. **Not** retryable |
| Semantic rule broken | `400` | text | Fix the request. See the counterexample below |
| No such machine | `404` | text, `machine not found` | Stop |
| Duplicate name | `409` | text | Choose another name |
| Route deliberately unimplemented | `501` | text | Stop. It will not start working |
| **Guest command failed** | **`200`** | JSON, `exitCode` non-zero | **Read `exitCode`** |

Guest exit codes worth knowing: `42` is whatever the command returned, `124` is a timeout, and
`255` is an executable that was not found.

## The 400 versus 422 split does not hold

The documented split is that `400` means malformed and `422` means invalid. Neither direction is
reliable:

- A **wrong field name**, a **wrong type**, and being **over quota** are all `422` with prose
  bodies. A client that treats `422` as a quota problem and retries will retry a schema bug
  forever.
- A **semantic rule** on a well-formed body can be `400`:

```
POST /v1/machines  {"network":{"mode":"allowCidrs","cidrs":[]}}
allowCidrs network mode requires at least one CIDR or host
http=400
```

So a client cannot triage by status and must read the body, which is prose for every status but
`401`.

## Security defaults, and why they are the defaults

- **Nothing here retries.** Every failure this packet provokes is a client error, and the two
  that would be retryable in principle are the two it cannot provoke.
- **The 403 body names the missing scope**, so a scope failure is diagnosable without widening
  the key. Read it rather than minting a broader key by reflex.
- **The bad-key probe uses a deliberately invalid string**, never a real key with a character
  changed, so nothing valid is ever sent to a log.
- **Cleanup deletes only what this packet recorded**, and the machine it makes is the smallest
  the plan allows.

## Platform arms

- **macOS arm64 client**: verified. The provocations are `curl` and a URL and depend on nothing
  platform specific.
- **Linux and Windows clients**: **not run.** Note that on Windows the API has been recorded
  returning **empty bodies for 400 and 404**, which would make a wrong field name undiagnosable;
  that was not re-run here.

## What was not run

- **`402`, billing restriction.** Needs a suspended or over-budget tenant. Not provokable on a
  healthy account, and not guessed.
- **`429`, rate limiting.** The budget is roughly 10000 requests per period and a burst did not
  approach it. `x-ratelimit-remaining` is returned and is undocumented; it is the cheapest way to
  see what a burst consumed.
- **`5xx`.** Nothing here can cause one on purpose.
- **`501`** was recorded from the export route by an earlier run and was not re-provoked here.

## Related packets

- `cloud-auth` for the credential, and for why `smol auth status` cannot gate anything.
- `cloud-machine` for the lifecycle these failures interrupt, and the same 200-on-failure rule
  applied to a real run.

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

### `scripts/provoke-http.sh`

```bash
#!/usr/bin/env bash
# Provokes every documented failure that needs no machine, and asserts the status
# AND the body shape, because on this API the two do not agree about the format.
# Creates nothing and bills nothing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
fails=0
# probe NAME EXPECTED_STATUS EXPECTED_BODY_SUBSTRING curl-args...
probe() {
  local name="$1" want="$2" needle="$3"; shift 3
  local body status
  body=$(curl -sS --max-time 45 -o /tmp/ce.$$ -w '%{http_code}' "$@"); status="$body"
  body=$(head -c 300 /tmp/ce.$$ | tr '\n' ' ')
  if [ "$status" = "$want" ] && case "$body" in *"$needle"*) true;; *) false;; esac; then
    echo "$name=ok ($status)"
  else
    echo "$name=FAIL expected=$want+'$needle' actual=$status '$body'"; fails=$((fails+1))
  fi
}
H="Authorization: Bearer $SMOL_CLOUD_TOKEN"
J='content-type: application/json'

# 401: the body here IS json with a code field. Almost nothing else is.
probe unknown_key_401 401 unknown_key -H 'Authorization: Bearer smk_wrong' "$API/v1/machines"
# 401 on a route that does not exist, so route probing without a key tells you nothing.
probe nonexistent_path_401 401 "" "$API/v1/nope"
# 403 names the exact missing scope in plain text.
probe missing_scope_403 403 "missing scope" -H "$H" "$API/v1/volumes"
# 400 is reserved for a body that is not JSON at all.
probe not_json_400 400 "" -X POST -H "$H" -H "$J" -d 'not json' "$API/v1/machines"
# 422 is everything that parses but does not satisfy the schema: three causes, one status.
probe missing_field_422 422 source -X POST -H "$H" -H "$J" -d '{"name":"x"}' "$API/v1/machines"
probe wrong_type_422 422 "" -X POST -H "$H" -H "$J" \
  -d '{"source":{"type":"image","reference":"library/alpine:3.20"},"resources":{"cpus":"lots"}}' "$API/v1/machines"
# 404 carries a message, unlike the unauthenticated 401 above.
probe no_such_machine_404 404 "not found" -H "$H" "$API/v1/machines/mach-does-not-exist"

echo "---"
echo "note=401 is JSON with a code field; 400, 403, 404, 409, 422 and 501 are plain text"
echo "note=a 422 cannot be triaged by status: a typo, a wrong type and a quota refusal are all 422"
rm -f /tmp/ce.$$
[ "$fails" -eq 0 ] && echo "result=all_provoked" || echo "result=unexpected_shapes"
[ "$fails" -eq 0 ]
```

### `scripts/provoke-exec.sh`

```bash
#!/usr/bin/env bash
# The failures that arrive as HTTP 200. These are the ones that matter: no status
# check finds them. Creates one small machine and deletes it via cleanup.sh.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

NAME="${PREFIX}err1"
body=$(printf '{"name":"%s","source":{"type":"image","reference":"library/alpine:3.20"},"resources":{"cpus":1,"memoryMb":256},"network":{"mode":"open"}}' "$NAME")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
[ -n "$id" ] || { echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; exit 1; }
record "$id"; echo "machine_id=$id"
api POST "/v1/machines/$id/start" '{}' >/dev/null
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ -n "$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","echo up"]}' | jget stdout)" ] && break
  sleep 3
done

# A duplicate name is one of the few real 4xx a running machine can produce.
dup=$(curl -sS --max-time 45 -o /tmp/ce2.$$ -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
      -d "$body" "$API/v1/machines")
check duplicate_name_409 409 "$dup"; rm -f /tmp/ce2.$$

ex() { curl -sS --max-time 60 -o /tmp/ce3.$$ -w '%{http_code}' -X POST \
       -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
       -d "$1" "$API/v1/machines/$id/exec"; }
field() { python3 -c "import json,sys;print(json.load(open('/tmp/ce3.$$')).get(sys.argv[1],''))" "$1" 2>/dev/null; }

# 1. A command that exited non-zero.
check nonzero_exit_status 200 "$(ex '{"command":["sh","-c","echo out; echo err >&2; exit 42"]}')"
check nonzero_exit_code 42 "$(field exitCode)"
# 2. A command that timed out. 124 is the shell's timeout convention.
check timeout_status 200 "$(ex '{"command":["sh","-c","sleep 30"],"timeoutSeconds":3}')"
check timeout_exit_code 124 "$(field exitCode)"
# 3. An interpreter the image does not have. Not a transport failure either.
check missing_binary_status 200 "$(ex '{"command":["python3","-c","print(1)"]}')"
mb=$(field exitCode); [ "$mb" != 0 ] && echo "missing_binary_exit_code=ok ($mb)" || { echo "missing_binary_exit_code=FAIL expected=non-zero actual=0"; fails=$((fails+1)); }
rm -f /tmp/ce3.$$

echo "---"
echo "note=every failure above is HTTP 200; exitCode in the body is the only signal"
[ "$fails" -eq 0 ] && echo "result=all_provoked" || echo "result=unexpected_shapes"
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

Reproduced on smolfleet API 0.1.0 on 2026-09-10 unless an item says otherwise.

### "Check the HTTP status before decoding a success response" is backwards for exec

The status is 200 for a command that succeeded, one that exited 42, one that timed out and one
whose interpreter was missing:

```
{"command":["sh","-c","echo out; echo err >&2; exit 42"]}   -> 200, exitCode 42
{"command":["sh","-c","sleep 30"],"timeoutSeconds":3}       -> 200, exitCode 124
{"command":["python3","-c","print(1)"]}                     -> 200, exitCode 255
```

The last one's stderr reads
`executable file 'python3' not found in $PATH: No such file or directory`. All three are
indistinguishable from success by status.

The CLI does the right thing and propagates the guest exit code; raw HTTP does not. Both SDKs
propagate it too, but their `exec` promise **resolves** for a failed command, so a `try/catch`
around it catches transport errors only.

### Error bodies are not one format

`401` is JSON with a `code`:

```
{"code":"unknown_key","error":"unknown API key"}
```

`400`, `403`, `404`, `409`, `422` and `501` are plain text. So the common advice not to parse
error message text when a type or code is available is good advice that mostly cannot be followed
here, because for most statuses no code is available.

A client that calls `.json()` on an error path works against an expired key and throws on a
duplicate name.

### A 422 cannot be triaged by status, and neither can a 400

Three distinct causes, one status:

| Cause | Status |
|---|---|
| Missing required field (`source`) | 422 |
| Wrong type (`"cpus":"lots"`) | 422 |
| Over plan quota | 422 |

And the reverse, a well-formed body failing a semantic rule with a **400**:

```
{"network":{"mode":"allowCidrs","cidrs":[]}}
allowCidrs network mode requires at least one CIDR or host
http=400
```

So the status separates a parse failure from a validation failure in neither direction. Read the
body.

### Unauthenticated, every path is 401, including paths that do not exist

`GET /v1/nope` with no credential is 401 with an empty body, not 404. Route probing without a key
tells you nothing, and an empty-bodied 401 cannot be told from a missing route.

### The 403 body names the exact missing scope

```
missing scope: volume:read
http=403
```

That is more useful than the status and more reliable than comparing against `smol auth status`,
because it names what this call needed rather than what the key has.

### Do not use a machine count to detect a failed create

A create that fails after the record exists rolls the record back. `smol cloud deploy` with a bad
image prints `Created: ... (id: mach-...)` and then deletes it, and that id 404s afterwards. Do
not chase the id from a failed deploy, and do not infer a leak from the printed line.

### `x-ratelimit-remaining` exists and is undocumented

It is returned on responses and appears in no reference page. It is the cheapest way to see how
much of the request budget a burst consumed, which matters because the rate limit is the one
documented failure that a healthy account cannot easily provoke.

### A duplicate name is one of the few real 4xx a healthy account produces

Creating a second machine with a name already in use returns 409 with a plain-text body. It is
worth having in a test suite for that reason: most of this API's failure surface needs either a
malformed request or a broken account, and this one needs neither.

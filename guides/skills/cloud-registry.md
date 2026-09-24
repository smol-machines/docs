---
title: "Cloud registry: push an artifact and run a machine from it"
---

# Cloud registry: push an artifact and run a machine from it

Pulls a smolmachine artifact from the smol registry, pushes one into the account's own namespace, and runs a cloud machine from the artifact that was pushed. Use when a task needs a prebuilt artifact rather than an OCI image; when deciding which tag or digest to deploy; when a registry command reports it is not logged in while another one works; or before a first push, because a push cannot be undone. Do not use it to create the artifact from a machine, and do not expect it to remove one, because no shipped tool can delete a pushed artifact.

Verified on **smol v1.14.3** against `registry.smolmachines.com` and smolfleet API 0.1.0, macOS
26.6.2 arm64 client, on 2026-09-10. One pass cost **29 micros (USD 0.00003)** for 2
uptime-seconds. Done means a machine is executing code that came out of the registry write
performed earlier in the same run, proven by reading a value from inside it.

**A push cannot be undone.** No verb in `smol pack` or `smol registry` deletes, and the OCI
manifest delete is refused. Read "What cannot be undone" before pushing anything.

## Procedure

**1. Preflight.** Read-only.

```bash
scripts/preflight.sh
```

It names your tenant namespace, reports the host architecture, and measures the registry verbs
that disagree with each other.

**2. Pull an artifact.** Reads on the `library` namespace need no credential.

```bash
scripts/pull.sh
scripts/pull.sh registry.smolmachines.com/library/alpine:3.20-linux-amd64 ./artifact.smolmachine
```

Tags come in two families: a plain tag such as `3.20` is a multi-arch index, and
`-<os>-<arch>` tags are the concrete builds. The suffix is the only visible architecture signal.

**3. Push into your own namespace.** No `smol registry login` is needed; the cloud API key
authenticates the write.

```bash
scripts/push.sh "registry.smolmachines.com/tenants/<tenant>/smolskill-pack:v1" \
  ./artifact.smolmachine --i-understand-this-cannot-be-undone
```

The script refuses without that flag, because the operation has no inverse. It prints the
**manifest digest**, which is the only immutable handle to what you pushed and the only thing the
console can act on later. One push creates two tags, `v1` and `v1-linux-amd64`.

**4. Run a machine from what you pushed.** This is the step the packet exists for.

```bash
scripts/verify-registry.sh "tenants/<tenant>/smolskill-pack:v1"
```

```
runs_from_artifact=ok (3.20.10)
guest_arch=ok (x86_64)
result=registry_ok
```

The version is read out of the guest's own `/etc/alpine-release`. That is the assertion: it
proves the machine is running the artifact that was pushed rather than a coincidentally named
image.

**5. Clean up.**

```bash
scripts/cleanup.sh --reap
```

The machine deletes normally and returns its settled bill. The artifact does not delete at all.

## What cannot be undone

`smol pack` has create, push, pull and inspect. `smol registry` has ls, catalog, tags, login and
logout. **Neither can delete.** The OCI manifest delete returns
`{"code":"UNSUPPORTED","message":"the operation is unsupported"}` under an HTTP 401.

So a push creates durable, billable storage in the account with no supported way to remove it.
Two consequences for anything built on this packet:

- **Plan the name before the first push, and reuse one tag across runs.** Minting a new tag each
  run accumulates artifacts nobody can remove. Pushing the same content to the same tag changes
  nothing, which is how this packet was verified without adding to the account.
- **The console's registry page is the only candidate remover**, and it was not exercised here.

## Which reference resolves where

| Written as | Through | Resolves to |
|---|---|---|
| `alpine:3.20` | `smol cloud deploy` | your tenant namespace, and 404s |
| `alpine:3.20` | the API's `{"type":"image"}` source | `library/alpine` |
| `library/alpine:3.20-linux-amd64` | either | the official artifact |
| `tenants/<tenant>/name:tag` | the API's `{"type":"smolmachine"}` source | your own artifact |

The `smolmachine` source needs an explicit `"arch"`, because the cloud serves `amd64` and the
client may not be that.

## Security defaults, and why they are the defaults

- **`push.sh` refuses without an explicit confirmation flag.** An irreversible, account-visible
  write should not happen because a script was run with the wrong argument.
- **The manifest digest is captured and printed**, because a tag can be moved and a digest cannot,
  and it is the only handle the console can use.
- **Nothing here logs in to the registry.** The ambient cloud key is enough for push and tags, so
  no second credential is stored on disk.
- **Cleanup deletes only machines this packet recorded.** It cannot and does not touch artifacts.

## Platform arms

- **macOS arm64 client**: verified. Note `smol pack inspect` refuses an `amd64` artifact on an
  `arm64` host, so on a Mac you can push and deploy what you cannot inspect.
- **Linux and Windows clients**: **not run.**

## What was not run

- **Deleting an artifact**, by any route. There is none in the shipped tooling, and the console
  was not exercised.
- **`smol pack create`**, which builds an artifact from an image or a machine snapshot. This
  packet pulls one that already exists.
- **`smol pack inspect`** against a matching-architecture artifact. On this host it refuses.
- **The catalog endpoint.** `smol registry catalog` returns a registry 401 with a normal key.

## Related packets

- `cloud-auth` for the credential and the `Registry` line that names your namespace.
- `cloud-machine` for the lifecycle, the create body and the leak check this reuses.

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
# Read-only. Pulls nothing, pushes nothing, creates no machine.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
command -v smol >/dev/null 2>&1 || { echo "smol_installed=no"; echo "note=the registry verbs are CLI only"; echo "result=blocked"; exit 0; }
echo "smol_installed=yes"

ns=$(smol auth status 2>/dev/null | sed -n 's/^ *Registry *//p')
echo "namespace=${ns:-unknown}"
[ -n "$ns" ] || { echo "note=no Registry line in auth status; the credential is not resolving"; echo "result=blocked"; exit 0; }

echo "host_arch=$(uname -m)"
# `smol pack inspect` refuses an artifact whose arch is not the host's, while the
# cloud runs amd64. On an arm64 host you can push and deploy what you cannot inspect.
case "$(uname -m)" in
  arm64|aarch64) echo "note=cloud guests are amd64; pack inspect will refuse an amd64 artifact on this host, deploy still works";;
esac

# These four verbs disagree about whether you are logged in. Measured without a
# pipe, because a pipe reports the exit status of the last command in it.
for v in ls catalog; do smol registry "$v" >/dev/null 2>&1; echo "registry_${v}_exit=$?"; done
echo "note=registry ls and catalog fail with only SMOL_CLOUD_TOKEN set, while pack push and registry tags succeed"

echo "result=ready"
```

### `scripts/pull.sh`

```bash
#!/usr/bin/env bash
# Pulls a .smolmachine artifact to a local file. Reads on the `library` namespace
# need no credential. Creates nothing on the account and bills nothing.
set -uo pipefail
REF="${1:-registry.smolmachines.com/library/alpine:3.20-linux-amd64}"
OUT="${2:-./artifact.smolmachine}"
command -v smol >/dev/null 2>&1 || { echo "smol_installed=no"; exit 1; }
out=$(smol pack pull "$REF" -o "$OUT" 2>&1); echo "$out" | sed 's/^/  /'
bytes=$(printf '%s' "$out" | sed -n 's/.*(\([0-9]*\) bytes).*/\1/p')
echo "artifact=$OUT bytes=${bytes:-unknown}"
printf '%s' "$out" | grep -q 'Pulled successfully' && echo "result=pulled" || { echo "result=pull_failed"; exit 1; }
```

### `scripts/push.sh`

```bash
#!/usr/bin/env bash
# Pushes a .smolmachine artifact into the account's namespace.
# A PUSH CANNOT BE UNDONE with any shipped tool. Refuses without confirmation.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
REF="${1:-}"; FILE="${2:-}"; CONFIRM="${3:-}"
if [ -z "$REF" ] || [ -z "$FILE" ]; then
  echo "usage: push.sh <registry-reference> <file.smolmachine> --i-understand-this-cannot-be-undone"; exit 2
fi
if [ "$CONFIRM" != "--i-understand-this-cannot-be-undone" ]; then
  echo "refused=yes"
  echo "note=a pushed artifact cannot be deleted by smol pack, smol registry, or an OCI manifest DELETE"
  echo "note=reuse one tag across runs rather than minting a new one; pass the confirmation flag to proceed"
  exit 2
fi
out=$(smol pack push "$REF" -f "$FILE" 2>&1); echo "$out" | sed 's/^/  /'
# The manifest digest is the only immutable handle to what was pushed, and the
# console is the only thing that can remove it. Capture it now or lose it.
echo "manifest=$(printf '%s' "$out" | sed -n 's/.*Manifest: *\(sha256:[0-9a-f]*\).*/\1/p')"
printf '%s' "$out" | grep -q 'Pushed successfully' && echo "result=pushed" || { echo "result=push_failed"; exit 1; }
```

### `scripts/verify-registry.sh`

```bash
#!/usr/bin/env bash
# Runs a cloud machine from an artifact in your namespace and asserts it is that
# artifact, by reading a value out of the guest rather than trusting the name.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
REF="${1:-}"; EXPECT="${2:-3.20.10}"
[ -n "$REF" ] || { echo "usage: verify-registry.sh <tenants/<tenant>/name:tag> [expected-alpine-release]"; exit 2; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

NAME="${PREFIX}reg1"
# The smolmachine source needs an explicit arch: cloud guests are amd64 and the
# client may not be, so the artifact's arch cannot be inferred from this host.
body=$(printf '{"name":"%s","source":{"type":"smolmachine","reference":"%s","arch":"amd64"},"resources":{"cpus":1,"memoryMb":256},"network":{"mode":"open"}}' "$NAME" "$REF")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
[ -n "$id" ] || { echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; exit 1; }
record "$id"; echo "machine_id=$id"
api POST "/v1/machines/$id/start" '{}' >/dev/null

deadline=$(( $(date +%s) + 120 ))
rel=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  rel=$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","cat /etc/alpine-release"]}' | jget stdout | tr -d '\n')
  [ -n "$rel" ] && break
  sleep 3
done
check runs_from_artifact "$EXPECT" "$rel"
check guest_arch x86_64 "$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","uname -m"]}' | jget stdout | tr -d '\n')"
[ "$fails" -eq 0 ] && echo "result=registry_ok" || echo "result=registry_failed"
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

Reproduced on smol v1.14.3 against `registry.smolmachines.com` on 2026-09-10 unless an item says
otherwise.

### A pushed artifact cannot be removed with any shipped tool

`smol pack` has create, push, pull, inspect. `smol registry` has ls, catalog, tags, login,
logout. Neither deletes. The OCI manifest delete is refused:

```
DELETE https://registry.smolmachines.com/v2/tenants/<tenant>/<name>/manifests/sha256:...
{"code":"UNSUPPORTED","message":"the operation is unsupported"}
http=401
```

The status says "authenticate" and the body says "this operation does not exist", so a client
doing the correct thing for a 401 and retrying with fresh credentials will never succeed.

The push command's own closing line is *"Registered in your catalog"*: it creates durable state
in the account and offers no way to undo it, while every other resource in this product family
has a delete. **Plan the name, and reuse one tag across runs.**

### The registry verbs disagree about whether you are logged in

With only `SMOL_CLOUD_TOKEN` set, in the same shell, same second:

| Command | Result |
|---|---|
| `smol pack push` | **succeeds** |
| `smol registry tags` | **succeeds**, exit 0 |
| `smol registry ls` | `No registries configured. Log in with: smol registry login`, exit 0 |
| `smol registry catalog` | registry `401 UNAUTHORIZED`, exit 1 |

`ls` lists *stored credentials* and the push uses the ambient token, so this behaves as built,
but the wording tells you to perform a login you demonstrably do not need. **Do not conclude from
`registry ls` that a push will fail.**

### Measure exit codes without a pipe, and mind your shell

`smol registry catalog | head` reports `head`'s status, which is 0 while the command underneath
failed. Measured directly, `catalog` exits 1 and `tags` exits 0.

A second way to get this wrong, hit twice while writing this packet: **zsh does not word-split an
unquoted parameter and bash does.** `v="registry ls"; smol $v` runs `smol "registry ls"` in zsh,
one argument, and reports a usage error whose exit code has nothing to do with the registry. The
scripts here have a `bash` shebang for that reason.

### `smol pack inspect` takes a registry reference, not a local file

Passing a local `.smolmachine` path gets it treated as a reference and produces a bare registry
`401 UNAUTHORIZED`, which reads like a credential problem rather than a usage error. Compare
`smol registry tags` on a missing repository, which correctly says `Error: blob not found: ...`.

### `smol pack inspect` refuses an artifact whose architecture is not the host's

From an arm64 Mac against the amd64 artifact:

```
invalid manifest: no linux/arm64 build available for this machine;
the registry has: linux/amd64
```

So you cannot read the metadata of an artifact you cannot run, even though deploying that same
reference works, because the cloud is amd64. On a Mac, push and deploy are available and inspect
is not.

### Tags come in two families

```
smol registry tags registry.smolmachines.com/library/alpine
3.20
3.20-linux-amd64
latest
latest-linux-amd64
```

A plain tag is a multi-arch index; `-<os>-<arch>` is a concrete build. The suffix is the only
visible architecture signal, and the catalog endpoint that might have told you more is
unavailable to a normal key.

### A bare reference means different things to the CLI and the API

`smol cloud deploy alpine:3.20` resolves under your tenant namespace and 404s. The API's
`{"type":"image","reference":"alpine:3.20"}` resolves to `library/`. Same string, two resolvers.

### The `smolmachine` source needs an explicit arch

```json
{"source":{"type":"smolmachine","reference":"tenants/<tenant>/name:tag","arch":"amd64"}}
```

Cloud guests are `amd64`. The client may not be, so the artifact's architecture cannot be
inferred from the host that is making the call.

### Capture the manifest digest at push time

```
Manifest: sha256:758bc14a6e65d4437a387d2cd2eced960c852966aa6361f6553fdd9a6a4e3026
```

A tag can be moved; a digest cannot. Since nothing in the CLI can delete or list by digest
afterwards, the push output is the one moment this handle is offered.

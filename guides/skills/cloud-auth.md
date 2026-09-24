---
title: "Cloud auth: point an agent at a cloud account and prove it"
---

# Cloud auth: point an agent at a cloud account and prove it

Points the smol CLI and raw HTTP at a smol cloud account with an API key, and proves one authenticated call reaches it before any other work starts. Use when setting an agent up against smol cloud for the first time; when a call returns 401 and it is unclear whether the key, the tenant or the API is at fault; when choosing between the SMOL_CLOUD_TOKEN environment variable and a persisted CLI config; or when checking which scopes a key carries before a task that needs one. Do not use it to create an account or mint a key, which are human steps in the console, and do not use it to create or run machines, which later packets cover.

Verified on **smol v1.14.3** and **smolfleet API 0.1.0** (`apiVersion` 2), macOS 26.6.2 arm64,
against `https://api.smolmachines.com` on 2026-09-10. Done means the account body reports
`status: active`, a machine list comes back as a list, and the CLI agrees with raw HTTP.

This is the first packet. Every other cloud packet assumes it has passed.

**A key is a human handover.** Accounts are created and keys are minted in the console by a
person, who hands the key to the agent. Nothing here creates either.

## Procedure

**1. Preflight.** Read-only: creates no machine, writes no config, bills nothing.

```bash
scripts/preflight.sh
```

It reports `key=value` lines and ends with `result=ready` or `result=blocked`. It checks the API
**before** presenting a credential, which is what separates the three failures that all look
alike from a 401: the API is unreachable, no credential is configured, or the key is bad.

**2. Give the CLI and the API a credential.** Two routes, and they are not interchangeable.

```bash
# Route A, the environment. Nothing is written to disk.
export SMOL_CLOUD_TOKEN="smk_..."

# Route B, persisted CLI config. Written to ~/.config/smolvm/config.toml, mode 600.
smol config set cloud.api_key smk_...
```

Route A is the one to prefer for an agent or a CI job: it leaves nothing behind and it is the
only route raw HTTP can use. **Route B does not reach `curl`**, so a packet that mixes CLI and
HTTP steps needs the environment variable regardless.

**3. Prove it.**

```bash
scripts/verify-auth.sh
```

```
account_status=ok (active)
tenant_id=ok (present)
http_machine_list=ok (list of 0)
cli_machine_list=ok (reachable)
cli_auth_text=ok (Logged in)
result=auth_ok
```

Both surfaces are checked because the CLI and raw HTTP are different code paths. The account
body is asserted by value, because a well-formed key against a suspended tenant still returns a
200 from some routes.

**4. Read the scopes before planning the work.**

```bash
smol auth status
```

The `Access` line is the scope list and is the cheapest way to find out that a later task cannot
pass. The account this packet was verified on carries
`machine:create, machine:read, machine:exec, machine:delete, machine:files` and no volume,
usage or admin scope.

There is no cleanup step. **This packet creates nothing on the account**, so nothing bills and
nothing has to be deleted. To undo route B, `smol config set cloud.api_key ""`.

## What the preflight reports

| key | meaning |
|---|---|
| `smol_installed`, `smol_version` | whether the CLI is on `PATH` and what it reports |
| `version_status` | `match`, `newer`, `older` or `unknown` against the version this packet was verified on |
| `api_reachable`, `api_version`, `api_nodes_ready` | from `/health`, the only route that answers without a key |
| `credential_source` | `env`, `cli_config` or `none` |
| `account_readable` | `yes` over HTTP, `via_cli` when the key is only in the CLI config |
| `tenant_status` | `active` or the tenant's real state |
| `result` | `ready` or `blocked` |

`version_status=newer` is a warning, not a failure. The CLI's flags and messages move every
release, so on a newer binary check each step's output against the binary before trusting the
text here.

## Security defaults, and why they are the defaults

- **`SMOL_CLOUD_TOKEN` is preferred because it writes nothing to disk.** An agent that is handed
  a key for one task should not leave it in a config file that outlives the task. When route B is
  used anyway, the CLI writes `~/.config/smolvm/config.toml` at mode 600, which is correct.
- **Nothing here prints the key**, and neither should anything built on it. Both scripts read the
  credential from the environment and never echo it, because a key reaches a transcript once and
  stays there.
- **A key belongs in a mode-600 file outside every repository**, and the path is what gets handed
  around, not the value. Rotate it when the session that used it ends.
- **Read the `Access` line rather than assuming a scope.** A key that cannot do the task fails
  late and confusingly; the scope list costs one command.
- **The API rejects every path without a credential, including paths that do not exist**, so a
  404 cannot be told from a 401 while unauthenticated. Only `/health` answers.

## Platform arms

- **macOS arm64**: verified, both credential routes, on smol v1.14.3.
- **Linux and Windows**: **not run.** The HTTP half of this packet is `curl` and a URL and
  depends on nothing platform specific; the CLI half was not executed there.

## What was not run

- **`smol auth login`.** This packet authenticates with an API key and never drives a sign-in.
  See `references/traps.md` for why that command is not the account login its own hint suggests.
- **Account creation and key minting.** Human steps in the console, by design.
- **A suspended tenant.** `tenant_status` is asserted against `active` and the failure path was
  exercised with a malformed key, not with a real suspension, which cannot be provoked here.
- **Linux and Windows**, as above.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Reports whether this host can reach smol cloud and whether a credential works.
# Read-only: creates no machine, writes no config, bills nothing.
# Never prints the key. Every line is key=value; the last line is result=.
set -uo pipefail

VERIFIED_CLI="1.14.3"
VERIFIED_API="0.1.0"
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
notes=()

# --- the CLI -----------------------------------------------------------------
if command -v smol >/dev/null 2>&1; then
  echo "smol_installed=yes"
  ver=$(smol --version 2>/dev/null | awk '{print $2}')
  echo "smol_version=${ver:-unknown}"
  if [ "$ver" = "$VERIFIED_CLI" ]; then echo "version_status=match"
  elif [ -z "$ver" ]; then echo "version_status=unknown"
  else
    # Sort tells us which side is newer without a version-compare dependency.
    newest=$(printf '%s\n%s\n' "$ver" "$VERIFIED_CLI" | sort -V | tail -1)
    [ "$newest" = "$VERIFIED_CLI" ] && echo "version_status=older" || echo "version_status=newer"
    notes+=("note=this packet was verified on smol $VERIFIED_CLI; check each step's output against your binary")
  fi
else
  echo "smol_installed=no"; echo "smol_version=none"; echo "version_status=unknown"
  notes+=("note=the smol CLI is not on PATH; the HTTP half of this packet still works")
fi
echo "verified_cli=$VERIFIED_CLI"

# --- the API, before any credential is presented ------------------------------
# /health is the only unauthenticated route: it separates "the API is down" from
# "your key is wrong", which no status code on a 401-everything API can do.
health=$(curl -fsS --max-time 20 "$API/health" 2>/dev/null)
if [ -n "$health" ]; then
  echo "api_reachable=yes"
  echo "api_version=$(printf '%s' "$health" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  echo "api_nodes_ready=$(printf '%s' "$health" | sed -n 's/.*"nodesReady":\([0-9]*\).*/\1/p')"
else
  echo "api_reachable=no"; echo "api_version=unknown"; echo "api_nodes_ready=0"
  notes+=("note=$API/health did not answer; this is the API or your network, not your key")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi
echo "verified_api=$VERIFIED_API"

# --- the credential -----------------------------------------------------------
if [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then
  echo "credential_source=env"
elif command -v smol >/dev/null 2>&1 &&
     smol config show 2>/dev/null | grep 'cloud.api_key' | grep -qv '(not set)'; then
  echo "credential_source=cli_config"
  notes+=("note=the key is persisted on disk; SMOL_CLOUD_TOKEN leaves nothing behind")
else
  echo "credential_source=none"
  notes+=("note=set SMOL_CLOUD_TOKEN, or run: smol config set cloud.api_key <key>")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi

# Assert a value out of the account body, on whichever surface holds the key.
# A 200 alone does not prove the tenant is usable, and `smol auth status` cannot
# be gated on at all (see references/traps.md).
status=""
if [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then
  acct=$(curl -fsS --max-time 25 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/account" 2>/dev/null)
  if [ -n "$acct" ]; then
    echo "account_readable=yes"
    status=$(printf '%s' "$acct" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    echo "plan=$(printf '%s' "$acct" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
  else
    echo "account_readable=no"
    notes+=("note=the API answered /health but refused /v1/account; the key is wrong, expired or revoked")
  fi
else
  # The key is in the CLI config, so the HTTP half of this packet cannot use it.
  # Prove the credential through the CLI instead, by value and not by exit code.
  echo "account_readable=via_cli"
  status=$(smol auth status 2>/dev/null | sed -n 's/.*(tenant-[^,]*, \([a-z]*\)).*/\1/p')
  notes+=("note=the HTTP steps in this packet need SMOL_CLOUD_TOKEN as well; the CLI config is not read by curl")
fi
echo "tenant_status=${status:-unknown}"

[ "$status" = "active" ] || notes+=("note=the tenant is not active or could not be read; calls that create machines will refuse")

[ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
[ "$status" = "active" ] && echo "result=ready" || echo "result=blocked"
```

### `scripts/verify-auth.sh`

```bash
#!/usr/bin/env bash
# Proves the credential reaches the account on both surfaces.
# Read-only: creates no machine, bills nothing. Never prints the key.
# Each check prints ok or FAIL with what was expected; exit is non-zero if any failed.
set -uo pipefail

API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
fails=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "$1=ok ($3)"
  else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi
}

if [ -z "${SMOL_CLOUD_TOKEN:-}" ]; then
  echo "credential=FAIL expected=SMOL_CLOUD_TOKEN set actual=unset"
  echo "result=cannot_verify"; exit 1
fi

acct=$(curl -fsS --max-time 25 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/account" 2>/dev/null)
check account_status active "$(printf '%s' "$acct" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"

# A tenant id proves the body is this account's, not a generic 200.
tenant=$(printf '%s' "$acct" | sed -n 's/.*"tenantId":"\(tenant-[^"]*\)".*/\1/p')
[ -n "$tenant" ] && echo "tenant_id=ok (present)" || { echo "tenant_id=FAIL expected=tenant-... actual=absent"; fails=$((fails+1)); }

# The machine list is the call that a well-formed but dead key cannot satisfy.
# Assert it parses as a list, not that it is empty: the account may be in use.
list=$(curl -fsS --max-time 25 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/machines" 2>/dev/null)
if printf '%s' "$list" | grep -q '^\['; then
  echo "http_machine_list=ok (list of $(printf '%s' "$list" | grep -o '"id"' | wc -l | tr -d ' '))"
else
  echo "http_machine_list=FAIL expected=a JSON array actual=${list:0:60}"; fails=$((fails+1))
fi

# The CLI is a different code path from raw HTTP and can disagree; check both.
if command -v smol >/dev/null 2>&1; then
  if smol cloud ls >/dev/null 2>&1; then echo "cli_machine_list=ok (reachable)"
  else echo "cli_machine_list=FAIL expected=exit 0 actual=exit 1"; fails=$((fails+1)); fi
  # Assert the text, never `smol auth status`'s exit code: it is 0 logged out.
  if smol auth status 2>/dev/null | grep -q 'Logged in'; then echo "cli_auth_text=ok (Logged in)"
  else echo "cli_auth_text=FAIL expected=Logged in actual=not logged in"; fails=$((fails+1)); fi
else
  echo "cli_machine_list=skipped (smol not on PATH)"
  echo "cli_auth_text=skipped (smol not on PATH)"
fi

[ "$fails" -eq 0 ] && echo "result=auth_ok" || echo "result=auth_failed"
[ "$fails" -eq 0 ]
```

## Traps, with the observation behind each

Every item was reproduced on smol v1.14.3 against smolfleet API 0.1.0 on 2026-09-10 unless the
item says otherwise.

### `smol auth status` exits 0 when you are not logged in

It prints `Not logged in.` and a remediation hint, and returns 0. `smol cloud ls` exits 1 in the
same state. So a preflight shaped `smol auth status && run_the_job` walks straight into an
unauthenticated run.

```
smol auth status >/dev/null 2>&1; echo $?    # 0, logged out
smol cloud ls    >/dev/null 2>&1; echo $?    # 1, same state
```

**Gate on the text, or on `smol cloud ls`.** `verify-auth.sh` asserts the string `Logged in`
rather than the exit code, which is the general rule for this product: assert the value, never
the status.

Note the shape of the mistake, because it recurs. Capturing the exit code through a pipe
(`smol auth status | head -3; echo $?`) reports the exit code of `head`, which is 0 whatever the
CLI did. Redirect to a file and read `$?` from the command itself.

### `smol config show` lists keys that are not set, by name

```
cloud.endpoint = (not set)
cloud.api_key  = (not set)
```

A script that greps the output for `cloud.api_key` matches the label and concludes a credential
exists on a host that has none. `preflight.sh` greps for the line and then excludes `(not set)`.

### The environment variable is `SMOL_CLOUD_TOKEN`, not `SMOL_API_KEY`

The CLI does not read `SMOL_API_KEY`. With it set and nothing else configured, every cloud verb
fails as if no credential were present:

```
smol cloud ls
Error: list machines: not authenticated (401 Unauthorized). Run `smol auth login` to re-authenticate.
```

which names a command that does not fix it. See the next item.

### `smol auth login` is not the account login its own hint advertises

`smol auth status` says `Log in with your account: smol auth login`, and
`smol auth login --help` describes itself as *"Log in to a registry"*, taking only `--registry`,
`--token`, `--token-stdin` and `--no-browser`. For a cloud API credential the routes are
`SMOL_CLOUD_TOKEN` or `smol config set cloud.api_key`. No command output says that the cloud
credential and the registry credential are separate things, which is what the `Access` and
`Registry` lines of `auth status` imply.

### A persisted CLI key does not reach `curl`

`smol config set cloud.api_key` writes `~/.config/smolvm/config.toml` (mode 600, and note the
directory is `smolvm`, shared with the local engine). Nothing reads that file except the CLI, so
a procedure that mixes CLI and HTTP steps needs `SMOL_CLOUD_TOKEN` as well. `preflight.sh`
reports `account_readable=via_cli` in that state and says so rather than reporting a bad key.

### The API 401s every path, including ones that do not exist

`GET /v1/nope` unauthenticated returns 401, not 404, with an empty body. So the route surface
cannot be probed without a credential, and a 401 never distinguishes "wrong key" from "no such
route". This is correct behaviour and worth knowing before concluding a route is missing.

### `/health` is the only unauthenticated route, and it is the best preflight available

```
curl -fsS https://api.smolmachines.com/health
{"clusterId":"...","version":"0.1.0","apiVersion":2,
 "capabilities":["machine.branch","machine.branch_batch","machine.branch_source_continues",
                 "machine.lineage","machine.portable_checkpoint"],
 "nodesTotal":4,"nodesReady":4,"groupsTotal":0,"poolsTotal":0,"uptimeSecs":92947}
```

Every other path probed returns 401 with an empty body, including `/v1/health`, `/openapi.json`
and `/`. Because `/health` answers without a credential, it is what lets a preflight say "the API
is reachable and your key is wrong" instead of "something returned 401".

Two cautions on reading it. **An advertised capability is not a working one**: the list above is
what the cluster reports, not what has been exercised. And `uptimeSecs` is the cluster's, so a
low value means a recent deployment, which is a reason to re-verify rather than trust a stamp.

### The generated OpenAPI is on the website host, not the API host

`https://smolmachines.com/openapi.json` returns 200 with 44 paths and reports
`smolfleet API 0.1.0`. `https://api.smolmachines.com/openapi.json` returns 401. A reader who has
just been told the base URL is `api.smolmachines.com` will try it there and conclude the spec is
gone.

### Scopes are visible and worth reading first

```
Access     machine:create, machine:read, machine:exec, machine:delete, machine:files
```

The account behind this packet has no volume, usage or admin scope. A task that needs one of
those fails at the call, not at authentication, so the scope list is the cheapest early warning.

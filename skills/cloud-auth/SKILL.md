---
name: "cloud-auth"
description: "Points the smol CLI and raw HTTP at a smol cloud account with an API key, and proves one authenticated call reaches it before any other work starts. Use when setting an agent up against smol cloud for the first time; when a call returns 401 and it is unclear whether the key, the tenant or the API is at fault; when choosing between the SMOL_CLOUD_TOKEN environment variable and a persisted CLI config; or when checking which scopes a key carries before a task that needs one. Do not use it to create an account or mint a key, which are human steps in the console, and do not use it to create or run machines, which later packets cover."
---

# Authenticating against smol cloud

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

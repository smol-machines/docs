---
name: "cloud-errors"
description: "Provokes every failure the smol cloud API can return and shows what a client must branch on, including the failures that arrive as HTTP 200. Use when writing a client, harness or agent tool against the cloud API; when a call succeeded by status but the work did not happen; when a 422 needs to be told apart from a schema bug, a wrong type and a quota refusal; or when deciding which failures are safe to retry. Do not use it to drive a normal machine lifecycle, which is the cloud-machine packet, and do not expect it to cover billing suspension or rate limiting, which cannot be provoked on a healthy account."
---

# Every failure this API returns, on purpose

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

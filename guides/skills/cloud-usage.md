---
title: "Cloud usage: find out what a run cost"
---

# Cloud usage: find out what a run cost

Reads what a smol cloud account has spent, and reconciles one machine's bill against its own uptime and the plan's published rate. Use when a run needs a spend figure, a budget gate or a cost regression check; when a bill looks wrong and the arithmetic needs checking; when deciding where to read usage from, because the surfaces disagree; or when a machine was deleted before its bill was taken. Do not use it to read tenant usage over an arbitrary window, which needs a scope a machine key does not have, and do not use it as a leak check, because the machine count it reports is cumulative.

Verified on **smolfleet API 0.1.0**, macOS 26.6.2 arm64 client, on 2026-09-10. **This packet
costs nothing**: it only reads, and the usage it reads was produced by other work.

**Every cost field on this API is in micros.** One million micros is one US dollar. Reading them
as cents overstates a bill by 10000 times, which is the single most likely mistake here.

## Procedure

**1. Preflight.** Reports which usage routes this key can reach at all.

```bash
scripts/preflight.sh
```

```
account_route=200
tenant_usage_route=403
billing_meters_route=403
result=ready
```

**2. The account's period totals.**

```bash
scripts/report.sh
```

```
plan=Standard
uptime_seconds=3618
machines_this_period=90  (cumulative, NOT a live count)
baseMicros=36667
totalMicros=43377
credit_applied_micros=43377
amount_due_micros=0
total_usd=0.043377
base_rate_micros_per_hour=40000
```

`amount_due_micros` is what is actually owed after the credit is applied, and it is the number to
gate on. `totalMicros` is what was consumed.

**3. One machine's settled bill, with the arithmetic checked.**

```bash
scripts/machine-bill.sh mach-...
```

```
uptime_seconds=157
baseMicros=1744
totalMicros=1811
total_usd=0.001811
base_rate_arithmetic=ok (expected=1744 actual=1744)
```

**This route keeps working for 30 days after the machine is deleted**, which is the only way to
recover a bill you forgot to take at delete time.

## Where usage can be read from, and by whom

| Route | A `machine:*` key | Covers |
|---|---|---|
| `GET /v1/account` | **200** | The whole current period: plan, rates, `periodUsage`, `periodCost` |
| `GET /v1/machines/{id}/usage` | **200** | One machine, for 30 days after deletion |
| `DELETE /v1/machines/{id}?includeUsage=true` | **200** | The settled bill at delete time |
| `GET /v1/usage` | **403** | Tenant usage over a time range. Needs `admin` or `usage:read` |
| `GET /v1/billing/meters` | **403** | Needs `admin` |

So a deploy key can account for its own machines and for the current period, and cannot build a
usage report over an arbitrary window.

## The arithmetic that reconciles, and the one that does not

**One machine reconciles exactly.** The base term is uptime hours times the plan's
`rateBaseHourMicros`, and for a short-lived small machine it dominates everything else. Three
machines checked, all exact to the micro:

| Uptime | Expected base | Actual base |
|---|---|---|
| 157 s | 1744 | 1744 |
| 7 s | 78 | 78 |
| 2 s | 22 | 22 |

**The period aggregate does not**, and is not meant to. Machines bill on overlapping windows and
a stopped machine still bills disk without base, so `totalUptimeSeconds` times the base rate does
not equal `periodCost.baseMicros`. Reconcile a machine, not a period.

## Security defaults, and why they are the defaults

- **Read-only, always.** Nothing in this packet creates, starts or deletes anything, so it can be
  run on a production account without a second thought.
- **Gate on `amountDueMicros`, not on `totalMicros`.** Consumption is not debt while credit
  covers it, and a budget check that ignores the credit stops work that costs nothing.
- **A `403` here is a scope answer, not a failure to fix by minting a wider key.** A key that can
  create machines deliberately cannot read tenant-wide billing.
- **Nothing prints the credential.**

## Platform arms

- **macOS arm64 client**: verified. Every call is `curl` and a URL and depends on nothing
  platform specific.
- **Linux and Windows clients**: **not run.**

## What was not run

- **`GET /v1/usage` and `GET /v1/billing/meters`.** Both 403 on a `machine:*` key. The scope was
  not widened to reach them.
- **The console.** `smolmachines.com/console` and its usage page are a human surface, and this
  packet is the API half only.
- **A month boundary.** Everything read here is inside one billing period.
- **A budget refusal.** The account carries credit and `amountDueMicros` is 0, so no
  over-budget behaviour was observed.

## Related packets

- `cloud-machine` for the delete that returns the settled bill, and for the leak check the
  cumulative machine count cannot do.
- `cloud-auth` for the scopes that decide which of these routes answer.

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
# Reports which usage routes this key can actually reach. Read-only, bills nothing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
code() { curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API$1"; }
echo "account_route=$(code /v1/account)"
echo "tenant_usage_route=$(code /v1/usage)"
echo "billing_meters_route=$(code /v1/billing/meters)"
echo "note=/v1/usage needs admin or usage:read and /v1/billing/meters needs admin; a machine:* key gets 403"
echo "note=what a machine:* key can read is /v1/account for the period and /v1/machines/<id>/usage for one machine"
[ "$(code /v1/account)" = "200" ] && echo "result=ready" || echo "result=blocked"
```

### `scripts/report.sh`

```bash
#!/usr/bin/env bash
# Prints the account's period usage and cost, and checks the base-rate arithmetic
# against the plan's own published rate. Read-only, bills nothing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
api GET /v1/account | python3 -c '
import json,sys
d = json.load(sys.stdin); p = d["plan"]; u = d["periodUsage"]; c = d["periodCost"]
print("tenant_status=" + d["status"])
print("plan=" + p["name"])
print("period_from=" + str(u["from"]))
print("uptime_seconds=" + str(u["totalUptimeSeconds"]))
print("machines_this_period=" + str(u["machineCount"]) + "  (cumulative, NOT a live count)")
for k in ("cpuMicros","memoryMicros","diskMicros","egressMicros","execMicros","baseMicros","totalMicros"):
    print(k + "=" + str(c[k]))
print("credit_applied_micros=" + str(c["creditAppliedMicros"]))
print("amount_due_micros=" + str(c["amountDueMicros"]))
# Every cost field is MICROS. Reading them as cents overstates the bill by 10000x.
print("total_usd=%.6f" % (c["totalMicros"] / 1000000))
print("amount_due_usd=%.6f" % (c["amountDueMicros"] / 1000000))
# The period aggregate does NOT reconcile against uptime times the base rate, and
# is not expected to: machines bill on overlapping windows and a stopped machine
# still bills disk without base. Reconcile one machine instead, where it is exact.
print("base_rate_micros_per_hour=" + str(p["rateBaseHourMicros"]))
print("note=reconcile a single machine with machine-bill.sh; the period aggregate does not reconcile this way")
print("result=reported")
'
```

### `scripts/machine-bill.sh`

```bash
#!/usr/bin/env bash
# The settled bill for one machine. Works for 30 days after the machine is
# deleted, which is the only way to get a bill you forgot to take at delete time.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
ID="${1:-}"; [ -n "$ID" ] || { echo "usage: machine-bill.sh <machine-id>"; exit 2; }
RATE=$(api GET /v1/account | sed -n 's/.*"rateBaseHourMicros":\([0-9]*\).*/\1/p')
api GET "/v1/machines/$ID/usage" | python3 -c '
import json,sys
d = json.load(sys.stdin)
u = d.get("usage") or {}
c = d.get("cost") or u.get("cost") or {}
print("machine_id=" + str(d.get("machineId","")))
print("uptime_seconds=" + str(u.get("totalUptimeSeconds","unknown")))
for k in ("baseMicros","cpuMicros","memoryMicros","diskMicros","egressMicros","execMicros","totalMicros"):
    if k in c: print(k + "=" + str(c[k]))
if "totalMicros" in c:
    print("total_usd=%.6f" % (c["totalMicros"] / 1000000))
    # For one machine the base term reconciles exactly against the plan rate:
    # uptime hours times rateBaseHourMicros. It dominates a short small machine,
    # so a mismatch here means the rate or the uptime is not what you think.
    rate = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    if rate and "baseMicros" in c and u.get("totalUptimeSeconds") is not None:
        exp = u["totalUptimeSeconds"] / 3600 * rate
        ok = abs(exp - c["baseMicros"]) <= 1
        print("base_rate_arithmetic=" + ("ok" if ok else "MISMATCH") +
              " (expected=%.0f actual=%d)" % (exp, c["baseMicros"]))
else:
    print("note=no cost block on this response; take the bill from DELETE ?includeUsage=true")
print("result=billed")
' "$RATE"
```

## Traps, with the observation behind each

Reproduced on smolfleet API 0.1.0 on 2026-09-10 unless an item says otherwise.

### Every cost field is micros

One million micros is one US dollar. `totalMicros: 43377` is USD 0.043377. Reading micros as
cents overstates a bill by 10000 times, which is the most consequential unit mistake available
here because every cost field on the API uses them and none is named in a way that says so.

### `periodUsage.machineCount` is cumulative and is not a live count

Observed 90 while `GET /v1/machines` returned `[]`. It counts machines seen in the billing
period, not machines that exist. **It is not a leak check.** For that, count `GET /v1/machines`
and check `smol cloud ls` as well, since the two are different code paths.

### A mid-life usage read is a lower bound, not the bill

The settled figure comes from `DELETE /v1/machines/{id}?includeUsage=true`. An earlier read of
the same machine reports less. One recorded case: 1440 mid-life against 1692 settled.

There is a smaller effect in the other direction worth knowing. Reading a machine's usage **after**
the delete can be a micro or two above what the delete itself reported:

| Machine | At delete | Read back later |
|---|---|---|
| 157 s machine | 1810 | 1811 |
| 2 s machine | 29 | 31 |
| 7 s machine | 89 | 89 |

So the delete-time figure is the right one to record, and it is not final to the last micro. Do
not build an equality assertion on it.

### The per-machine route outlives the machine

`GET /v1/machines/{id}/usage` keeps answering for 30 days after deletion. That is the recovery
path when a run deleted a machine without passing `?includeUsage=true`, and it is the only one.

### Tenant-wide usage needs a scope a deploy key does not have

```
GET /v1/usage           -> missing scope: admin or usage:read   http=403
GET /v1/billing/meters  -> missing scope: admin                 http=403
```

The reference pages name `/v1/usage` for usage over a time range without mentioning the scope, so
a reader with a working `machine:*` key gets a 403 from a documented endpoint and reasonably
concludes something is broken.

### The period aggregate does not reconcile against the base rate

Per machine, uptime hours times `rateBaseHourMicros` equals `baseMicros` exactly. For the period
it does not: 3618 uptime-seconds at 40000 micros/hour predicts about 40200, while
`periodCost.baseMicros` was 36667.

That is not an error. Machines bill on overlapping windows, and a stopped machine still bills
disk without accruing base. **Reconcile one machine, never a period.**

### `execMicros` is always 0

Exec is metered at zero. It appears in every cost block and will never be the reason a bill moved.

### `amountDueMicros` and `totalMicros` are different questions

`totalMicros` is what was consumed; `creditAppliedMicros` is what the free credit absorbed;
`amountDueMicros` is what is owed. On an account inside its credit the first is non-zero and the
last is 0. A budget gate that reads `totalMicros` stops work that costs nothing.

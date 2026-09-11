---
name: "cloud-usage"
description: "Reads what a smol cloud account has spent, and reconciles one machine's bill against its own uptime and the plan's published rate. Use when a run needs a spend figure, a budget gate or a cost regression check; when a bill looks wrong and the arithmetic needs checking; when deciding where to read usage from, because the surfaces disagree; or when a machine was deleted before its bill was taken. Do not use it to read tenant usage over an arbitrary window, which needs a scope a machine key does not have, and do not use it as a leak check, because the machine count it reports is cumulative."
---

# What this account has spent

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

# Traps, with the observation behind each

Reproduced on smolfleet API 0.1.0 on 2026-09-10 unless an item says otherwise.

## Every cost field is micros

One million micros is one US dollar. `totalMicros: 43377` is USD 0.043377. Reading micros as
cents overstates a bill by 10000 times, which is the most consequential unit mistake available
here because every cost field on the API uses them and none is named in a way that says so.

## `periodUsage.machineCount` is cumulative and is not a live count

Observed 90 while `GET /v1/machines` returned `[]`. It counts machines seen in the billing
period, not machines that exist. **It is not a leak check.** For that, count `GET /v1/machines`
and check `smol cloud ls` as well, since the two are different code paths.

## A mid-life usage read is a lower bound, not the bill

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

## The per-machine route outlives the machine

`GET /v1/machines/{id}/usage` keeps answering for 30 days after deletion. That is the recovery
path when a run deleted a machine without passing `?includeUsage=true`, and it is the only one.

## Tenant-wide usage needs a scope a deploy key does not have

```
GET /v1/usage           -> missing scope: admin or usage:read   http=403
GET /v1/billing/meters  -> missing scope: admin                 http=403
```

The reference pages name `/v1/usage` for usage over a time range without mentioning the scope, so
a reader with a working `machine:*` key gets a 403 from a documented endpoint and reasonably
concludes something is broken.

## The period aggregate does not reconcile against the base rate

Per machine, uptime hours times `rateBaseHourMicros` equals `baseMicros` exactly. For the period
it does not: 3618 uptime-seconds at 40000 micros/hour predicts about 40200, while
`periodCost.baseMicros` was 36667.

That is not an error. Machines bill on overlapping windows, and a stopped machine still bills
disk without accruing base. **Reconcile one machine, never a period.**

## `execMicros` is always 0

Exec is metered at zero. It appears in every cost block and will never be the reason a bill moved.

## `amountDueMicros` and `totalMicros` are different questions

`totalMicros` is what was consumed; `creditAppliedMicros` is what the free credit absorbed;
`amountDueMicros` is what is owed. On an account inside its credit the first is non-zero and the
last is 0. A budget gate that reads `totalMicros` stops work that costs nothing.

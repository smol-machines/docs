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

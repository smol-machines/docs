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

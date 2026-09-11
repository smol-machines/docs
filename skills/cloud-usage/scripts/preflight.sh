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

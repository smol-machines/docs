#!/usr/bin/env bash
# Read-only. Creates no machine and bills nothing. Never prints the key.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

health=$(curl -fsS --max-time 20 "$API/health" 2>/dev/null)
[ -n "$health" ] && echo "api_reachable=yes" || { echo "api_reachable=no"; echo "result=blocked"; exit 0; }
echo "api_version=$(printf '%s' "$health" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"

acct=$(api GET /v1/account)
status=$(printf '%s' "$acct" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
echo "tenant_status=${status:-unknown}"
echo "max_machines=$(printf '%s' "$acct" | sed -n 's/.*"effectiveMaxMachines":\([0-9]*\).*/\1/p')"

# Scopes decide whether the lifecycle can complete at all, and they fail late otherwise.
if command -v smol >/dev/null 2>&1; then
  scopes=$(smol auth status 2>/dev/null | sed -n 's/.*Access *//p')
  echo "scopes=${scopes:-unknown}"
  for need in machine:create machine:read machine:exec machine:delete; do
    case "$scopes" in *"$need"*) ;; *) echo "note=this key lacks $need; the lifecycle cannot complete";; esac
  done
else
  echo "scopes=unknown (smol not on PATH)"
fi

# A live count, because periodUsage.machineCount is cumulative for the period.
live=$(api GET /v1/machines | grep -o '"id"' | wc -l | tr -d ' ')
echo "machines_live_now=$live"
echo "recorded_by_this_packet=$( [ -f "$IDFILE" ] && wc -l < "$IDFILE" | tr -d ' ' || echo 0)"

[ "$status" = "active" ] && echo "result=ready" || echo "result=blocked"

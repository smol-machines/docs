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

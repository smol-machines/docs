#!/usr/bin/env bash
# Deletes only the machines this packet recorded, takes the settled bill from the
# delete, and proves both surfaces are clean. --reap also removes any machine
# carrying this packet's name prefix, for a run that threw before recording.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
CEILING_MICROS="${SMOLSKILL_CEILING_MICROS:-1000000}"   # USD 1, asserted below

total=0
if [ -f "$IDFILE" ]; then
  while read -r id; do
    [ -n "$id" ] || continue
    # ?includeUsage=true returns the settled bill. A mid-life /usage read is a
    # documented lower bound, so this is the only figure worth recording.
    resp=$(api DELETE "/v1/machines/$id?includeUsage=true")
    micros=$(printf '%s' "$resp" | sed -n 's/.*"totalMicros":\([0-9]*\).*/\1/p')
    secs=$(printf '%s' "$resp" | sed -n 's/.*"totalUptimeSeconds":\([0-9]*\).*/\1/p')
    echo "deleted=$id uptime_s=${secs:-0} micros=${micros:-0}"
    total=$(( total + ${micros:-0} ))
  done < "$IDFILE"
  rm -f "$IDFILE"
fi
echo "settled_micros=$total"

if [ "${1:-}" = "--reap" ]; then
  api GET /v1/machines | python3 -c "
import json,sys
for m in json.load(sys.stdin):
    if (m.get('name') or '').startswith('$PREFIX'): print(m['id'])" | while read -r id; do
    [ -n "$id" ] || continue
    echo "reaped=$id"; api DELETE "/v1/machines/$id" >/dev/null
  done
fi

# Both surfaces, because the CLI list and the API list are different code paths.
left=$(api GET /v1/machines | python3 -c "
import json,sys
print(sum(1 for m in json.load(sys.stdin) if (m.get('name') or '').startswith('$PREFIX')))")
echo "api_prefix_machines_left=$left"
if command -v smol >/dev/null 2>&1; then
  smol cloud ls 2>/dev/null | grep -q "$PREFIX" && echo "cli_prefix_machines_left=some" || echo "cli_prefix_machines_left=0"
else
  echo "cli_prefix_machines_left=skipped"
fi

over=no; [ "$total" -gt "$CEILING_MICROS" ] && over=yes
echo "over_ceiling=$over (ceiling=${CEILING_MICROS} micros)"
[ "$left" -eq 0 ] && [ "$over" = no ] && echo "result=clean" || echo "result=NOT_CLEAN"
[ "$left" -eq 0 ] && [ "$over" = no ]

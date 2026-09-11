#!/usr/bin/env bash
# Drives one machine through exec, files, stop, start and asserts what survives.
# Asserts values from bodies, never HTTP status: a failed guest command is a 200.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

ID="${1:-$(tail -1 "$IDFILE" 2>/dev/null)}"
[ -n "$ID" ] || { echo "machine=FAIL expected=an id actual=none recorded"; exit 1; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

ex() { api POST "/v1/machines/$ID/exec" "$(printf '{"command":["sh","-c",%s]}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")")"; }
exout() { ex "$1" | jget stdout | tr -d '\n'; }

check guest_exec MACHINE_UP "$(exout 'echo MACHINE_UP')"

# A failing command comes back on HTTP 200. The exit code is in the body and is
# the only place the failure appears, so assert it rather than the status.
r=$(ex 'echo out; echo err >&2; exit 42')
check failing_exec_exit_code 42 "$(printf '%s' "$r" | sed -n 's/.*"exitCode":\([0-9-]*\).*/\1/p')"

# Files are a path SUFFIX on the route, with no leading slash. The ?path= query
# form returns an empty-bodied 404 that reads exactly like "no such machine".
up=$(curl -sS -X PUT --max-time 60 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
     -H 'content-type: application/octet-stream' --data-binary 'ROUNDTRIP-9f3a' \
     -o /dev/null -w '%{http_code}' "$API/v1/machines/$ID/files/workspace/rb-rt.txt")
check file_upload 204 "$up"
check file_download ROUNDTRIP-9f3a "$(curl -sS --max-time 60 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/machines/$ID/files/workspace/rb-rt.txt")"
check file_in_guest ROUNDTRIP-9f3a "$(exout 'cat /workspace/rb-rt.txt')"

# One marker per filesystem. Everything after this is a read.
ex 'echo persist-9f3a > /workspace/rb-marker.txt; echo tmp-9f3a > /tmp/rb-marker.txt' >/dev/null

api POST "/v1/machines/$ID/stop" '{}' >/dev/null
api POST "/v1/machines/$ID/start" '{}' >/dev/null
# Poll on a value from the guest, not on the record's state field: start returns
# when the record flips, which is before the guest can run anything.
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ "$(exout 'echo BACK')" = "BACK" ] && break
  sleep 3
done

check workspace_survives persist-9f3a "$(exout 'cat /workspace/rb-marker.txt 2>/dev/null')"
check tmp_wiped "" "$(exout 'cat /tmp/rb-marker.txt 2>/dev/null')"

# The load-bearing one: it proves the guest really rebooted rather than the
# control plane flipping a state field, which a state check cannot see.
up_s=$(exout 'cut -d. -f1 /proc/uptime')
if [ -n "$up_s" ] && [ "$up_s" -lt 120 ]; then echo "really_rebooted=ok (uptime ${up_s}s)"
else echo "really_rebooted=FAIL expected=uptime under 120s actual=${up_s:-unknown}"; fails=$((fails+1)); fi

# Reported honestly rather than attempted: there is no branch or fork route in
# the published spec, and the machine record says it cannot.
rec=$(api GET "/v1/machines/$ID")
echo "branchable=$(printf '%s' "$rec" | sed -n 's/.*"branchable":\([a-z]*\).*/\1/p') forkable=$(printf '%s' "$rec" | sed -n 's/.*"forkable":\([a-z]*\).*/\1/p')"

[ "$fails" -eq 0 ] && echo "result=lifecycle_ok" || echo "result=lifecycle_failed"
[ "$fails" -eq 0 ]

#!/usr/bin/env bash
# The failures that arrive as HTTP 200. These are the ones that matter: no status
# check finds them. Creates one small machine and deletes it via cleanup.sh.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

NAME="${PREFIX}err1"
body=$(printf '{"name":"%s","source":{"type":"image","reference":"library/alpine:3.20"},"resources":{"cpus":1,"memoryMb":256},"network":{"mode":"open"}}' "$NAME")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
[ -n "$id" ] || { echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; exit 1; }
record "$id"; echo "machine_id=$id"
api POST "/v1/machines/$id/start" '{}' >/dev/null
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ -n "$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","echo up"]}' | jget stdout)" ] && break
  sleep 3
done

# A duplicate name is one of the few real 4xx a running machine can produce.
dup=$(curl -sS --max-time 45 -o /tmp/ce2.$$ -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
      -d "$body" "$API/v1/machines")
check duplicate_name_409 409 "$dup"; rm -f /tmp/ce2.$$

ex() { curl -sS --max-time 60 -o /tmp/ce3.$$ -w '%{http_code}' -X POST \
       -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
       -d "$1" "$API/v1/machines/$id/exec"; }
field() { python3 -c "import json,sys;print(json.load(open('/tmp/ce3.$$')).get(sys.argv[1],''))" "$1" 2>/dev/null; }

# 1. A command that exited non-zero.
check nonzero_exit_status 200 "$(ex '{"command":["sh","-c","echo out; echo err >&2; exit 42"]}')"
check nonzero_exit_code 42 "$(field exitCode)"
# 2. A command that timed out. 124 is the shell's timeout convention.
check timeout_status 200 "$(ex '{"command":["sh","-c","sleep 30"],"timeoutSeconds":3}')"
check timeout_exit_code 124 "$(field exitCode)"
# 3. An interpreter the image does not have. Not a transport failure either.
check missing_binary_status 200 "$(ex '{"command":["python3","-c","print(1)"]}')"
mb=$(field exitCode); [ "$mb" != 0 ] && echo "missing_binary_exit_code=ok ($mb)" || { echo "missing_binary_exit_code=FAIL expected=non-zero actual=0"; fails=$((fails+1)); }
rm -f /tmp/ce3.$$

echo "---"
echo "note=every failure above is HTTP 200; exitCode in the body is the only signal"
[ "$fails" -eq 0 ] && echo "result=all_provoked" || echo "result=unexpected_shapes"
[ "$fails" -eq 0 ]

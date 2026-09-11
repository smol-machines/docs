#!/usr/bin/env bash
# Provokes every documented failure that needs no machine, and asserts the status
# AND the body shape, because on this API the two do not agree about the format.
# Creates nothing and bills nothing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
fails=0
# probe NAME EXPECTED_STATUS EXPECTED_BODY_SUBSTRING curl-args...
probe() {
  local name="$1" want="$2" needle="$3"; shift 3
  local body status
  body=$(curl -sS --max-time 45 -o /tmp/ce.$$ -w '%{http_code}' "$@"); status="$body"
  body=$(head -c 300 /tmp/ce.$$ | tr '\n' ' ')
  if [ "$status" = "$want" ] && case "$body" in *"$needle"*) true;; *) false;; esac; then
    echo "$name=ok ($status)"
  else
    echo "$name=FAIL expected=$want+'$needle' actual=$status '$body'"; fails=$((fails+1))
  fi
}
H="Authorization: Bearer $SMOL_CLOUD_TOKEN"
J='content-type: application/json'

# 401: the body here IS json with a code field. Almost nothing else is.
probe unknown_key_401 401 unknown_key -H 'Authorization: Bearer smk_wrong' "$API/v1/machines"
# 401 on a route that does not exist, so route probing without a key tells you nothing.
probe nonexistent_path_401 401 "" "$API/v1/nope"
# 403 names the exact missing scope in plain text.
probe missing_scope_403 403 "missing scope" -H "$H" "$API/v1/volumes"
# 400 is reserved for a body that is not JSON at all.
probe not_json_400 400 "" -X POST -H "$H" -H "$J" -d 'not json' "$API/v1/machines"
# 422 is everything that parses but does not satisfy the schema: three causes, one status.
probe missing_field_422 422 source -X POST -H "$H" -H "$J" -d '{"name":"x"}' "$API/v1/machines"
probe wrong_type_422 422 "" -X POST -H "$H" -H "$J" \
  -d '{"source":{"type":"image","reference":"library/alpine:3.20"},"resources":{"cpus":"lots"}}' "$API/v1/machines"
# 404 carries a message, unlike the unauthenticated 401 above.
probe no_such_machine_404 404 "not found" -H "$H" "$API/v1/machines/mach-does-not-exist"

echo "---"
echo "note=401 is JSON with a code field; 400, 403, 404, 409, 422 and 501 are plain text"
echo "note=a 422 cannot be triaged by status: a typo, a wrong type and a quota refusal are all 422"
rm -f /tmp/ce.$$
[ "$fails" -eq 0 ] && echo "result=all_provoked" || echo "result=unexpected_shapes"
[ "$fails" -eq 0 ]

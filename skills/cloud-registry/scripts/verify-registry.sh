#!/usr/bin/env bash
# Runs a cloud machine from an artifact in your namespace and asserts it is that
# artifact, by reading a value out of the guest rather than trusting the name.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
REF="${1:-}"; EXPECT="${2:-3.20.10}"
[ -n "$REF" ] || { echo "usage: verify-registry.sh <tenants/<tenant>/name:tag> [expected-alpine-release]"; exit 2; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "$1=ok ($3)"; else echo "$1=FAIL expected=$2 actual=$3"; fails=$((fails+1)); fi; }

NAME="${PREFIX}reg1"
# The smolmachine source needs an explicit arch: cloud guests are amd64 and the
# client may not be, so the artifact's arch cannot be inferred from this host.
body=$(printf '{"name":"%s","source":{"type":"smolmachine","reference":"%s","arch":"amd64"},"resources":{"cpus":1,"memoryMb":256},"network":{"mode":"open"}}' "$NAME" "$REF")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
[ -n "$id" ] || { echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; exit 1; }
record "$id"; echo "machine_id=$id"
api POST "/v1/machines/$id/start" '{}' >/dev/null

deadline=$(( $(date +%s) + 120 ))
rel=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  rel=$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","cat /etc/alpine-release"]}' | jget stdout | tr -d '\n')
  [ -n "$rel" ] && break
  sleep 3
done
check runs_from_artifact "$EXPECT" "$rel"
check guest_arch x86_64 "$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","uname -m"]}' | jget stdout | tr -d '\n')"
[ "$fails" -eq 0 ] && echo "result=registry_ok" || echo "result=registry_failed"
[ "$fails" -eq 0 ]

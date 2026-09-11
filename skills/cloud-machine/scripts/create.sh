#!/usr/bin/env bash
# Creates one cloud machine over HTTP and records its id for cleanup.
# Creates a billable machine. Run cleanup.sh when done.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token

NAME="${1:-${PREFIX}m1}"
IMAGE="${2:-library/alpine:3.20}"
case "$NAME" in "$PREFIX"*) ;; *) echo "name=FAIL expected=${PREFIX}* actual=$NAME"; exit 1;; esac

# `source` is required and is a tagged object; `image` at the top level is
# rejected with a deserialize error. cpus and memoryMb live under `resources`.
# No "ports" field: the CLI publishes 8080 by default, which makes `ready`
# unreachable for a non-server image and widens the machine's exposure.
body=$(printf '{"name":"%s","source":{"type":"image","reference":"%s"},"resources":{"cpus":1,"memoryMb":512},"network":{"mode":"open"}}' "$NAME" "$IMAGE")
resp=$(api POST /v1/machines "$body")
id=$(printf '%s' "$resp" | jget id)
if [ -z "$id" ]; then
  echo "created=FAIL response=$(printf '%s' "$resp" | head -c 200)"; echo "result=create_failed"; exit 1
fi
record "$id"
echo "machine_id=$id"
echo "created_state=$(printf '%s' "$resp" | jget state)"

start=$(api POST "/v1/machines/$id/start" '{}')
echo "started_state=$(printf '%s' "$start" | jget state)"

# Poll on a value from inside the guest rather than sleeping a fixed time: the
# record flips to "started" when the control plane says so, not when the guest
# can run a command, and the gap is what a blind sleep gets wrong in both
# directions. Bounded so a machine that never answers fails instead of hanging.
deadline=$(( $(date +%s) + 120 ))
ready=no
while [ "$(date +%s)" -lt "$deadline" ]; do
  out=$(api POST "/v1/machines/$id/exec" '{"command":["sh","-c","echo GUEST_UP"]}' 2>/dev/null | jget stdout)
  case "$out" in *GUEST_UP*) ready=yes; break;; esac
  sleep 3
done
echo "guest_answered=$ready"
[ "$ready" = yes ] && echo "result=up" || { echo "result=guest_never_answered"; exit 1; }

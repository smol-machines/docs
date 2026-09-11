# Shared by this packet's scripts. Sourced, not run.
# Never echoes the credential.
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
PREFIX="smolskill-"
STATE="${SMOLSKILL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/smol-skills}"
mkdir -p "$STATE"
IDFILE="$STATE/cloud-machines.ids"

api() { # api METHOD PATH [JSON_BODY]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" --max-time 120 \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" -H 'content-type: application/json' \
      -d "$body" "$API$path"
  else
    curl -sS -X "$method" --max-time 120 \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API$path"
  fi
}

jget() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit(0)
for k in sys.argv[1].split('.'):
    if d is None: break
    d = d.get(k) if isinstance(d, dict) else None
print('' if d is None else d)" "$1"; }

require_token() {
  [ -n "${SMOL_CLOUD_TOKEN:-}" ] && return 0
  echo "credential=FAIL expected=SMOL_CLOUD_TOKEN set actual=unset"; echo "result=cannot_run"; exit 1
}

record() { echo "$1" >> "$IDFILE"; }   # only ids this packet created

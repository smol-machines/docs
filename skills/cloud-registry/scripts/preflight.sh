#!/usr/bin/env bash
# Read-only. Pulls nothing, pushes nothing, creates no machine.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
command -v smol >/dev/null 2>&1 || { echo "smol_installed=no"; echo "note=the registry verbs are CLI only"; echo "result=blocked"; exit 0; }
echo "smol_installed=yes"

ns=$(smol auth status 2>/dev/null | sed -n 's/^ *Registry *//p')
echo "namespace=${ns:-unknown}"
[ -n "$ns" ] || { echo "note=no Registry line in auth status; the credential is not resolving"; echo "result=blocked"; exit 0; }

echo "host_arch=$(uname -m)"
# `smol pack inspect` refuses an artifact whose arch is not the host's, while the
# cloud runs amd64. On an arm64 host you can push and deploy what you cannot inspect.
case "$(uname -m)" in
  arm64|aarch64) echo "note=cloud guests are amd64; pack inspect will refuse an amd64 artifact on this host, deploy still works";;
esac

# These four verbs disagree about whether you are logged in. Measured without a
# pipe, because a pipe reports the exit status of the last command in it.
for v in ls catalog; do smol registry "$v" >/dev/null 2>&1; echo "registry_${v}_exit=$?"; done
echo "note=registry ls and catalog fail with only SMOL_CLOUD_TOKEN set, while pack push and registry tags succeed"

echo "result=ready"

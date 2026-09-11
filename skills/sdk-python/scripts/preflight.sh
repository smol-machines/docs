#!/usr/bin/env bash
# Read-only. Installs nothing, creates no machine, bills nothing.
# Run it with the interpreter you intend to use: PY=./.venv/bin/python preflight.sh
set -uo pipefail
PY="${PY:-python3}"
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
notes=()
TLS_OK=no

command -v "$PY" >/dev/null 2>&1 || { echo "python=missing ($PY)"; echo "result=blocked"; exit 0; }
echo "python=$("$PY" -c 'import sys;print(sys.version.split()[0])')"
echo "python_path=$("$PY" -c 'import sys;print(sys.executable)')"

# The distribution is `smolmachines`; the module it installs is `smol`.
if "$PY" -c 'import smol' >/dev/null 2>&1; then
  echo "module_smol=importable"
  echo "sdk_version=$("$PY" -c 'import smol;print(getattr(smol,"__version__","unknown"))')"
else
  echo "module_smol=missing"
  notes+=("note=pip install smolmachines, then import smol; import smolmachines always fails")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi

# A python.org interpreter ships no CA bundle, and the SDK uses urllib, so the
# failure is a TLS error that reads like an outage rather than a setup problem.
if "$PY" - <<'PYEOF' >/dev/null 2>&1
import urllib.request
urllib.request.urlopen("https://api.smolmachines.com/health", timeout=20).read()
PYEOF
then
  echo "tls_to_api=ok"; TLS_OK=yes
else
  echo "tls_to_api=FAILED"; TLS_OK=no
  notes+=("note=certificate verification failed: pip install certifi and export SSL_CERT_FILE=\$($PY -m certifi)")
fi

[ -n "${SMOL_CLOUD_TOKEN:-}" ] && echo "credential=env" || { echo "credential=none"; notes+=("note=set SMOL_CLOUD_TOKEN"); }

[ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
# Blocked when TLS fails: an SDK that cannot open a connection is not ready,
# and saying so here is the whole point of the check.
if [ "$TLS_OK" = yes ] && [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then echo "result=ready"; else echo "result=blocked"; fi

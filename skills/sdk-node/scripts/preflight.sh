#!/usr/bin/env bash
# Read-only. Installs nothing, creates no machine, bills nothing.
set -uo pipefail
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
notes=()
command -v node >/dev/null 2>&1 || { echo "node=missing"; echo "result=blocked"; exit 0; }
echo "node=$(node --version)"

if node -e "require.resolve('smolmachines')" >/dev/null 2>&1; then
  echo "package_smolmachines=resolvable"
  # The package does not export its package.json, so require() of it throws.
  # Resolve the entry point and walk up to the manifest beside it.
  VER=$(node -p "const{createRequire}=require('node:module'),fs=require('node:fs'),path=require('node:path');let d=path.dirname(createRequire(process.cwd()+'/').resolve('smolmachines')),v='unknown';for(let i=0;i<4;i++){const f=path.join(d,'package.json');if(fs.existsSync(f)){v=JSON.parse(fs.readFileSync(f,'utf8')).version;break}d=path.dirname(d)}v" 2>/dev/null || echo unknown)
  echo "sdk_version=${VER:-unknown}"
else
  echo "package_smolmachines=missing"
  notes+=("note=npm install smolmachines in this project; the package and the import name match, unlike Python")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi

# Node ships its own trust store, so the certificate trap that stops the Python
# SDK on a fresh interpreter does not apply here. Checked rather than assumed.
if node -e "fetch('$API/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))" >/dev/null 2>&1; then
  echo "tls_to_api=ok"; TLS_OK=yes
else
  echo "tls_to_api=FAILED"; TLS_OK=no
  notes+=("note=Node ships a CA bundle, so this is the network or the API rather than a missing trust store")
fi

[ -n "${SMOL_CLOUD_TOKEN:-}" ] && echo "credential=env" || { echo "credential=none"; notes+=("note=set SMOL_CLOUD_TOKEN"); }
echo "note=never console.log or JSON.stringify a Machine: apiKey is a plain enumerable property"

[ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
if [ "${TLS_OK:-no}" = yes ] && [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then echo "result=ready"; else echo "result=blocked"; fi

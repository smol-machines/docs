#!/usr/bin/env bash
# Pulls a .smolmachine artifact to a local file. Reads on the `library` namespace
# need no credential. Creates nothing on the account and bills nothing.
set -uo pipefail
REF="${1:-registry.smolmachines.com/library/alpine:3.20-linux-amd64}"
OUT="${2:-./artifact.smolmachine}"
command -v smol >/dev/null 2>&1 || { echo "smol_installed=no"; exit 1; }
out=$(smol pack pull "$REF" -o "$OUT" 2>&1); echo "$out" | sed 's/^/  /'
bytes=$(printf '%s' "$out" | sed -n 's/.*(\([0-9]*\) bytes).*/\1/p')
echo "artifact=$OUT bytes=${bytes:-unknown}"
printf '%s' "$out" | grep -q 'Pulled successfully' && echo "result=pulled" || { echo "result=pull_failed"; exit 1; }

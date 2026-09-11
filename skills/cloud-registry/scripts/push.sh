#!/usr/bin/env bash
# Pushes a .smolmachine artifact into the account's namespace.
# A PUSH CANNOT BE UNDONE with any shipped tool. Refuses without confirmation.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_token
REF="${1:-}"; FILE="${2:-}"; CONFIRM="${3:-}"
if [ -z "$REF" ] || [ -z "$FILE" ]; then
  echo "usage: push.sh <registry-reference> <file.smolmachine> --i-understand-this-cannot-be-undone"; exit 2
fi
if [ "$CONFIRM" != "--i-understand-this-cannot-be-undone" ]; then
  echo "refused=yes"
  echo "note=a pushed artifact cannot be deleted by smol pack, smol registry, or an OCI manifest DELETE"
  echo "note=reuse one tag across runs rather than minting a new one; pass the confirmation flag to proceed"
  exit 2
fi
out=$(smol pack push "$REF" -f "$FILE" 2>&1); echo "$out" | sed 's/^/  /'
# The manifest digest is the only immutable handle to what was pushed, and the
# console is the only thing that can remove it. Capture it now or lose it.
echo "manifest=$(printf '%s' "$out" | sed -n 's/.*Manifest: *\(sha256:[0-9a-f]*\).*/\1/p')"
printf '%s' "$out" | grep -q 'Pushed successfully' && echo "result=pushed" || { echo "result=push_failed"; exit 1; }

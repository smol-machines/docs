#!/usr/bin/env bash
# Reports whether this host can reach smol cloud and whether a credential works.
# Read-only: creates no machine, writes no config, bills nothing.
# Never prints the key. Every line is key=value; the last line is result=.
set -uo pipefail

VERIFIED_CLI="1.14.3"
VERIFIED_API="0.1.0"
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
notes=()

# --- the CLI -----------------------------------------------------------------
if command -v smol >/dev/null 2>&1; then
  echo "smol_installed=yes"
  ver=$(smol --version 2>/dev/null | awk '{print $2}')
  echo "smol_version=${ver:-unknown}"
  if [ "$ver" = "$VERIFIED_CLI" ]; then echo "version_status=match"
  elif [ -z "$ver" ]; then echo "version_status=unknown"
  else
    # Sort tells us which side is newer without a version-compare dependency.
    newest=$(printf '%s\n%s\n' "$ver" "$VERIFIED_CLI" | sort -V | tail -1)
    [ "$newest" = "$VERIFIED_CLI" ] && echo "version_status=older" || echo "version_status=newer"
    notes+=("note=this packet was verified on smol $VERIFIED_CLI; check each step's output against your binary")
  fi
else
  echo "smol_installed=no"; echo "smol_version=none"; echo "version_status=unknown"
  notes+=("note=the smol CLI is not on PATH; the HTTP half of this packet still works")
fi
echo "verified_cli=$VERIFIED_CLI"

# --- the API, before any credential is presented ------------------------------
# /health is the only unauthenticated route: it separates "the API is down" from
# "your key is wrong", which no status code on a 401-everything API can do.
health=$(curl -fsS --max-time 20 "$API/health" 2>/dev/null)
if [ -n "$health" ]; then
  echo "api_reachable=yes"
  echo "api_version=$(printf '%s' "$health" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  echo "api_nodes_ready=$(printf '%s' "$health" | sed -n 's/.*"nodesReady":\([0-9]*\).*/\1/p')"
else
  echo "api_reachable=no"; echo "api_version=unknown"; echo "api_nodes_ready=0"
  notes+=("note=$API/health did not answer; this is the API or your network, not your key")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi
echo "verified_api=$VERIFIED_API"

# --- the credential -----------------------------------------------------------
if [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then
  echo "credential_source=env"
elif command -v smol >/dev/null 2>&1 &&
     smol config show 2>/dev/null | grep 'cloud.api_key' | grep -qv '(not set)'; then
  echo "credential_source=cli_config"
  notes+=("note=the key is persisted on disk; SMOL_CLOUD_TOKEN leaves nothing behind")
else
  echo "credential_source=none"
  notes+=("note=set SMOL_CLOUD_TOKEN, or run: smol config set cloud.api_key <key>")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi

# Assert a value out of the account body, on whichever surface holds the key.
# A 200 alone does not prove the tenant is usable, and `smol auth status` cannot
# be gated on at all (see references/traps.md).
status=""
if [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then
  acct=$(curl -fsS --max-time 25 -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" "$API/v1/account" 2>/dev/null)
  if [ -n "$acct" ]; then
    echo "account_readable=yes"
    status=$(printf '%s' "$acct" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    echo "plan=$(printf '%s' "$acct" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
  else
    echo "account_readable=no"
    notes+=("note=the API answered /health but refused /v1/account; the key is wrong, expired or revoked")
  fi
else
  # The key is in the CLI config, so the HTTP half of this packet cannot use it.
  # Prove the credential through the CLI instead, by value and not by exit code.
  echo "account_readable=via_cli"
  status=$(smol auth status 2>/dev/null | sed -n 's/.*(tenant-[^,]*, \([a-z]*\)).*/\1/p')
  notes+=("note=the HTTP steps in this packet need SMOL_CLOUD_TOKEN as well; the CLI config is not read by curl")
fi
echo "tenant_status=${status:-unknown}"

[ "$status" = "active" ] || notes+=("note=the tenant is not active or could not be read; calls that create machines will refuse")

[ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
[ "$status" = "active" ] && echo "result=ready" || echo "result=blocked"

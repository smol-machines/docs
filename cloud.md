---
title: Cloud Quick Start
---

# Cloud Quick Start

Create a persistent cloud machine, run a command, and clean it up through the REST API.

## 1. Create an account and API key

Sign in at [smolmachines.com/console](/console), open [API Keys](/console/keys), and create a key. Copy it when it is shown.

New accounts currently include $10 monthly free usage, no card required. See [pricing](/pricing) for current limits and rates.

Export the key. The SDK and the `smol` CLI read the same two variables:

```bash
export SMOL_CLOUD_TOKEN="smk_your_key_here"
export SMOL_CLOUD_URL="https://api.smolmachines.com"
```

Send the key as a bearer token. Do not put it in source control or client-side application code.

## 2. Create a machine

This request creates an Alpine machine with one vCPU, 256 MB of memory, and open outbound networking:

```bash
curl --fail-with-body -X POST "$SMOL_CLOUD_URL/v1/machines" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "quick-start",
    "source": {"type": "image", "reference": "alpine"},
    "resources": {"cpus": 1, "memoryMb": 256},
    "network": {"mode": "open"}
  }'
```

The response includes the machine `id`. Save it:

```bash
export MACHINE_ID="mach-replace-with-your-id"
```

A newly created machine is stopped. The first exec request starts it automatically.

## 3. Execute a command

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"command":["sh","-lc","echo hello from smol cloud"]}'
```

The response contains `stdout`, `stderr`, `exitCode`, `durationMs`, and `machineId`.

## 4. Install software or run a script

With open networking, packages installed in the machine persist across later exec calls:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"command":"apk add --no-cache python3"}'
```

Upload a local script, then execute it:

```bash
curl --fail-with-body -X PUT \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/files/workspace/app.py" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  --data-binary @app.py

curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"command":["python3","/workspace/app.py"]}'
```

Pass JSON, source code, or another small payload through standard input with the `stdin` field in an exec request.

## 5. Wait for readiness when needed

`state: "started"` means the VM process has launched. It does not guarantee that the guest agent or an application listening on a published port is ready.

Poll the machine until `ready` is `true` before connecting to an application:

```bash
ready=false
for _ in $(seq 1 60); do
  record=$(curl --fail --silent \
    "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID" \
    -H "Authorization: Bearer $SMOL_CLOUD_TOKEN") || {
      sleep 1
      continue
    }

  if jq -e '.ready == true' >/dev/null <<<"$record"; then
    ready=true
    break
  fi

  if jq -e '(has("ready") | not) and .state == "started"' \
    >/dev/null <<<"$record" &&
    curl --fail --silent -X POST \
      "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"command":["true"]}' >/dev/null; then
    ready=true
    break
  fi

  sleep 1
done

[ "$ready" = true ] || {
  echo "machine did not become ready within 60 seconds" >&2
  exit 1
}
```

For older records without `ready`, the loop waits for `started` and runs a lightweight command to verify the guest agent. Poll the application endpoint separately before sending traffic to a service.

## 6. Stop or delete the machine

Stop the machine when you want to keep its filesystem for later:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/stop" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

Start it again:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/start" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

Delete it when you no longer need the machine or its stored data:

```bash
curl --fail-with-body -X DELETE \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking) before using volumes, ingress, or restricted egress.

---
title: Cloud Examples
---

# Cloud Examples

These examples use the Cloud REST API directly.

## Setup

```bash
export SMOL_CLOUD_TOKEN="smk_your_key_here"
export SMOL_CLOUD_URL="https://api.smolmachines.com"
```

The examples use `jq` to read JSON responses.

## Create a machine and capture its ID

```bash
export MACHINE_ID="$(
  curl --fail-with-body --silent -X POST \
    "$SMOL_CLOUD_URL/v1/machines" \
    -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "examples",
      "source": {"type": "image", "reference": "python:3.12-alpine"},
      "resources": {"cpus": 1, "memoryMb": 512},
      "network": {"mode": "open"}
    }' |
  jq -r '.id'
)"

printf '%s\n' "$MACHINE_ID"
```

## Run a command

An argv array avoids an extra shell parsing step:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "command": ["python3", "-c", "print(sum(range(100)))"],
    "timeoutSeconds": 30
  }'
```

Use a string when shell features such as pipes or redirection are required:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"command":"printf \"%s\\n\" alpha beta | sort -r"}'
```

## Pass environment and stdin

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "command": ["python3", "-c", "import os,sys; print(os.environ[\"LABEL\"], len(sys.stdin.read()))"],
    "env": {"LABEL": "payload-bytes"},
    "stdin": "hello\n"
  }'
```

Values in `env` are visible to code inside the guest. Do not send a secret unless the workload should be able to read it.

## Start a background service

Create a machine with a published port:

```bash
export WEB_MACHINE_ID="$(
  curl --fail-with-body --silent -X POST \
    "$SMOL_CLOUD_URL/v1/machines" \
    -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "example-web",
      "source": {"type": "image", "reference": "python:3.12-alpine"},
      "resources": {"cpus": 1, "memoryMb": 512},
      "network": {"mode": "open"},
      "ports": [{"port": 8000}],
      "public": false
    }' |
  jq -r '.id'
)"
```

Start a detached HTTP server:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$WEB_MACHINE_ID/exec" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "command": ["python3", "-m", "http.server", "8000", "--directory", "/workspace"],
    "background": true
  }'
```

Use `background` for detached execution when the endpoint supports it.

Wait for readiness:

```bash
ready=false
for _ in $(seq 1 60); do
  record=$(curl --fail --silent \
    "$SMOL_CLOUD_URL/v1/machines/$WEB_MACHINE_ID" \
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
    curl --fail --silent \
      "$SMOL_CLOUD_URL/v1/machines/$WEB_MACHINE_ID/connect/8000/" \
      -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" >/dev/null; then
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

For older records without `ready`, the loop waits for `started` and probes the application through the authenticated connect route.

Connect through the authenticated bridge:

```bash
curl --fail \
  "$SMOL_CLOUD_URL/v1/machines/$WEB_MACHINE_ID/connect/8000/" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

Confirm published-port fields and the connect route in the API Explorer before using this example in production.

## Use a restricted egress policy

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "restricted",
    "source": {"type": "image", "reference": "alpine"},
    "network": {
      "mode": "allowCidrs",
      "hosts": ["example.com"],
      "cidrs": []
    }
  }'
```

The control plane pulls the source OCI image outside the guest. Add registry and package hosts only when software running inside the guest must reach them.

## Create and mount a volume

Create a volume:

```bash
export VOLUME_NAME="example-data"

curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/volumes" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$VOLUME_NAME\",\"sizeGb\":10}"
```

Mount it when creating a machine:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"with-volume\",
    \"source\": {\"type\": \"image\", \"reference\": \"alpine\"},
    \"network\": {\"mode\": \"blocked\"},
    \"mounts\": [
      {
        \"volume\": \"$VOLUME_NAME\",
        \"mountPath\": \"/data\",
        \"readonly\": false
      }
    ]
  }"
```

## List and inspect machines

List every machine on the account:

```bash
curl --fail --silent "$SMOL_CLOUD_URL/v1/machines" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" |
  jq '.[] | {id, name, state, ready}'
```

Read one machine in full:

```bash
curl --fail --silent \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" |
  jq
```

## Stop and clean up

Stop a machine while keeping its data:

```bash
curl --fail-with-body -X POST \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID/stop" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

Delete example machines when finished:

```bash
curl --fail-with-body -X DELETE \
  "$SMOL_CLOUD_URL/v1/machines/$MACHINE_ID" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"

curl --fail-with-body -X DELETE \
  "$SMOL_CLOUD_URL/v1/machines/$WEB_MACHINE_ID" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN"
```

Delete any separately managed volume by its returned volume ID after all attached machines are removed.

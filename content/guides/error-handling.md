---
title: Error Handling
---

# Error Handling

Separate command failures from machine, transport, and configuration failures. A command can run successfully at the infrastructure level and still return a nonzero exit code.

## SDK command results

`exec` and local `run` return an `ExecResult`:

| Python | Node.js | Meaning |
|---|---|---|
| `exit_code` | `exitCode` | Guest process exit code |
| `stdout` | `stdout` | Captured UTF-8 text |
| `stderr` | `stderr` | Captured UTF-8 text |
| `success` | `success` | Exit code is zero |
| `output` | `output` | Combined output |
| `assert_success()` | `assertSuccess()` | Raise `ExecutionError` on nonzero exit |

Inspect the result when a nonzero code is part of normal control flow:

```python
result = machine.exec(["sh", "-c", "test -f /workspace/result.json"])
if result.exit_code == 1:
    print("result file is absent")
elif not result.success:
    print(result.stderr)
    raise RuntimeError(f"check failed with {result.exit_code}")
```

Use `assert_success()` when any nonzero exit should abort the operation:

```python
result = machine.exec(["python", "-m", "pytest"]).assert_success()
print(result.stdout)
```

The Node equivalent is:

```typescript
const result = await machine.exec(["npm", "test"]);
result.assertSuccess();
console.log(result.stdout);
```

Cloud text output can be truncated. Check `stdout_truncated` and `stderr_truncated` in Python, or `stdoutTruncated` and `stderrTruncated` in Node. Use byte output, REST streaming where supported, or write large output to a guest file and download it.

## SDK exceptions

Both SDKs expose typed errors:

- `ExecutionError`: `assert_success()` or `assertSuccess()` received a nonzero command exit
- `InvalidConfigError`: required configuration is missing or invalid
- `NotSupportedError`: the selected local or cloud backend does not implement that operation
- `SmolError`: base SDK, engine, transport, readiness, and cloud API error. Inspect its `code`

Python:

```python
from smol import ExecutionError, SmolError

try:
    machine.exec(["python", "-m", "pytest"]).assert_success()
except ExecutionError as error:
    print(error.exit_code, error.stderr)
except SmolError as error:
    print(error.code, str(error))
```

Node.js:

```typescript
import { ExecutionError, SmolError } from "smolmachines";

try {
  (await machine.exec(["npm", "test"])).assertSuccess();
} catch (error) {
  if (error instanceof ExecutionError) {
    console.error(error.exitCode, error.stderr);
  } else if (error instanceof SmolError) {
    console.error(error.code, error.message);
  } else {
    throw error;
  }
}
```

Do not parse error message text when a type or code is available. Common SDK codes include `COMMAND_FAILED`, `INVALID_CONFIG`, `NOT_SUPPORTED`, `NOT_FOUND`, `UNAUTHORIZED`, `CONNECTION`, and `TIMEOUT`.

## REST API errors

Check the HTTP status before decoding a success response. Keep the response body and `x-request-id` for debugging:

```bash
body=$(mktemp)
headers=$(mktemp)
trap 'rm -f "$body" "$headers"' EXIT

status=$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  https://api.smolmachines.com/v1/machines)

if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
  printf 'request failed: HTTP %s\n' "$status" >&2
  awk 'tolower($1) == "x-request-id:" { print }' "$headers" >&2
  cat "$body" >&2
  exit 1
fi

cat "$body"
```

Typical meanings:

- `400`: malformed or invalid request
- `401` or `403`: missing, invalid, or insufficient credentials
- `402`: tenant billing or budget restriction
- `404`: machine or other resource does not exist
- `409`: lifecycle conflict or duplicate name
- `422`: request accepted as structured input but rejected by a constraint such as quota
- `429`: rate limited; retry with bounded backoff and jitter
- `5xx`: service failure; retry idempotent requests with bounded backoff

Do not automatically retry invalid input, authentication failures, or arbitrary non-idempotent creates. When a create times out, list or fetch the resource before submitting another create.

The local `smolvm serve` API uses `/api/v1`. Generate the OpenAPI document for the installed version:

```bash
smolvm serve openapi
```

`smolvm serve` is a local control surface and does not currently enforce authentication. Bind it to loopback or a protected Unix socket, not an untrusted network.

## CLI exit codes

`smolvm machine run` and `smol run` return the guest command's exit code after cleanup. Other CLI commands return nonzero when the lifecycle or control operation fails.

Preserve the exit status in scripts:

```bash
set +e
smolvm machine run --net --image node:22-alpine -- npm test
status=$?
set -e

if [ "$status" -ne 0 ]; then
  printf 'tests failed with exit code %s\n' "$status" >&2
fi

exit "$status"
```

Do not pipe a command whose status matters without handling pipeline semantics. In Bash, use `set -o pipefail`; in other shells, capture the workload status before processing its output.

## Cleanup

Use a Python context manager for automatic deletion:

```python
from smol import ConnectOptions, Machine

with Machine.create(conn=ConnectOptions(target="local")) as machine:
    machine.run("alpine:3.20", ["sh", "-c", "./job"]).assert_success()
```

Use `finally` in Node and for persistent or cloud Python machines:

```typescript
import { Machine } from "smolmachines";

const machine = await Machine.create(undefined, { target: "local" });
try {
  (await machine.run("alpine:3.20", ["sh", "-c", "./job"])).assertSuccess();
} finally {
  await machine.delete().catch((error) => {
    console.error("machine cleanup failed", error);
  });
}
```

Do not let a cleanup error hide the original command failure. Log both, then return the workload's status. Add a cloud TTL when abandoned machines must be deleted after a controller crash.

## Debugging

1. Check machine state before retrying a lifecycle action.
2. For cloud machines, wait for `ready`. The `started` state only confirms that the VM process launched. `Machine.create` waits; `Machine.connect` does not.
3. Read both stdout and stderr and record the command exit code.
4. Set `RUST_LOG=debug` when running the CLI to collect engine logs:

   ```bash
   RUST_LOG=debug smolvm machine start --name dev
   ```

5. Run `smolvm machine status --name dev` and record the installed `smolvm --version`.
6. For local REST failures, reproduce against the OpenAPI document emitted by the installed binary.
7. For cloud REST failures, include the HTTP status and `x-request-id` in a support report. Remove tokens, injected secrets, and sensitive guest output first.
8. When a file written earlier is missing, check whether its path is memory-backed. `/tmp`, `/run`, and `/dev/shm` are empty after a stop and start, including an automatic idle stop, so a credential or configuration file kept there is gone once the machine restarts.

---
title: "SDK Python: drive cloud machines from Python"
---

# SDK Python: drive cloud machines from Python

Drives smol cloud machines from Python with the smolmachines SDK, from install through create, exec, files and delete. Use when a Python program or agent tool needs to run code in a machine; when the import fails after a successful install; when every call fails with a certificate error on a fresh interpreter; when an exec that failed did not raise; or when a machine config field seems to be ignored. Do not use it for the Node SDK or for raw HTTP, which have their own packets, and do not use it to install the CLI or mint a key.

Verified on **smolmachines 1.14.3** from PyPI (wheel `cp39-abi3-macosx_11_0_arm64`, 46.6 MB),
CPython **3.13.9** from python.org in a fresh venv, against **smolfleet API 0.1.0**, macOS 26.6.2
arm64, on 2026-09-10. Done means a machine was created, ran a command, round-tripped a file, and
was deleted, with every assertion made on a value rather than on the absence of an exception.

Two facts break more first attempts than anything else in this packet:

- **The distribution is `smolmachines` and the module is `smol`.** `import smolmachines` always
  fails.
- **A fresh python.org interpreter cannot reach the API at all** until a CA bundle is installed.
  The SDK uses `urllib` and depends on no `certifi`, so the failure is a TLS error that reads like
  an outage.

## Procedure

**1. Install and preflight.**

```bash
python3 -m venv .venv
./.venv/bin/pip install smolmachines certifi
export SSL_CERT_FILE="$(./.venv/bin/python -m certifi)"
PY=./.venv/bin/python scripts/preflight.sh
```

```
python=3.13.9
module_smol=importable
sdk_version=1.14.3
tls_to_api=ok
credential=env
result=ready
```

The preflight reports `result=blocked` when the certificate check fails, because an SDK that
cannot open a connection is not ready and every later error would name the wrong thing.

**2. Run the lifecycle.**

```bash
SMOL_CLOUD_TOKEN=... ./.venv/bin/python scripts/verify_sdk.py
```

```
string_command_accepted_without_validation=ok (True)
machine_id=mach-...
ready_after_create=ok (True)
exec_stdout=ok ('SDK_OK\n')
failed_exec_returns=ok (False)
failed_exec_exit_code=ok (42)
assert_success_raises=ok (True)
read_file_returns_bytes=ok (<class 'bytes'>)
file_roundtrip=ok (b'ROUNDTRIP')
exec_stream_works_on_cloud=ok (True)
endpoint_headers_carry_the_key=yes
deleted=yes
result=sdk_ok
```

The script deletes the machine in a `finally` block, including on an assertion failure. A leaked
cloud machine bills until someone notices, so that is not optional.

## The shape that works

```python
import os
from smol import ConnectOptions, Machine, MachineConfig, ResourceSpec

conn = ConnectOptions(target="cloud", api_key=os.environ["SMOL_CLOUD_TOKEN"])
machine = Machine.create(
    MachineConfig(name="my-job", image="library/alpine:3.20",
                  command=["sh", "-c", "while true; do sleep 3600; done"],
                  resources=ResourceSpec(cpus=1, memory_mb=256, network=True)),
    conn)
try:
    result = machine.exec(["sh", "-c", "echo hello"])
    result.assert_success()
    print(result.stdout)
finally:
    machine.delete()
```

`command` **must be a list.** A string is accepted by the config with no validation and the
workload never runs; the API rejects the same thing with a 422. With a published port that
surfaces two minutes later as a readiness timeout naming readiness, not the command.

`id` and `name` are properties; `state()`, `ready()`, `url()`, `exec()`, `endpoint(port)` and the
rest are methods.

## Reading a result

`exec` **returns** for a command that failed. It does not raise, so a `try/except` around it
catches transport errors only.

| To ask | Use |
|---|---|
| Did it succeed | `result.success` |
| What did it exit with | `result.exit_code` |
| Raise if it failed | `result.assert_success()`, raises `ExecutionError` |
| Output | `result.stdout`, `result.stderr`, both text |
| File contents | `machine.read_file(path)`, returns **bytes** |

`exec_stream()` works against cloud machines, although the reference page says local only.

## Security defaults, and why they are the defaults

- **The key comes from the environment**, never a literal in the file. `ConnectOptions` also
  accepts `api_key=` directly, which is useful for a test that must not read the environment and
  is a liability in committed code.
- **`endpoint(port).headers` carries the key**, confirmed here. Do not log an endpoint, and do not
  put one in an error message.
- **Delete in a `finally`.** Every example in this packet does, including the failure paths.
- **`network=True` is outbound access for the whole machine**, and it is on here only because the
  image pull needs it.

## Platform arms

- **macOS arm64, CPython 3.13.9 from python.org**: verified, in a fresh venv.
- **A system or Homebrew interpreter**: **not run.** Those usually carry a CA bundle, so the
  certificate trap may not appear; the preflight reports which case you are in rather than
  assuming.
- **Linux and Windows**: **not run.**

## What was not run

- **`AsyncMachine`** and the async surface.
- **The local target.** Everything here is `target="cloud"`.
- **A published port and `request()`**, which needs a server in the guest.
- **`Machine.create` against a machine that never becomes ready.** Recorded elsewhere as blocking
  the full readiness timeout, then deleting the machine and raising `TIMEOUT`, having billed for
  the wait. Not re-provoked here because it costs two minutes of billing to observe.
- **Branch and fork** were exercised from this SDK while verifying `cloud-machine`, not by this
  packet's own script.

## Related packets

- `cloud-auth` for the credential and its scopes.
- `cloud-machine` for the same lifecycle over raw HTTP, and the create body the SDK hides.
- `cloud-errors` for what the API returns underneath these calls.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
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
```

### `scripts/verify_sdk.py`

```python
"""Drives one cloud machine through the Python SDK and asserts values.

Creates a billable machine and deletes it in a finally block, including on an
assertion failure, because a leaked cloud machine bills until someone notices.
"""
import os, sys
from smol import (ConnectOptions, Machine, MachineConfig, ResourceSpec,
                  ExecutionError, SmolError)

NAME = "smolskill-py1"
fails = []


def check(name, expected, actual):
    if expected == actual:
        print(f"{name}=ok ({actual!r})")
    else:
        print(f"{name}=FAIL expected={expected!r} actual={actual!r}")
        fails.append(name)


conn = ConnectOptions(target="cloud", api_key=os.environ["SMOL_CLOUD_TOKEN"])

# A string here is silently dropped and the workload never runs. Asserted before
# a machine exists, because the failure it causes surfaces two minutes later as a
# readiness timeout that names readiness and not the command.
cfg_str = MachineConfig(name=NAME + "x", image="library/alpine:3.20",
                        command="echo hi",
                        resources=ResourceSpec(cpus=1, memory_mb=256, network=True))
check("string_command_accepted_without_validation", True,
      getattr(cfg_str, "command", None) is not None)
print("note=a string command is accepted here and the API rejects it with a 422; pass a list")

machine = None
try:
    machine = Machine.create(
        MachineConfig(name=NAME, image="library/alpine:3.20",
                      command=["sh", "-c", "while true; do sleep 3600; done"],
                      resources=ResourceSpec(cpus=1, memory_mb=256, network=True)),
        conn)
    print(f"machine_id={machine.id}")
    check("ready_after_create", True, machine.ready())

    r = machine.exec(["sh", "-c", "echo SDK_OK"])
    r.assert_success()
    check("exec_stdout", "SDK_OK\n", r.stdout)

    # exec RETURNS for a failed command; it does not raise. try/except around it
    # catches transport errors only, so the exit code has to be read.
    bad = machine.exec(["sh", "-c", "echo boom >&2; exit 42"])
    check("failed_exec_returns", False, bad.success)
    check("failed_exec_exit_code", 42, bad.exit_code)
    raised = False
    try:
        bad.assert_success()
    except ExecutionError:
        raised = True
    check("assert_success_raises", True, raised)

    machine.write_file("/workspace/rt.txt", b"ROUNDTRIP")
    got = machine.read_file("/workspace/rt.txt")
    check("read_file_returns_bytes", bytes, type(got))
    check("file_roundtrip", b"ROUNDTRIP", got)

    lines = [c for c in machine.exec_stream(["sh", "-c", "echo a; echo b"])]
    check("exec_stream_works_on_cloud", True, len(lines) > 0)

    # The key rides on the endpoint headers in both SDKs. Checked so nothing built
    # on this packet logs an endpoint by reflex. endpoint() needs a port, and this
    # machine publishes none, so a failure here is not a test failure.
    try:
        ep = machine.endpoint(8080)
        hdrs = getattr(ep, "headers", {}) or {}
        leaks = any("smk_" in str(v) for v in hdrs.values())
        print(f"endpoint_headers_carry_the_key={'yes' if leaks else 'no'}")
    except Exception as e:
        print(f"endpoint_headers_carry_the_key=not_checked ({type(e).__name__})")
finally:
    if machine is not None:
        machine.delete()
        print("deleted=yes")

print("result=" + ("sdk_ok" if not fails else "sdk_failed"))
sys.exit(1 if fails else 0)
```

## Traps, with the observation behind each

Reproduced on smolmachines 1.14.3 with CPython 3.13.9 on macOS arm64, 2026-09-10.

### The distribution is `smolmachines`, the module is `smol`

```
pip install smolmachines        # succeeds
python -c "import smolmachines" # ModuleNotFoundError: No module named 'smolmachines'
python -c "import smol"         # works, smol.__version__ == 1.14.3
```

Nothing in the install output says so.

### A fresh python.org interpreter cannot reach the API

```
SmolError: cloud request failed: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed:
unable to get local issuer certificate (_ssl.c:1032)
```

The SDK uses `urllib` and depends on no `certifi`, and a python.org framework build ships no
trust store, so **every** cloud call fails this way on a fresh venv. It reads like an API outage.

```bash
pip install certifi
export SSL_CERT_FILE="$(python -m certifi)"
```

After which the same call reaches the API and returns a normal error:

```
SmolError: cloud GET /v1/machines/mach-does-not-exist → 404: machine not found
[request id: 30b220d3-...]
```

Note the **request id** in that message: it is worth keeping when reporting a problem.

### `command` must be a list, and a string fails silently

`MachineConfig(command="echo hi")` is accepted with no validation. The workload then never runs.
The same value sent to the API directly is rejected with a 422, so the SDK is the more permissive
of the two and the failure moves from the create call to somewhere much later.

With a declared port it surfaces after the readiness timeout as
`not ready after 120.0s (state=started)`, which names readiness and not the command, and bills
for the wait.

### `exec` returns for a failed command

```python
bad = machine.exec(["sh", "-c", "echo boom >&2; exit 42"])
bad.success     # False
bad.exit_code   # 42
```

No exception is raised. A `try/except` around `exec` catches transport errors only, so a program
that relies on exceptions treats every guest failure as a success. Use `assert_success()`, which
raises `ExecutionError`, or read `success`.

### `id` and `name` are properties, the rest are methods

`machine.id` and `machine.name` take no parentheses. `state()`, `ready()`, `ready_at()`, `url()`,
`usage()`, `endpoint(port)`, `exec()`, `read_file()`, `write_file()`, `delete()` and
`exec_stream()` are all calls. Calling a property raises `TypeError: 'str' object is not
callable`, which does not point at the cause.

`endpoint()` also requires a `port` argument.

### `read_file` returns bytes while `exec().stdout` is text

```python
machine.read_file("/workspace/rt.txt")   # b'ROUNDTRIP'
machine.exec([...]).stdout               # 'SDK_OK\n'
```

Two different types from the same object, so a helper that handles both needs to know which it
has.

### `endpoint(port).headers` carries the API key

Confirmed by inspection: the headers contain the `smk_` credential. Anything that logs an
endpoint, or embeds one in an error message, logs the key.

### `fork` and `branch` take the child's name as a required argument

```python
Machine.fork(self, name, ports=None, *, checkpointable=False)
Machine.branch(self, name, ports=None, *, branchable=False, checkpointable=None)
```

Calling `m.fork()` raises `TypeError: missing 1 required positional argument: 'name'`, which is a
client-side error and not the server refusing. The machine also has to have been created with
`forkable=True` or `branchable=True`.

Earlier material recorded `fork()` failing with a server 500 that returned a raw Postgres
statement. **That no longer reproduces**: on 2026-09-10 both fork and branch succeeded and the
branch child ran a command.

### `exec_stream()` works on cloud

The reference page says the streaming variant is local only. It returns lines from a cloud machine.

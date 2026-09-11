---
name: "sdk-python"
description: "Drives smol cloud machines from Python with the smolmachines SDK, from install through create, exec, files and delete. Use when a Python program or agent tool needs to run code in a machine; when the import fails after a successful install; when every call fails with a certificate error on a fresh interpreter; when an exec that failed did not raise; or when a machine config field seems to be ignored. Do not use it for the Node SDK or for raw HTTP, which have their own packets, and do not use it to install the CLI or mint a key."
---

# Driving smol cloud from Python

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

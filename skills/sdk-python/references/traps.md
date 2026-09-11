# Traps, with the observation behind each

Reproduced on smolmachines 1.14.3 with CPython 3.13.9 on macOS arm64, 2026-09-10.

## The distribution is `smolmachines`, the module is `smol`

```
pip install smolmachines        # succeeds
python -c "import smolmachines" # ModuleNotFoundError: No module named 'smolmachines'
python -c "import smol"         # works, smol.__version__ == 1.14.3
```

Nothing in the install output says so.

## A fresh python.org interpreter cannot reach the API

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

## `command` must be a list, and a string fails silently

`MachineConfig(command="echo hi")` is accepted with no validation. The workload then never runs.
The same value sent to the API directly is rejected with a 422, so the SDK is the more permissive
of the two and the failure moves from the create call to somewhere much later.

With a declared port it surfaces after the readiness timeout as
`not ready after 120.0s (state=started)`, which names readiness and not the command, and bills
for the wait.

## `exec` returns for a failed command

```python
bad = machine.exec(["sh", "-c", "echo boom >&2; exit 42"])
bad.success     # False
bad.exit_code   # 42
```

No exception is raised. A `try/except` around `exec` catches transport errors only, so a program
that relies on exceptions treats every guest failure as a success. Use `assert_success()`, which
raises `ExecutionError`, or read `success`.

## `id` and `name` are properties, the rest are methods

`machine.id` and `machine.name` take no parentheses. `state()`, `ready()`, `ready_at()`, `url()`,
`usage()`, `endpoint(port)`, `exec()`, `read_file()`, `write_file()`, `delete()` and
`exec_stream()` are all calls. Calling a property raises `TypeError: 'str' object is not
callable`, which does not point at the cause.

`endpoint()` also requires a `port` argument.

## `read_file` returns bytes while `exec().stdout` is text

```python
machine.read_file("/workspace/rt.txt")   # b'ROUNDTRIP'
machine.exec([...]).stdout               # 'SDK_OK\n'
```

Two different types from the same object, so a helper that handles both needs to know which it
has.

## `endpoint(port).headers` carries the API key

Confirmed by inspection: the headers contain the `smk_` credential. Anything that logs an
endpoint, or embeds one in an error message, logs the key.

## `fork` and `branch` take the child's name as a required argument

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

## `exec_stream()` works on cloud

The reference page says the streaming variant is local only. It returns lines from a cloud machine.

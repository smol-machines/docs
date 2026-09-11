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

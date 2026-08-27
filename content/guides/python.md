---
title: Run Python
---

# Run Python

Use the local CLI for shell commands and scripts. Use the Python SDK when a Python application needs to create and control machines.

## Run Python from the local CLI

This starts an ephemeral microVM from the official Python image, prints the result, and deletes the machine when the command exits:

```bash
smolvm machine run --image python:3.12-alpine -- \
  python3 -c "print(2 ** 10)"
```

Add `--net` only when the workload needs network access:

```bash
smolvm machine run --net --image python:3.12-alpine -- \
  python3 -m pip install httpx
```

For repeated work, use a persistent machine:

```bash
smolvm machine create --name py-dev --net --image python:3.12-alpine
smolvm machine start --name py-dev
smolvm machine exec --name py-dev -- python3 -m pip install pytest
smolvm machine exec --name py-dev -- python3 -m pytest
smolvm machine stop --name py-dev
```

Installed packages and filesystem changes survive stop and start. Delete the machine when you no longer need it:

```bash
smolvm machine delete --name py-dev
```

## Run Python from the SDK

Install the SDK:

```bash
pip install smolmachines
```

The local transport embeds the smolvm engine in the Python process. It does not require `smolvm serve`.

```python
from smol import ConnectOptions, Machine, MachineConfig, ResourceSpec

config = MachineConfig(
    resources=ResourceSpec(cpus=2, memory_mb=1024, network=False)
)

with Machine.create(config, ConnectOptions(target="local")) as machine:
    result = machine.run(
        "python:3.12",
        ["python", "-c", "print(2 ** 10)"],
    ).assert_success()
    print(result.stdout)
```

The context manager deletes the local machine on exit. For a cloud machine, pass `ConnectOptions(target="cloud")` and set `SMOL_CLOUD_TOKEN`; see [Use SDK on Cloud](/docs/sdk/with-cloud) for lifecycle and readiness details.

## Run a local project

Mount only the directory the guest needs:

```bash
smolvm machine run --image python:3.12-alpine \
  --volume "$PWD:/app:ro" -- \
  sh -c "cd /app && python3 main.py"
```

Use a writable mount only when the workload must change host files. A mounted directory is intentionally available to guest code and is outside the machine's disposable filesystem.

## Prebuild dependencies

If setup dominates runtime, create a reusable artifact:

```bash
smolvm pack create --image python:3.12-alpine -o python312
./python312 run -- python3 --version
```

For project-specific dependencies, put the image, initialization commands, resources, and entrypoint in a Smolfile, then create a pack from that file.

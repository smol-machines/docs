---
title: Pack and .smolmachine CLI
---

# Pack and .smolmachine CLI

`smolvm pack create` turns an OCI image or a stopped persistent VM into a reusable machine artifact.

For an output path such as `./python312`, pack creation produces:

- `python312`: a platform-specific launcher stub with the VM runtime
- `python312.smolmachine`: the VM payload containing the root filesystem, OCI layers, and storage

Keep both files when distributing the launcher form.

## Pack from an OCI image

```bash
smolvm pack create --image python:3.12-alpine -o ./python312
./python312 run -- python3 --version
```

The direct launcher run is ephemeral. Each run starts from the packed state and is cleaned up on exit.

You can also run a payload through the installed CLI:

```bash
smolvm pack run --sidecar ./python312.smolmachine -- python3 --version
```

## Pack a stopped machine

Use a persistent machine when setup requires multiple commands:

```bash
smolvm machine create --name app --image python:3.12-alpine --net
smolvm machine start --name app
smolvm machine exec --name app -- pip install requests
smolvm machine stop --name app
smolvm pack create --from-vm app -o ./app
```

Stop the machine before packing it. The artifact captures durable disk state. It does not capture live RAM, running processes, or open connections.

## Create a persistent machine from an artifact

```bash
smolvm machine create --name app-dev --from ./app.smolmachine
smolvm machine start --name app-dev
smolvm machine exec --name app-dev -- python3 -c "import requests"
smolvm machine stop --name app-dev
```

This path gives the artifact a normal named-machine lifecycle. Changes made through `machine exec` persist across stop/start cycles.

## Launcher daemon mode

The generated launcher also has a persistent daemon mode:

```bash
./app start
./app exec -- python3 -c "print('hello')"
./app stop
```

In launcher daemon mode, `/workspace` persists across `exec` and stop/start. OCI container overlay changes, including package installs, reset for each `exec`. Use `machine create --from` when the full machine filesystem must remain writable and persistent.

## Architecture compatibility

The payload can move between supported host operating systems when the host architecture matches. An arm64 artifact requires an arm64 host; an x86_64 artifact requires an x86_64 host. The launcher stub is specific to the host platform that created it, so use a launcher built for the destination platform or run the `.smolmachine` payload with an installed compatible `smolvm`.

The manifest records the guest platform, host platform, creation time, and smolvm version. Cross-architecture restore is not supported.

## Disk state, RAM, and migration

A `.smolmachine` is a disk artifact. It packages the prepared filesystem and storage needed to start another machine. It is not:

- A live-memory snapshot
- A capture of running processes
- A live migration stream
- A way to move an active VM between hosts without stopping it

For a local-to-cloud move, stop and pack the machine, then use an artifact deployment path supported by the destination. Live migration of a running local machine is not part of this workflow.

## Registry

Use the registry to discover and transfer published `.smolmachine` artifacts:

```bash
smolvm pack pull registry.smolmachines.com/library/alpine:latest \
  -o alpine.smolmachine
```

See [Cloud Registry](/docs/cloud/registry) for artifact names, authentication, publishing, and cloud availability. Registry support does not make incompatible architectures interchangeable.

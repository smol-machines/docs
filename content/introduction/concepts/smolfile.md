---
title: Smolfile
---

# Smolfile

A Smolfile is a TOML file that describes a machine environment. It keeps the image, resources, networking, development mounts, initialization, ports, and selected capabilities in one reviewable configuration.

## What belongs in a Smolfile

Use a Smolfile for settings that should be reproducible across machine creation:

```toml
image = "python:3.12-alpine"
cpus = 4
memory = 8192
net = true

[network]
allow_hosts = ["pypi.org"]

[dev]
volumes = ["./src:/app"]
init = ["pip install -r requirements.txt"]
ports = ["8080:8080"]

[auth]
ssh_agent = true
```

`memory` is measured in MiB. The keys are top-level fields; there is no `[vm]` table. Host mounts use `[dev].volumes`, not a `[mounts]` table.

## Configuration and state

A Smolfile describes how to prepare and connect a machine. It is not the machine's persistent disk and does not contain its RAM.

Initialization commands prepare an environment during the relevant create or run workflow. After preparation, a [pack](/docs/introduction/concepts/packs-and-smolmachine) can capture the resulting disk state for reuse. External volumes remain runtime attachments.

Secret declarations resolve host references into guest values. Those values enter the guest as plaintext. See [Isolation, networking, and credentials](/docs/introduction/concepts/isolation-networking-credentials) before adding credentials.

## Interfaces

The `smolvm` CLI can create and run local machines from a Smolfile. The `smol` CLI also provides Smolfile workflows. SDK configuration expresses the same machine concepts through language-native objects.

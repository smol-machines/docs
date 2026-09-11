# Skill packets for smol machines

Task-scoped procedures for agents working with smol machines. Each packet is one directory:
`SKILL.md` is the procedure, `scripts/` are wrappers over the public CLI and API, and
`references/` holds the traps and the per-platform arms.

Every packet was run end to end against the shipped product, and each one says which steps were
not run and on which platforms. The `SKILL.md` header names the versions it was verified on;
check those against what you have installed before trusting a step.

**The packets in this directory cover smol cloud and the SDKs.** The packets for the local
`smolvm` runtime live in the [smolvm repository](https://github.com/smol-machines/smolvm) under
`skills/`, because they version with that binary. This file routes a task to whichever is right.

## Find the packet for your task

### Running things locally, on your own machine

These live in `smol-machines/smolvm` under `skills/<name>/`.

| Your task | Packet |
|---|---|
| Install smolvm and prove the host can boot a VM | `install` |
| Run untrusted code with no network, against a read-only repo | `sandbox` |
| Keep a development machine you re-enter across sessions | `dev-env` |
| Run a Docker daemon inside a machine | `docker-in-machine` |
| Drive the local runtime over HTTP | `local-api` |
| Run CUDA workloads against a host NVIDIA GPU | `gpu-cuda` |
| Stop everything and prove the host is clean | `teardown` |

### Running things on smol cloud

In this directory.

| Your task | Packet |
|---|---|
| Point an agent at a cloud account and prove one call works | [`cloud-auth`](./cloud-auth/SKILL.md) |
| Create a machine, exec, move files, restart it, delete it | [`cloud-machine`](./cloud-machine/SKILL.md) |
| Pull or push an artifact and run a machine from it | [`cloud-registry`](./cloud-registry/SKILL.md) |
| Handle the API's failures, including the ones that return 200 | [`cloud-errors`](./cloud-errors/SKILL.md) |
| Find out what a run cost | [`cloud-usage`](./cloud-usage/SKILL.md) |
| Scope a machine's egress, or publish a port | **not yet available**, see below |

### Driving machines from code

In this directory. Both target smol cloud.

| Your task | Packet |
|---|---|
| Drive machines from Python | [`sdk-python`](./sdk-python/SKILL.md) |
| Drive machines from Node | [`sdk-node`](./sdk-node/SKILL.md) |

## Start here if you are new

`cloud-auth` first: every other cloud packet assumes the credential it establishes, and it
carries the scope list that decides whether a later task can pass at all. Then `cloud-machine`,
which is the lifecycle everything else is built on.

If you would rather watch the runtime work before reading a procedure, the
[agent quickstart](https://smolmachines.com/docs/guides/agent-quickstart) installs smolvm and
exercises branching and checkpoints end to end in one runnable block. The packets are the same
ground as procedures, with a preflight that checks the host first and a cleanup that proves it
afterwards.

For local work, `install` in the smolvm repository plays the same role, and `teardown` is the
cleanup every other local packet borrows.

## What has no packet yet, and why

A packet is written only when the procedure behind it can be run end to end and its result
trusted. These are deliberately absent rather than overlooked.

| Task | Why there is no packet |
|---|---|
| Scoping egress, publishing ports | The behaviour a packet would have to route around is not resolved, so a packet would teach a workaround with no end date. Until then, prefer an explicit allow list over a blanket deny, and read `cloud-machine`'s notes on published ports |
| Cloud volumes | The feature is not built. A create request carrying `mounts` is accepted and produces a machine silently missing its storage |
| Empty folder to a deployed tool in three commands | The documented route does not currently complete on every host |
| Headless browsing on cloud | A browser in a cloud machine renders nothing, and the cause is narrowed rather than found |
| Anything behind the console sign-in | Account creation and key minting are human steps by design. The packets start where a person hands an agent a key |
| Checkpoint a running machine and restore it | **Not yet available.** The local CLI does this today and the agent quickstart runs it end to end, but no packet covers it: nothing here has exercised `machine checkpoint`, and on cloud the capability is advertised with no route in the published spec |

## Conventions every packet here follows

- **Assert values, never exit codes or HTTP status.** A guest command that exited 42 comes back
  as HTTP 200, and `smol auth status` exits 0 when logged out. Both are covered in the packets
  that meet them first.
- **Scripts wrap the public interfaces.** They edit no configuration, escalate no privilege, and
  delete only what they created, matched by an id they recorded or by the `smolskill-` name
  prefix.
- **Waits poll for a value.** A control plane reports a machine started before the guest can run
  anything, so a fixed sleep is wrong in both directions.
- **Cleanup takes the bill.** Deleting a cloud machine with `?includeUsage=true` returns the
  settled cost, and the cleanup scripts assert a spend ceiling rather than assuming one.
- **Nothing prints a credential.** Keys are read from the environment and passed in a header.

## Using a packet with an agent

An agent with no skill discovery needs nothing: read `skills/<name>/SKILL.md` when the task
matches the packet's description.

An agent that scans a fixed path needs this directory linked to that path, which is a local
choice and is deliberately not committed here. Paths change, so check your agent's own
documentation rather than trusting a list.

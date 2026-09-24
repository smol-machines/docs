---
title: Skill Packets
---

# Skill Packets

A skill packet is a task-scoped procedure for smol machines, written for an agent to load when that task comes up. Each page below carries one packet whole: the procedure, the scripts it runs in the order it runs them, and the traps that cost the most time on the way.

## Which packet

Find the task, then read the one page it names. Each packet was run end to end against the shipped product, and its procedure opens with the versions it was verified on; check those against what you have installed before trusting a step.

### Running things locally, with smolvm

| Your task | Packet | Not for | Verified on |
|---|---|---|---|
| Install smolvm and prove the host can boot a VM | [install](/docs/guides/skills/install) | Removing an install; anything after the first boot | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Stop everything and prove the host is clean | [teardown](/docs/guides/skills/teardown) | Deleting machines another session created | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run untrusted code with no network, against a read-only repo | [sandbox](/docs/guides/skills/sandbox) | A machine you re-enter; Docker in a machine; installing smolvm | smolvm v1.14.6 on Linux aarch64 and macOS arm64 |
| Keep a development machine you re-enter across sessions | [dev-env](/docs/guides/skills/dev-env) | Untrusted code; Docker in a machine | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Drive the local runtime over HTTP | [local-api](/docs/guides/skills/local-api) | Replacing the CLI in a shell script; binding beyond loopback | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run a Docker daemon inside a machine | [docker-in-machine](/docs/guides/skills/docker-in-machine) | Running OCI images, which need no Docker; Windows | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run CUDA workloads against a host NVIDIA GPU | [gpu-cuda](/docs/guides/skills/gpu-cuda) | Vulkan graphics (`--gpu`); a Mac, which has no NVIDIA GPU | smolvm v1.14.6 on Linux x86_64 (A10) and Windows x86_64 (RTX 4050) |
| Ship a prepared machine to another host as one file | [pack](/docs/guides/skills/pack) | A machine you re-enter; untrusted code | smolvm v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |

### Running things on smol cloud

| Your task | Packet | Not for | Verified on |
|---|---|---|---|
| Point an agent at a cloud account and prove one call works | [cloud-auth](/docs/guides/skills/cloud-auth) | Creating an account or minting a key; creating machines | smol v1.14.3 and API 0.1.0, macOS arm64 client |
| Create a machine, exec, move files, restart it, delete it | [cloud-machine](/docs/guides/skills/cloud-machine) | Installing the CLI or handing over a key; scoping egress or publishing ports | smol v1.14.3 and API 0.1.0, macOS arm64 client |
| Pull or push an artifact and run a machine from it | [cloud-registry](/docs/guides/skills/cloud-registry) | Creating the artifact from a machine; removing a pushed artifact | smol v1.14.3 and API 0.1.0, macOS arm64 client |
| Handle the API's failures, including the ones that return 200 | [cloud-errors](/docs/guides/skills/cloud-errors) | A normal machine lifecycle; billing suspension or rate limiting | smol v1.14.3 and API 0.1.0, macOS arm64 client |
| Find out what a run cost | [cloud-usage](/docs/guides/skills/cloud-usage) | Tenant usage over an arbitrary window; a leak check | API 0.1.0, macOS arm64 client |
| Scope a machine's egress, or publish a port | Not yet available, see [below](#what-has-no-packet-yet-and-why) | | |

### Driving machines from code

Both target smol cloud.

| Your task | Packet | Not for | Verified on |
|---|---|---|---|
| Drive machines from Python | [sdk-python](/docs/guides/skills/sdk-python) | The Node SDK or raw HTTP; installing the CLI or minting a key | smolmachines 1.14.3, CPython 3.13.9, macOS arm64 |
| Drive machines from Node | [sdk-node](/docs/guides/skills/sdk-node) | The Python SDK or raw HTTP; installing the CLI or minting a key | smolmachines 1.14.3, Node v25.9.0, macOS arm64 |

Every packet page names the platforms in full under its platform arms, including the ones that were not run.

### Start here if you are new

On smol cloud, `cloud-auth` first: every other cloud packet assumes the credential it establishes, and it carries the scope list that decides whether a later task can pass at all. Then `cloud-machine`, which is the lifecycle everything else is built on.

For local work, `install` plays the same role, and `teardown` is the cleanup every other local packet borrows.

To watch the runtime work before reading a procedure, run the [agent quickstart](/docs/guides/agent-quickstart) first: it installs smolvm and exercises branching and checkpoints end to end in one runnable block. The packets cover the same ground as procedures, with a preflight that checks the host first and a cleanup that proves it afterwards.

### What has no packet yet, and why

A packet is written only when the procedure behind it can be run end to end and its result trusted. These are deliberately absent rather than overlooked.

| Task | Why there is no packet |
|---|---|
| Scoping egress, publishing ports | The behaviour a packet would have to route around is not resolved, so a packet would teach a workaround with no end date. Until then, prefer an explicit allow list over a blanket deny, and read `cloud-machine`'s notes on published ports |
| Cloud volumes | The feature is not built. A create request carrying `mounts` is accepted and produces a machine silently missing its storage |
| Empty folder to a deployed tool in three commands | The documented route does not currently complete on every host |
| Headless browsing on cloud | A browser in a cloud machine renders nothing, and the cause is narrowed rather than found |
| Anything behind the console sign-in | Account creation and key minting are human steps by design. The packets start where a person hands an agent a key |
| Checkpoint a running machine and restore it | **Not yet available.** The local CLI does this today and the agent quickstart runs it end to end, but no packet covers it: nothing here has exercised `machine checkpoint`, and on cloud the capability is advertised with no route in the published spec |

## What is on a packet page

| Part | What it is |
|---|---|
| The opening paragraph | The packet's `description`: what it is for, when to reach for it, and what it is not for |
| The procedure | The packet's `SKILL.md`, with the versions and platforms it was verified on in its first line |
| Scripts | Preflight, the lifecycle steps, and cleanup, each under the path the procedure calls it by |
| Traps | Each trap with the observation behind it |

## Why they exist

An agent that already knows the primitives still has to choose defaults, and the safe default is rarely the shortest command. A packet carries the choice: no network until a host is named, a repo mounted read-only, machines deleted by the name prefix the script recorded rather than by pattern.

## Conventions every packet follows

- **Assert values, never exit codes or HTTP status.** A guest command that exited 42 comes back as HTTP 200, and `smol auth status` exits 0 when logged out. Both are covered in the packets that meet them first.
- **Scripts wrap the public interfaces.** They edit no configuration, escalate no privilege, and delete only what they created, matched by an id they recorded or by the `smolskill-` name prefix. They assume nothing about which agent, if any, is driving them.
- **Waits poll for a value.** A control plane reports a machine started before the guest can run anything, so a fixed sleep is wrong in both directions.
- **Cleanup takes the bill.** Deleting a cloud machine with `?includeUsage=true` returns the settled cost, and the cloud cleanup scripts assert a spend ceiling rather than assuming one.
- **Nothing prints a credential.** Keys are read from the environment and passed in a header.

## Load one

An agent with no skill discovery needs nothing installed. Read the page for the task at hand, as Markdown rather than scraped HTML:

```bash
curl -fsSL https://raw.githubusercontent.com/smol-machines/docs/main/guides/skills/sandbox.md
```

The same shape works for any packet: substitute its name for `sandbox`.

To install one for an agent that discovers skills from a directory, make `<skills dir>/<name>/`, write the procedure to `SKILL.md` in it under a frontmatter block carrying the packet's `name` and `description`, and write each script to the path in its heading. The procedure calls the scripts by those relative paths.

## Agent-specific paths

These paths were read from each agent's own documentation on 2026-09-08:

| Agent | Project path | Notes |
|---|---|---|
| Claude Code | `.claude/skills/<name>/SKILL.md` | Also `~/.claude/skills` for personal skills |
| OpenCode | `.opencode/skills/<name>/SKILL.md` | Also accepts `.claude/skills` and the cross-agent `.agents/skills`, walking up to the git worktree root |

::: warning Discovery conventions move
Check the agent's own documentation before trusting a path here. Skill discovery is young, and both the directory names and the frontmatter an agent reads have changed more than once.
:::

---
title: Skill Packets
---

# Skill Packets

A skill packet is a task-scoped procedure for the `smolvm` CLI, written for an agent to load when that task comes up. Each page below carries one packet whole: the procedure, the scripts it runs in the order it runs them, and the traps that cost the most time on the way.

## What is on a packet page

| Part | What it is |
|---|---|
| The opening paragraph | The packet's `description`: what it is for, when to reach for it, and what it is not for |
| The procedure | The packet's `SKILL.md`, with the release and platforms it was verified on in its first line |
| Scripts | Preflight, the lifecycle steps, and cleanup, each under the path the procedure calls it by |
| Traps | Each trap with the measurement behind it |

The scripts are wrappers over the public CLI. They edit no smolvm configuration, escalate no privilege, and delete only the machines they created. They are plain `bash` and assume nothing about which agent, if any, is driving them.

## Why they exist

An agent that already knows the primitives still has to choose defaults, and the safe default is rarely the shortest command. A packet carries the choice: no network until a host is named, a repo mounted read-only, machines deleted by the name prefix the script recorded rather than by pattern.

Each packet was run end to end on a published release, and each one says which steps were not run and on which platforms. The procedure's first line names the release it was verified on, so check that against your installed version before trusting a step.

To watch the runtime work before reading a procedure, run the [agent quickstart](/docs/guides/agent-quickstart) first: it installs smolvm and exercises branching and checkpoints end to end in one block.

## The packets

| Task | Packet | Not for | Verified on |
|---|---|---|---|
| Install smolvm and prove the host boots a VM | [install](/docs/guides/skills/install) | Removing an install; anything after the first boot | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Stop everything and remove smolvm's state | [teardown](/docs/guides/skills/teardown) | Deleting machines another session created | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run untrusted code, no network, repo read-only | [sandbox](/docs/guides/skills/sandbox) | A machine you re-enter; Docker in a machine; installing smolvm | v1.14.6 on Linux aarch64 and macOS arm64 |
| Keep a persistent dev machine across sessions | [dev-env](/docs/guides/skills/dev-env) | Untrusted code; Docker in a machine | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Drive smolvm over its local HTTP API | [local-api](/docs/guides/skills/local-api) | Replacing the CLI in a shell script; binding beyond loopback | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run a Docker daemon inside a machine | [docker-in-machine](/docs/guides/skills/docker-in-machine) | Running OCI images, which need no Docker; Windows | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |
| Run CUDA workloads against a host NVIDIA GPU | [gpu-cuda](/docs/guides/skills/gpu-cuda) | Vulkan graphics (`--gpu`); a Mac, which has no NVIDIA GPU | v1.14.6 on Linux x86_64 (A10) and Windows x86_64 (RTX 4050) |
| Ship a prepared machine to another host as one file | [pack](/docs/guides/skills/pack) | A machine you re-enter; untrusted code | v1.16.1 on macOS arm64, v1.14.6 on Linux aarch64 |

Every packet page names the platforms in full under its platform arms, including the arms recorded from an earlier run rather than re-run.

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

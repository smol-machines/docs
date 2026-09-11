---
title: Skill Packets
---

# Skill Packets

A skill packet is a task-scoped procedure for the `smolvm` CLI, written for an agent to load when that task comes up. The packets live in the [smolvm](https://github.com/smol-machines/smolvm) repository under `skills/`, one directory per use case. This page is the catalog; the packets themselves are not copied here.

## What is in a packet

Each directory holds three things:

| Part | What it is |
|---|---|
| `SKILL.md` | The procedure, with `name` and `description` frontmatter |
| `scripts/` | Preflight, the lifecycle steps, and cleanup |
| `references/` | Traps and per-platform arms, read when the situation calls for them |

The scripts are wrappers over the public CLI. They edit no smolvm configuration, escalate no privilege, and delete only the machines they created. They are plain `bash` and assume nothing about which agent, if any, is driving them.

## Why they exist

An agent that already knows the primitives still has to choose defaults, and the safe default is rarely the shortest command. A packet carries the choice: no network until a host is named, a repo mounted read-only, machines deleted by the name prefix the script recorded rather than by pattern.

Each packet was run end to end on a published release, and each one says which steps were not run and on which platforms. The `SKILL.md` header names the release it was verified on, so check that against your installed version before trusting a step.

To watch the runtime work before reading a procedure, run the [agent quickstart](/docs/guides/agent-quickstart) first: it installs smolvm and exercises branching and checkpoints end to end in one block.

## The packets

| Task | Packet | Not for | Verified on |
|---|---|---|---|
| Install smolvm and prove the host boots a VM | [install](/docs/local/skills/install) | Removing an install; anything after the first boot | macOS arm64, Linux aarch64; Intel Mac stated unverified |
| Stop everything and remove smolvm's state | [teardown](/docs/local/skills/teardown) | Deleting machines another session created | macOS arm64, Linux aarch64 |
| Run untrusted code, no network, repo read-only | [sandbox](/docs/local/skills/sandbox) | A machine you re-enter; Docker in a machine; installing smolvm | Linux aarch64, macOS arm64 |
| Keep a persistent dev machine across sessions | [dev-env](/docs/local/skills/dev-env) | Untrusted code; Docker in a machine | Linux aarch64, macOS arm64 |
| Drive smolvm over its local HTTP API | [local-api](/docs/local/skills/local-api) | Replacing the CLI in a shell script; binding beyond loopback | macOS arm64, Linux aarch64 |
| Run a Docker daemon inside a machine | [docker-in-machine](/docs/local/skills/docker-in-machine) | Running OCI images, which need no Docker; Windows | Linux aarch64, macOS arm64 |
| Run CUDA workloads against a host NVIDIA GPU | [gpu-cuda](/docs/local/skills/gpu-cuda) | Vulkan graphics (`--gpu`); a Mac, which has no NVIDIA GPU | Linux x86_64 and Windows x86_64, each on one GPU, not re-run |

Every packet page names the platforms in full, including the arms that were recorded from an earlier run rather than re-run.

## Install one

The [`skills`](https://github.com/vercel-labs/skills) CLI copies a packet from the repository into the directory your agent reads:

```bash
npx skills add smol-machines/smolvm --skill sandbox
```

List what is there before choosing:

```bash
npx skills add smol-machines/smolvm --list
```

Name the agent with `-a`:

```bash
npx skills add smol-machines/smolvm --skill sandbox -a claude-code
```

The packet lands under that agent's project skills directory, with its `scripts/` and `references/` alongside `SKILL.md`. Its [README](https://github.com/vercel-labs/skills#supported-agents) listed 78 `--agent` values on 2026-09-10; read it for the current set and the path each one uses.

## Read one without installing

An agent with no skill discovery needs nothing installed. Read `skills/<name>/SKILL.md` from the repository when the task matches the packet's description:

```bash
curl -fsSL https://raw.githubusercontent.com/smol-machines/smolvm/main/skills/sandbox/SKILL.md
```

The same shape works for any packet: substitute its name for `sandbox`.

## Agent-specific paths

An agent that scans a fixed path needs `skills/` linked to that path. That link is a local choice and is not committed to the repository. These paths were read from each agent's own documentation on 2026-09-08:

| Agent | Project path | Notes |
|---|---|---|
| Claude Code | `.claude/skills/<name>/SKILL.md` | Also `~/.claude/skills` for personal skills |
| OpenCode | `.opencode/skills/<name>/SKILL.md` | Also accepts `.claude/skills` and the cross-agent `.agents/skills`, walking up to the git worktree root |

To expose the packets to an agent that scans `.claude/skills`, once, locally:

```bash
mkdir -p .claude && ln -s ../skills .claude/skills
```

::: warning Discovery conventions move
Check the agent's own documentation before trusting a path here. Skill discovery is young, and both the directory names and the frontmatter an agent reads have changed more than once.
:::

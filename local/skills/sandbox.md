---
title: "Sandbox: run untrusted code in a throwaway machine"
---

# Sandbox: run untrusted code in a throwaway machine

Runs untrusted code in a throwaway smolvm microVM against a repo it must not modify, with no network unless explicitly granted, and collects artifacts from a writable output directory. Use when executing an agent's generated script, a pull request's test suite, or any code that should not be trusted with the host; when a workload needs egress granted one host at a time; or when a sandbox run has to be cancelled, because Ctrl-C leaves the VM running and invisible to the CLI. Do not use it for a development environment that is re-entered across sessions, for running a Docker daemon inside a machine, or for installing smolvm itself, which is the install packet.

## What it does

Five steps: preflight, bake, run, verify, clean up. The bake is the only step that talks to a registry. It happens with the network on and nothing untrusted mounted, before the untrusted code is anywhere near the machine, so that the run itself needs no network at all. That is a materially stronger sandbox than granting egress and hoping.

The run mounts the repository read-only at `/workspace` and the output directory writable at `/out`. It prints an assertion that it used the host cache, which is what proves the bake worked and that the run reached no registry: without it the run pulled, which means it had network. It also records the VM pid, which is the only route back to the machine if the run has to be stopped. Egress is granted one host at a time with `--allow-host`.

Verification has two halves and both are needed, because either alone passes on a broken sandbox. From inside the guest it proves the workload could not write the repo and could not reach the network; from the host it proves the artifact came out and the repo is unchanged. A run that merely exited zero tells you neither.

Cancelling is its own step. `Ctrl-C` is not it: on the cached route the VM outlives the CLI, `machine list` reports `No machines found`, and the VM exits only when the untrusted workload does, which for code that hangs or loops is unbounded exposure at roughly 230 MB per survivor. The packet's cancel kills exactly the VMs its own run step recorded.

## What it checks first

- Everything the [install](/docs/local/skills/install) preflight checks: version, platform, acceleration and access to it
- Mounts plus published ports against the guest's device budget. The guest has eleven IRQs, four `-v` mounts boot and five do not, and every published port costs one of those slots, so a boot that would fail with `no more IRQs are available` is caught before it is attempted
- Whether the offline shape works on this host at all, and the reason when it does not

## What it is not for

A development environment that is re-entered across sessions, which is [dev-env](/docs/local/skills/dev-env). Running a Docker daemon inside a machine, which is [docker-in-machine](/docs/local/skills/docker-in-machine). Installing smolvm itself, which is [install](/docs/local/skills/install).

## Platforms

| Platform | State |
|---|---|
| Linux aarch64 | The network-on route, the cancel path and the reaper were run here. The offline route could not be run |
| Linux x86_64 | The offline route is verified in the material behind the packet, not re-run |
| macOS arm64 | The network-on route was run end to end. The offline shape is unavailable there, and the packet has a macOS page with a route that works |
| Windows x86_64 | Recorded from one earlier run, not re-run. The offline shape is unavailable there for a different reason: the bake never completes |

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill sandbox
```

The procedure is [`skills/sandbox/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/sandbox/SKILL.md). For the lifecycle choice behind it, the read-only mount and the egress allow list, see [Agent Sandboxes and CI](/docs/guides/agent-sandboxes-ci).

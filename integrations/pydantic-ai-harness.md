---
title: Pydantic AI Harness
---

# Pydantic AI Harness

Run a Pydantic AI agent's shell and file tools in a smol machine on your own computer, with the Harness's `SmolSandbox` capability.

- **Package:** [`pydantic-ai-harness`](https://pypi.org/project/pydantic-ai-harness/) with the `smol` extra, 0.56.0 or later
- **Code:** [`smol_sandbox`](https://github.com/pydantic/pydantic-ai/tree/main/src/pydantic_ai_harness/pydantic_ai_harness/smol_sandbox) in Pydantic's pydantic-ai repository, written by Pydantic
- **Runs on:** the local engine, on the computer that runs the agent
- **Issues:** the capability on [pydantic-ai issues](https://github.com/pydantic/pydantic-ai/issues), the machines on [smolvm issues](https://github.com/smol-machines/smolvm/issues)

[Pydantic AI Harness](https://pydantic.dev/docs/ai/harness/) is Pydantic's capability library for Pydantic AI agents. Its `SmolSandbox` capability gives an agent run a smol machine as its workspace, so the tools that use the workspace, such as the shell and file tools of `Coder`, run their commands and file edits inside the machine.

Pydantic wrote the capability and ships it in the Harness. Its full reference is [Smol Sandbox in the Pydantic AI docs](https://pydantic.dev/docs/ai/harness/smol-sandbox/).

## When to use it

- **Agent commands off your computer.** The machine has its own kernel and filesystem. Nothing from your computer is mounted into it, no ports are published, and none of your environment variables reach it.
- **No account.** The machines run on the local engine, so no smol cloud account or key is needed.
- **Work that carries across runs.** The machine stays after a run. A follow-up run given the message history, or a workspace ref you stored, works in the same machine with its files.
- **A machine you prepared.** `SmolSandboxBackend(sandbox=machine)` runs the agent in a `smol.Machine` your code already created, from 0.60.0.

## Requirements

- macOS on Apple Silicon, or Linux on x86_64 or aarch64 with glibc 2.34 or newer and read and write access to `/dev/kvm`. See [Supported platforms](/docs/introduction/concepts/supported-platforms).
- Python 3.11 or newer, and a model provider for the agent.

`smol.local_availability()` checks a host without booting a machine.

## Set up

Install the Harness with the `smol` extra and your model provider's extra:

```bash
pip install "pydantic-ai-harness[smol,anthropic]"
```

The `smol` extra installs the `smolmachines` SDK, which bundles the local engine, so there is no separate `smolvm` install.

Add `SmolSandbox` next to the tools that use it:

```python
from pydantic_ai import Agent
from pydantic_ai_harness.coder import Coder
from pydantic_ai_harness.smol_sandbox import SmolSandbox

agent = Agent('anthropic:claude-opus-5-5', capabilities=[SmolSandbox(image='python:3.12-alpine'), Coder()])
result = agent.run_sync('Write a script that prints the first 10 primes, and run it.')
```

The machine boots on the run's first use of the workspace. Without an `image` it runs smolvm's own Alpine Linux, which has no Python. An `image` is any OCI image, pulled on your computer the first time it is used. Commands start in `/workspace`.

To continue in the same machine, pass the message history, or store `result.workspace.ref` and pass it back as `workspace=`:

```python
followup = agent.run_sync('Now make it print the first 100.', message_history=result.all_messages())
```

## Clean up

A run never deletes its machine, and there is no idle or lifetime limit. Delete it with the ref you stored:

```python
from pydantic_ai.workspaces import WorkspaceRef
from pydantic_ai_harness.smol_sandbox import SmolSandbox


async def delete_vm(ref: WorkspaceRef) -> None:
    await SmolSandbox().destroy(ref)
```

Booting a machine logs its id at INFO on the `pydantic_ai_harness.smol_sandbox._backend` logger, so a machine left behind by a run that never stored its ref can still be found.

## What to know

- The capability always connects with `target='local'`, so smol cloud credentials in the environment do not move it to smol cloud.
- A new machine has no network access. `allow_internet_access=True` gives it outbound access with no allowlist. The capability does not expose smolvm's host and CIDR allowlists. See [Isolation, networking and credentials](/docs/introduction/concepts/isolation-networking-credentials).
- Files move through the shell, 64 KiB per command, so reading or writing a file of several MiB takes seconds.
- The backend needs the asyncio event loop. Under Trio, operations raise `UserError`.
- Treat a ref as trusted input. A ref from the message history opens only machines the capability booted, named `pydantic-ai-` and 32 hex digits. `SmolSandboxBackend(ref=...)` opens any machine of your OS user by name, so do not build one from user input.

## Links

- [Smol Sandbox in the Pydantic AI docs](https://pydantic.dev/docs/ai/harness/smol-sandbox/)
- [pydantic-ai v2.56.0 release notes](https://github.com/pydantic/pydantic-ai/releases/tag/v2.56.0), where `SmolSandbox` first shipped
- [Machine API](/docs/sdk/machine-api), the SDK the capability builds on

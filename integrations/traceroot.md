---
title: traceroot
---

# traceroot

Run the sandboxes of traceroot's AI agent in smol machines, on smol cloud or on your own computer.

- **Package:** traceroot's agent service, which pins the [`smolmachines`](https://www.npmjs.com/package/smolmachines) Node SDK at 1.36.1
- **Code:** [`frontend/ee/agent/src/executors/smol.ts`](https://github.com/traceroot-ai/traceroot/blob/main/frontend/ee/agent/src/executors/smol.ts) in traceroot's repository, written by smol machines
- **Runs on:** smol cloud by default, or the local engine with `SMOL_TARGET=local`
- **Issues:** the provider on [traceroot issues](https://github.com/traceroot-ai/traceroot/issues), the machines on [smolvm issues](https://github.com/smol-machines/smolvm/issues)

[traceroot](https://traceroot.ai) is an open-source platform for tracing and improving AI agents. Its AI agent investigates failures: it clones your repository into a sandbox, reads the code where an error happened, and runs commands there. `SANDBOX_PROVIDER` chooses where those sandboxes run, `docker` by default. `smol` runs each session's sandbox in a smol machine, a microVM with its own Linux kernel.

The agent creates the machine the first time a session needs its sandbox, from `ubuntu:24.04` with outbound network access. Setup installs Git, jq and curl with `apt-get` and makes the agent's folders under `/workspace`. The agent deletes the machine when the session is deleted or the agent shuts down.

## When to use it

- **A VM boundary around cloned code.** The repository the agent clones and every command it runs stay in a machine with its own kernel.
- **A hosted sandbox for a self-hosted traceroot.** On smol cloud, the computer that runs the agent needs only a smol cloud API key.
- **Local machines for development.** Under `make dev` on Apple Silicon or Linux with KVM, `SMOL_TARGET=local` boots the machines on your computer, with no account.

## Requirements

- traceroot run from its repository, with `make dev` or the Docker Compose stack (`make prod` or `make prod-lite`), and a model provider key for the agent. See [Self-Hosting in the traceroot docs](https://traceroot.ai/docs/developer/self-hosting).
- For smol cloud: a smol cloud API key. Create one under [API Keys](/console/keys), as the [Cloud Quick Start](/docs/cloud) describes.
- For the local engine: `make dev` on macOS on Apple Silicon, or on Linux on x86_64 or aarch64 with glibc 2.34 or newer and read and write access to `/dev/kvm`. See [Supported platforms](/docs/introduction/concepts/supported-platforms). The engine is installed with traceroot's dependencies, as part of the `smolmachines` package.

## Set up

traceroot reads its settings from `.env` at the root of its repository, which `make dev` and `make prod` copy from `.env.example` the first time. That file sets `SANDBOX_PROVIDER=docker` and has the smol lines commented out. For smol cloud, change the first and uncomment `SMOL_CLOUD_TOKEN` so they read:

```bash
SANDBOX_PROVIDER=smol
SMOL_CLOUD_TOKEN=smk_your_key_here
```

Any `SMOL_TARGET` other than `local`, or none, uses smol cloud. For the local engine, under `make dev`:

```bash
SANDBOX_PROVIDER=smol
SMOL_TARGET=local
```

The agent reads these when it starts, so start traceroot with `make dev` or `make prod`, or restart it if it is running. To check, ask the agent to run `uname -a` in its sandbox. Once the machine is set up, the agent's log prints `[SmolExecutor] Machine ready:` and the machine's name. Under `make dev` the log is in the Agent window; with Docker Compose, read it with `docker compose -f docker-compose.prod.yml logs -f agent`.

## What to know

- **Docker Compose uses smol cloud only.** `docker-compose.prod.yml` passes `SANDBOX_PROVIDER` and `SMOL_CLOUD_TOKEN` to the agent container, and not `SMOL_TARGET`, so the agent in that stack always uses smol cloud.
- **Cloud machines stop after 15 minutes idle and are deleted after 24 hours.** A stopped machine starts again on the session's next command, with `/workspace` and the installed packages kept and `/tmp` emptied ([paths that do not persist](/docs/cloud/lifecycle-storage-networking#paths-that-do-not-persist)). The delete comes 24 hours after creation even while the session is in use. After it, that session's sandbox commands fail, and a new session gets a new machine. See [Automatic cleanup](/docs/cloud/lifecycle-storage-networking#automatic-cleanup).
- **traceroot's sandbox sweep is for `docker` only.** `SANDBOX_IDLE_TTL_MINUTES` and `SANDBOX_RECLAIM_ON_START` do not touch smol machines, so a cloud machine stays until its session is deleted, the agent shuts down or 24 hours pass. Until it is deleted, a stopped machine bills its disk and counts toward your plan's machine limit ([Plan limits](/docs/cloud/api-reference#plan-limits)). If the agent is killed, delete its machines from the [console](/console) rather than wait out the 24 hours.
- **Machine size.** The agent sets no size, so a cloud machine gets the default of 4 vCPUs and 8192 MB of memory ([Machines](/docs/cloud/api-reference#machines)).
- **The network is open.** Commands the agent runs can reach any host. See [Isolation, networking and credentials](/docs/introduction/concepts/isolation-networking-credentials).
- **Local machines.** The 15 minute stop and the 24 hour delete apply on smol cloud only. A local machine normally ends with the agent process.
- **A failed setup starts over.** If creating the folders or installing the tools fails, the agent deletes the machine and reports the command and its output, and the session's next sandbox call creates a new machine.

## Links

- [The sandbox settings in traceroot's `.env.example`](https://github.com/traceroot-ai/traceroot/blob/main/.env.example)
- [The traceroot Agent in the traceroot docs](https://traceroot.ai/docs/ai-agent/overview)
- [traceroot #3323](https://github.com/traceroot-ai/traceroot/pull/3323), the pull request that added the provider

---
title: sweeper by The Paper Compute Company
---

# sweeper by The Paper Compute Company

Run sweeper's Claude Code lint-fixing agents in a smol machine, with your Anthropic key kept on the host.

- **Package:** sweeper, built from source with `go install`
- **Code:** [`pkg/vm/smol.go`](https://github.com/pcc-labs/sweeper/blob/main/pkg/vm/smol.go) in The Paper Compute Company's sweeper repository, written by The Paper Compute Company
- **Runs on:** the local engine, through the `smolvm` CLI on the computer that runs sweeper
- **Issues:** the backend on [sweeper issues](https://github.com/pcc-labs/sweeper/issues), the machines on [smolvm issues](https://github.com/smol-machines/smolvm/issues)

[sweeper](https://github.com/pcc-labs/sweeper) is The Paper Compute Company's open-source command-line tool for code maintenance. It runs a linter on your project, groups the findings by file, and hands each file to a one-shot coding agent. Its `--vm-backend smol` option runs those agents in a smol machine.

With the smol backend, sweeper creates one machine for the run from an OCI image, mounts the project at `/workspace`, and runs each agent there as `claude --print`. The Anthropic key is bound as a credential: the guest holds a placeholder, and the host puts the real key only into HTTPS requests to `api.anthropic.com`. When the run ends, sweeper stops the machine and deletes it.

## When to use it

- **The key stays out of the machine.** In the guest, `ANTHROPIC_API_KEY` holds a value that starts with `SMOL_PLACEHOLDER`, so code the agent runs cannot read the real key.
- **Agents off your host.** The agents run as root in the guest with `--dangerously-skip-permissions`. The only folder from your computer they see is the project, mounted at `/workspace`.
- **The image you choose.** `--vm-image` takes any OCI image, so the agents can work with your project's toolchain.

## Requirements

- macOS on Apple Silicon, or Linux with KVM (`/dev/kvm`). See [Supported platforms](/docs/introduction/concepts/supported-platforms).
- The `smolvm` CLI on `PATH`. See [Local](/docs/local) to install it.
- Go, to build sweeper.
- `ANTHROPIC_API_KEY` set on the host. sweeper refuses to boot the machine without it.

The default image is `node:22-bookworm-slim`, and the machine installs Claude Code when it starts if the image does not have it. Pass `--vm-image` with an image that has Claude Code installed to skip that step.

## Set up

Install sweeper:

```bash
go install github.com/papercomputeco/sweeper@latest
```

With `ANTHROPIC_API_KEY` set in your shell, pass `--vm-backend smol` and the lint command after `--`:

```bash
sweeper run --vm-backend smol -c 5 -- npm run lint
```

`--vm-backend smol` implies `--vm`. To set it in `.sweeper/config.toml` instead, use `[vm] backend = "smol"`. Two more flags apply to the smol backend:

```bash
sweeper run --vm-backend smol --vm-image ghcr.io/acme/agent:1 -- npm run lint   # your own image
sweeper run --vm-backend smol --vm-name my-smol -- npm run lint                 # a machine you manage
```

With `--vm-name`, sweeper runs in your existing machine and does not stop or delete it.

Inside a machine the agent is always Claude Code, whatever `--provider` is set to, and sweeper prints a warning when the provider is another one.

## What to know

- sweeper's README describes a VM for each sub-agent. The smol backend boots one machine for the whole run, and the agents running at once (`-c`) share its CPU, memory and `/workspace`.
- sweeper passes no machine size, so the machine gets smolvm's defaults, 4 vCPUs and 8192 MiB of memory.
- The machine has open outbound network access. The credential binding turns networking on, and sweeper passes no host allowlist, so the agents can reach any host, not only `api.anthropic.com`. See [Isolation, networking and credentials](/docs/introduction/concepts/isolation-networking-credentials).
- The project is mounted read-write, so the agents' edits land in it as they happen.
- When stdin is not a terminal, as in CI or an agent's shell, sweeper reads it as linter output and refuses a `--` command. Run it with `</dev/null`.
- When `machine stop` fails, sweeper does not delete the machine, and a killed run cannot clean up. sweeper's machines are named `sweeper-` and eight hex digits. List them with `smolvm machine ls` and delete each with `smolvm machine delete --name <name> --force`.

## Links

- [VM isolation in the sweeper README](https://github.com/pcc-labs/sweeper#vm-isolation)
- [Credential substitution](/docs/introduction/concepts/isolation-networking-credentials#credential-substitution), the mechanism that keeps the key on the host
- [Credentials skill](/docs/guides/skills/credentials), to check for yourself that a key stayed out of a machine

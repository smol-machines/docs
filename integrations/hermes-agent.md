---
title: Hermes Agent by Nous Research
---

# Hermes Agent by Nous Research

Run Hermes Agent's terminal, file and code tools in a smol machine on your own computer, with the `smolmachines` terminal backend from Hermes's plugin catalog.

- **Package:** the `smolmachines` plugin in [Hermes's plugin catalog](https://hermes-agent.nousresearch.com/docs/plugins), a community plugin for Hermes 0.21.6 or later
- **Code:** [`smol-machines/hermes-smolmachines`](https://github.com/smol-machines/hermes-smolmachines), written and maintained by smol machines
- **Runs on:** the local engine, on the computer that runs Hermes
- **Issues:** the plugin on [hermes-smolmachines issues](https://github.com/smol-machines/hermes-smolmachines/issues), the machines on [smolvm issues](https://github.com/smol-machines/smolvm/issues)

[Hermes Agent](https://hermes-agent.nousresearch.com) is Nous Research's open-source agent. It runs its tools through a terminal backend, chosen with `terminal.backend`: its own include local, Docker, SSH, Modal, Daytona and Vercel Sandbox, and plugins can add more.

The `smolmachines` backend runs those tools in a smol machine: a microVM with its own Linux kernel, booted from an OCI image on the same computer. Hermes itself still runs where it runs today. When it runs a command, writes a file or executes code, that happens in the machine.

## When to use it

- **Agent commands off your computer.** The machine has its own kernel and filesystem, and nothing from your computer is mounted into it.
- **No Docker and no account.** The plugin installs the `smolmachines` SDK, which carries the engine, and every machine runs on the local engine.
- **Work that carries across sessions.** With Hermes's default `terminal.container_persistent`, each session keeps one machine, so its files and installed packages are there the next time.

## Requirements

- macOS on Apple Silicon, or Linux on x86_64 or aarch64 with glibc 2.34 or newer and access to `/dev/kvm`. See [Supported platforms](/docs/introduction/concepts/supported-platforms).
- Hermes 0.21.6 or newer.

## Set up

Install the plugin from the catalog and select the backend:

```bash
hermes plugins install smolmachines
hermes config set terminal.backend smolmachines
```

Hermes asks to install one Python package, `smolmachines`, which carries the engine, and to enable the plugin. Answer yes to both.

Start Hermes as usual. Its first command boots a machine, and the first machine also pulls its image. To check, ask Hermes to run `uname -a` and `cat /etc/os-release`: they show a Linux kernel and Debian, not your computer.

To boot from another image, set it in the plugin's settings. Hermes runs its tools with `bash` and `python3`, so the image needs both:

```bash
hermes config set plugins.entries.smolmachines.settings.image ubuntu:24.04
```

`terminal.container_cpu` and `terminal.container_memory` set each machine's vCPUs and memory, 1 and 5120 MB by default. The [plugin README](https://github.com/smol-machines/hermes-smolmachines#readme) has every setting.

## What to know

- **Persistent machines keep running.** With `terminal.container_persistent: true`, the Hermes default, each Hermes home and session keeps one machine, named `hermes-<session>-<hash>`, which keeps running after Hermes exits. If it was stopped, the next command boots it again from its disk. List them with `smolvm machine ls`, and free one with `smolvm machine stop -n <name>` or `smolvm machine delete -n <name>`. With `false`, each session's machine is deleted when the session ends.
- **Image pulls use your Docker login.** Creating a machine pulls its image, from Docker Hub for the default `python:3.12-slim`. When this computer has a Docker registry login, the engine reads it and sends it only to the registry it pulls from.
- **The network is open.** The machine has outbound network access, so commands can install packages.
- **Local only.** The plugin always starts machines on the local engine, even when `SMOL_CLOUD_TOKEN` is set.
- **Output stops at 11 MiB.** The engine stops a command once it has printed 11 MiB, and Hermes gets the output up to that point marked `OUTPUT TRUNCATED`. Send large output to a file in the machine.
- **Not covered:** sub-agents started with `delegate_task` share their parent's machine, and Hermes's browser and computer-use tools do not move into the machine.
- Hermes skips its dangerous-command prompts in the machine, as it does for its Docker and cloud backends.

## Links

- [The plugin README](https://github.com/smol-machines/hermes-smolmachines#readme), with every setting
- [Terminal backend plugins in the Hermes docs](https://hermes-agent.nousresearch.com/docs/developer-guide/terminal-environment-plugin)
- [Hermes's catalog entry](https://github.com/NousResearch/hermes-agent/blob/main/plugin-catalog/smolmachines.yaml), added by [hermes-agent #145765](https://github.com/NousResearch/hermes-agent/pull/145765)

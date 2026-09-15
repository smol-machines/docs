---
title: "Dev env: a persistent machine you re-enter"
---

# Dev env: a persistent machine you re-enter

Keeps a persistent smolvm machine with its dependencies already installed and re-enters it cheaply across sessions. Use when a project needs an isolated development environment that survives stop and start; when deciding what belongs in a Smolfile's init versus what has to run on every boot; when a package installed in a machine has vanished after a restart; or when exec answers "the container smolvm-<hash> is not running". Do not use it for untrusted code, which needs a machine that leaves nothing behind (see the sandbox packet), or for running a Docker daemon inside the machine (see docker-in-machine).

## What it does

Preflight, declare the machine in a Smolfile, create and bring it up, work in it, prove it is worth keeping, clean up. The packet ships a working Smolfile as a starting point.

The create step matters more than it looks. It creates the machine with an explicit long-lived workload command, starts it, waits for the workload container to answer with a value, and then reports what actually happened rather than that nothing errored. Without an explicit command, `create` uses the image's own CMD as the persistent workload, and for an interpreter image that exits at once; a measured run on a nested-virt aarch64 host had 1 exec in 20 fail with `the container smolvm-<hash> is not running` with no command, and 0 in 20 with one.

The persistence check installs a package and records its **version**, seeds one file per filesystem, stops, starts, and then asserts each recorded value. A version comparison is the point: an import that does not crash can be satisfied by a system copy and says nothing about your install. What survives a stop and start is the overlay and the ext4 disk, so `$HOME` files, pip `--user` packages, writes at `/` and `/storage` all persist, while `/tmp` is a `tmpfs` and does not.

The packet's central fact is that `init` runs once, on the first start, and not again. It runs as root even when the Smolfile sets a `user`, while `exec` and `shell` run as that user, and there is no `machine start --init`. Anything that must be true on every boot, a bind mount above all, has to run in the command that needs it. The docs cover the semantics under [When init runs](/docs/introduction/concepts/smolfile#when-init-runs).

## What it checks first

- Whether a stopped machine starts again on this platform. It reports `restart_after_stop=verified` on macOS and Linux; on Windows a stopped machine does not start again, and the preflight says so rather than letting you find out later

## What it is not for

Untrusted code, which needs a machine that leaves nothing behind: that is [sandbox](/docs/local/skills/sandbox). Running a Docker daemon inside the machine, which is [docker-in-machine](/docs/local/skills/docker-in-machine).

## Platforms

| Platform | State |
|---|---|
| Linux aarch64 | The scripts were run here, and this is the verified platform for the use case |
| macOS arm64 | The scripts were run here too, and every check passed |
| Linux x86_64 | Verified in the material behind the packet, not re-run |
| Windows x86_64 | Recorded from one earlier run, not re-run. Create and first start match Unix, but a stopped machine does not start again, so the core promise of this use case does not hold there |

`init` after a checkpoint restore is not verified on any platform.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill dev-env
```

The procedure is [`skills/dev-env/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/dev-env/SKILL.md). For the Smolfile fields it uses, see [Smolfile](/docs/introduction/concepts/smolfile); for the lifecycle commands, [Machine Lifecycle and CLI Reference](/docs/local/machine-lifecycle-cli-reference).

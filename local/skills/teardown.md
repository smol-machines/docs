---
title: "Teardown: stop everything and remove smolvm's state"
---

# Teardown: stop everything and remove smolvm's state

Stops every smolvm machine a session started, removes smolvm's state, and proves the host is clean. Use after any smolvm session; when a machine seems to have survived a Ctrl-C or a crash; when disk space has disappeared; when uninstalling smolvm; when tearing down the Kubernetes runtime from a node; or when a borrowed or shared host has to be handed back with nothing left behind. Also use it as the cleanup step for other smolvm work, because the obvious assertions here give false results. Do not use it to delete machines another session created: it removes only what a script recorded under its own name prefix.

## What it does

It exists as its own packet because almost every cleanup fact in smolvm is counterintuitive: the obvious assertion gives a false failure, the obvious reaper matches the wrong process or nothing at all, and the command a user reaches for when a run misbehaves does not stop the machine. Every other packet's cleanup script is this one with a single line changed.

A read-only preflight reports what is on the host. The cleanup step deletes only machines recorded in its own state file, so a machine you or another session created by hand is never touched, and names must carry the `smolskill-` prefix or the delete is skipped. Leftover VM processes are reported by default and killed only with `--reap`, because killing a VM is not recoverable and the VM cannot be identified from `machine list`. A verification step then prints `ok` or `FAIL` per check and exits non-zero if any failed, and it can assert that nothing under a named real installation was written today. The last step reclaims space or removes smolvm entirely.

Four traps drive the design. `Ctrl-C` does not stop the machine and leaves no CLI route to what it left behind. Both obvious reapers fail in opposite directions: `pgrep -f` matches shells whose text contains the pattern and reports orphans that do not exist, while `readlink /proc/<pid>/exe` returns `Permission denied` for a VM process and reports none that do. Asserting "no machines" immediately after `machine run` fails on a healthy host, because the entry retires after the command returns. And `machine delete` prompts and defaults to No, so a script without `--force` prints `Cancelled` and carries on believing it cleaned up.

## What it checks first

- Each state directory, with its size
- Whether an `--oci-cache` image store exists, which is cache rather than residue and is excluded from the leak check
- Whether the launcher symlink and the `PATH` block are present
- Whether state can be relocated on this platform

The uninstaller leaves `~/.config/smolvm` and your `PATH` line on purpose, because those hold registry credentials and a change you made to your own shell profile. Nothing in the packet escalates privilege; the one place teardown needs `sudo` is the Kubernetes runtime, whose commands are given for you to read and run rather than wrapped in a script.

## What it is not for

Deleting machines another session created. It removes only what a script recorded under its own name prefix, which is deliberate: a cleanup that kills every smolvm process is fine on a laptop and destructive on a build agent. For what an install lays down, which is what you are removing, see [install](/docs/local/skills/install).

## Platforms

| Platform | State |
|---|---|
| macOS arm64 | Verified, scripts run here |
| Linux aarch64 | Verified, scripts run here |
| Linux x86_64 | The procedure was verified in the material behind the packet; the scripts were not re-run |
| Windows x86_64 | Recorded from one earlier run, not re-run. The scripts are POSIX shell and do not run there |
| Kubernetes nodes | Verified in the material behind the packet, not re-run |

Windows is the platform where this matters most, because state cannot be relocated there and one session left 30 GB behind.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill teardown
```

The procedure is [`skills/teardown/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/teardown/SKILL.md). For the lifecycle commands it wraps, see [Machine Lifecycle and CLI Reference](/docs/local/machine-lifecycle-cli-reference).

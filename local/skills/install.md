---
title: "Install: set up smolvm and prove the host boots"
---

# Install: set up smolvm and prove the host boots

Installs smolvm from a published release and proves the host can actually boot a microVM before any other work starts. Use when setting smolvm up on a new machine, a CI runner or an agent sandbox; when a first boot fails with krun_start_enter -22, KVM_DENIED or "agent did not become ready"; when checking whether a host meets smolvm's requirements at all; or when an install has to be isolated from an existing one and then removed. Do not use it to remove an existing install (see the teardown packet) or for anything after the first boot has succeeded.

## What it does

Four steps. A read-only preflight reports the host as `key=value` lines and ends with `result=ready` or `result=blocked`; it starts no VM and writes no smolvm state. The install itself is the published `install.sh` at a pinned version, which is a user-level install under `$HOME` and needs no root. The third step is the one that decides the outcome: it runs one ephemeral Alpine VM and asserts two values, a marker the guest printed and that the guest kernel is not the host's. A version number alone proves nothing, because on every platform here there is at least one way for the install to succeed and every VM start to fail. The last step cleans up, and waits before asserting an empty machine list, because a successful `machine run` returns before its entry retires.

To install without touching an existing install, the packet points `HOME` at a scratch directory. Every path smolvm uses moves with it on macOS and Linux. That does not work on Windows, where state cannot be relocated.

## What it checks first

- Whether the binary is on `PATH`, what version it reports, and how that compares with the release the packet was verified on
- The platform: `darwin-aarch64`, `linux-aarch64` or `linux-x86_64`
- Acceleration and access to it: `kern.hv_support` on macOS, or whether `/dev/kvm` is readable and writable on Linux
- The macOS socket path length, which the packet calls the single most common cause of a host that looks broken
- Whether the hardware is one the packet was run on: an Intel Mac reports `hardware_verified=no`
- Features the platform does not have, and a final `result=ready` or `result=blocked`

A `sudo usermod -aG kvm` is the one privileged step and the packet leaves it to you. Group membership on `/dev/kvm` is the host's boundary between users who can start VMs and users who cannot, so the preflight reports `accel_access=denied` and stops rather than widening it.

## What it is not for

Removing an existing install, which is [teardown](/docs/local/skills/teardown). Anything after the first boot has succeeded: for running work in a machine, start from [Machine Lifecycle and CLI Reference](/docs/local/machine-lifecycle-cli-reference).

## Platforms

| Platform | State |
|---|---|
| macOS arm64 | Verified. The path-length rule applies to every install |
| Linux aarch64 | Verified. The `kvm` group check applies to every fresh host |
| Linux x86_64 | Install and boot verified in the material behind the packet; the scripts were not re-run there |
| Intel Mac | Stated unverified. The installer accepts it and nothing behind the packet was run on one |
| Windows x86_64 | Recorded from one earlier run, not re-run. No PowerShell script ships, for that reason |

The Windows page carries the three facts that break a Unix-shaped script: the zip unpacks into a nested versioned folder, state lives in `%LOCALAPPDATA%\smolvm` and cannot be moved, and a script must never capture `machine start` output because it never returns.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill install
```

The procedure is [`skills/install/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/install/SKILL.md). For the install commands on their own, see [Local CLI Quick Start](/docs/local).

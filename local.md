---
title: Local CLI Quick Start
---

# Local CLI Quick Start

Use the `smolvm` CLI to run Linux workloads in local microVMs. Each workload gets its own guest kernel. No Docker daemon is required.

## Install

### macOS and Linux

```bash
curl -sSL https://smolmachines.com/install.sh | bash
smolvm --help
```

On macOS, the supported release path is Apple Silicon with macOS 11 or later. On Linux, the host architecture can be x86_64 or aarch64 and must expose KVM at `/dev/kvm`.

### Windows

1. Enable [Windows Hypervisor Platform (WHP)](https://learn.microsoft.com/en-us/virtualization/api/).
2. Download the `windows-x86_64` zip from the [v1.7.1 release](https://github.com/smol-machines/smolvm/releases/tag/v1.7.1).
3. Extract the full archive so `smolvm.exe`, `krun.dll`, and `libkrunfw.dll` remain together.
4. Run `smolvm.exe --help` from PowerShell.

Native Windows runs x86_64 Linux guests. WSL2 is an alternative on Windows 11 only when nested virtualization and KVM are available.

## Run an ephemeral machine

```bash
smolvm machine run --net --image alpine -- sh -c \
  "echo 'Hello from a microVM' && uname -a"
```

The machine exists only for this command and is cleaned up when the command exits.

- `machine run` selects the ephemeral lifecycle
- `--image alpine` pulls and boots the Alpine OCI image
- `--net` enables networking. Networking is off by default
- `--` separates smolvm flags from the command that runs in the guest

For an interactive shell:

```bash
smolvm machine run --net -it --image alpine -- /bin/sh
```

## Create a persistent machine

```bash
smolvm machine create --net --image alpine --name dev
smolvm machine start --name dev
smolvm machine exec --name dev -- apk add git
smolvm machine exec --name dev -- git --version
smolvm machine stop --name dev
```

This machine keeps filesystem changes across `exec` sessions and stop/start cycles.

- `machine create` records the machine and its configuration
- `machine start` boots it
- `machine exec` runs a command in the existing machine
- `machine stop` stops the VM without deleting its disk state

Delete the machine when you no longer need it:

```bash
smolvm machine delete --name dev
```

See [Machine Lifecycle and CLI Reference](/docs/local/machine-lifecycle-cli-reference) for the selected command reference and [Examples](/docs/local/examples) for more local workflows.

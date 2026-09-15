---
title: "Docker in machine: run a Docker daemon inside a machine"
---

# Docker in machine: run a Docker daemon inside a machine

Runs a Docker daemon inside a smolvm machine, for workloads that must call Docker themselves such as Testcontainers, Compose, image builds, or a coding agent that launches containers. Use when dockerd will not start inside a machine; when Docker worked on the first boot and broke after a stop and start; when deciding where Docker's data directory has to live; or when checking whether this is possible on a given platform at all. Do not use it to run OCI images, which smolvm boots natively without Docker, and do not attempt it on Windows, where the bundled guest kernel cannot support it.

## What it does

Preflight, create the machine and install Docker, start the daemon, prove it is on the right filesystem, clean up. The packet ships the Smolfile itself, because the release tarball does not contain `examples/`, so the guide's `git clone` step is not something a released install can follow.

The daemon step has to run on every start, not only the first. It re-applies both bind mounts, clears a stale pid file, starts `dockerd` with the `overlay2` driver and waits for `docker info` to answer. The verification asserts the storage driver, that Docker's root sits on `/dev/vda`, a nested container, and host networking inside the guest. The device check is the one that matters: `docker info` succeeds while `/var/lib/docker` sits on the rootfs overlay, and the failure that follows is confusing and much later.

Docker's data on `/storage` is a hard requirement, not a preference. The smolvm rootfs overlay uses the initramfs as its lower layer, ramfs has no file-handle support, and overlayfs then rejects it as an upper dir for Docker's nested overlay. Both mounts are needed, because `/var/lib/containerd` holds the snapshotter's overlay state and fails the same way.

The trap the packet exists for is that the mounts are gone on the second boot, since `init` runs once. The failure mode is a daemon that will not start, or one running on the wrong filesystem, not lost data: the images are on `/storage` and are still listed after the daemon comes back. The docs cover reapplying the mount under [Keep Docker data on /storage/docker](/docs/guides/docker-in-a-machine#keep-docker-data-on-storagedocker).

## What it checks first

- Whether this use case is possible on the platform at all. It reports `docker_in_machine=verified` on macOS and Linux, and `unavailable` on Windows with the reason

Setting `docker_socket = true` is the one line here that gives something outside the VM real authority: a process on the host that can open that socket can start containers inside the machine, mount paths the machine can see, and read anything they hold. The packet leaves it off, and none of its own checks depend on it.

## What it is not for

Running OCI images, which smolvm boots natively without Docker. Windows, where the bundled guest kernel has neither bridge networking nor POSIX message queues, so `dockerd` will not start and, forced past that, containers still cannot be created. For the `init` semantics this is built on, see [dev-env](/docs/local/skills/dev-env).

## Platforms

| Platform | State |
|---|---|
| Linux aarch64 | The scripts were run here, and this is the verified platform for the use case |
| macOS arm64 | The scripts were run here too and every check passed, including the restart trap and its recovery |
| Linux x86_64 | Not run for this use case on any host |
| Windows x86_64 | Not possible, from an earlier run that was not repeated |

Driving the host-side socket from a host `docker` client was not verified: the socket is created and asserted to exist, but neither host behind the packet has a Docker client.

## Install the packet

```bash
npx skills add smol-machines/smolvm --skill docker-in-machine
```

The procedure is [`skills/docker-in-machine/SKILL.md`](https://github.com/smol-machines/smolvm/blob/main/skills/docker-in-machine/SKILL.md). For the daemon commands, the socket bridge and published ports, see [Docker in a Machine](/docs/guides/docker-in-a-machine).

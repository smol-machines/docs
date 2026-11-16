---
title: Docker in a Machine
---

# Docker in a Machine

Run Docker inside a smolvm when a workload expects its own Docker daemon, including Testcontainers, Docker Compose, image builds, and coding agents that launch containers.

smolvm can boot OCI images without Docker. You only need this setup when software inside the machine must call Docker. For Docker clients on the host with no Docker daemon at all, see [the Docker Engine API](#the-docker-engine-api) below.

## Create the machine

Give Docker its two data directories as disk volumes, a guest path with no host side:

```bash
smolvm machine create --name docker --net --image docker:dind \
  -v /var/lib/docker -v /var/lib/containerd
smolvm machine start --name docker
```

The `docker:dind` image starts `dockerd` itself. Wait for it, then run a container from inside the guest:

```bash
smolvm machine exec --name docker -- sh -c '
  for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  docker run --rm alpine echo "hello from Docker"
'
```

## Why the disk volumes

The machine root filesystem is already an overlay, and Docker's `overlay2` cannot place its upper layer on another overlay. Each `-v` with only a guest path is a directory on the machine's ext4 disk, bound into the workload on every start, so Docker's data survives a stop and start and there is no mount to reapply first. In a Smolfile the same volumes are `volumes = ["/var/lib/docker", "/var/lib/containerd"]`.

The [docker-in-machine](/docs/guides/skills/docker-in-machine) skill packet runs this same setup with a preflight, a check of which filesystem Docker's root landed on, and the older bind-mount configuration for releases without disk volumes.

When separate exec calls use separate mount namespaces, including on the managed cloud path, point `dockerd` directly at `/storage/docker` with `--data-root=/storage/docker`.

## Reach the guest daemon from the host

Set `docker_socket = true` in the Smolfile or pass `--docker-socket` when creating the machine. smolvm bridges the guest's `/var/run/docker.sock` over vsock and prints the host socket path when the machine starts.

Point a host Docker client at that path:

```bash
DOCKER_HOST=unix:///path/printed/by/smolvm/docker.sock docker ps
```

This exposes the Docker daemon running inside the guest. It does not mount the host's Docker socket into the machine.

The distinction matters:

- **Guest Docker socket exposure:** host clients control the daemon inside the microVM. Containers remain inside the guest kernel
- **Host Docker socket exposure:** guest code controls the host daemon. This grants broad authority over the host and removes the isolation expected from the machine

Do not mount `/var/run/docker.sock` from the host into an untrusted guest.

## Published container ports

Declare host-to-guest ports when creating the machine:

```bash
smolvm machine create --name docker --net --image docker:dind -p 8080:8080 \
  -v /var/lib/docker -v /var/lib/containerd
```

A container can listen on guest port 8080, and smolvm forwards host port 8080 to it.

Ports that Docker Compose or Testcontainers choose later reach the host only with `--auto-ports`. Create the machine with it, and every port a container publishes inside appears at the same number on the host's loopback while it listens:

```bash
smolvm machine create --name docker --net --image docker:dind --auto-ports \
  -v /var/lib/docker -v /var/lib/containerd
```

`docker run -p 8080:8080 ...` inside the machine then answers at `http://127.0.0.1:8080` on the host. Docker's userland proxy, on by default, is what auto ports see, so with `"userland-proxy": false` nothing appears. The daemon's own TLS port, 2376 on `docker:dind`, is published as well; add `--auto-ports-exclude 2376` to keep it off the host. See [Publish the ports a machine starts listening on](/docs/local/machine-lifecycle-cli-reference#publish-the-ports-a-machine-starts-listening-on).

smolvm itself does not read Compose files. To run a Compose project, start this machine and run `docker compose up` inside it, with the project mounted or copied in.

## Avoid an unauthenticated Docker TCP endpoint

The vsock-backed Unix socket is the preferred host endpoint. If a client requires TCP, bind the host side to loopback and add TLS or another authentication layer. An unauthenticated Docker API exposed on `0.0.0.0` gives remote callers control of the daemon.

## Stop and delete

```bash
smolvm machine stop --name docker
smolvm machine delete --name docker
```

## The Docker Engine API

smolvm can also answer the Docker Engine API itself. The docker CLI, Docker Compose, Testcontainers and VS Code Dev Containers on the host talk to it as they would to a Docker daemon, and every container is a machine booted from its image. It is opt-in: installing or upgrading smolvm leaves your Docker setup alone. Run the setup once, on macOS or on Linux with a systemd user session:

```bash
smolvm engine
docker run --rm alpine echo hello
```

`smolvm engine` registers a socket at `~/.smolvm/run/docker.sock` with launchd on macOS or a systemd user socket on Linux, creates and selects the `smol` Docker context, and writes `docker.host` to `~/.testcontainers.properties` unless that file already names another runtime. When it replaces a context it names it, and `docker context use <previous>` switches back. A tool that reads only `DOCKER_HOST` can use the same socket:

```bash
export DOCKER_HOST=unix://$HOME/.smolvm/run/docker.sock
```

For a client fixed to `/var/run/docker.sock`, `smolvm engine link-socket` links that path to the socket through `sudo`. `smolvm engine status` says whether the socket is registered and whether the adapter is running.

Nothing stays resident. A Docker connection starts the API adapter, which exits after ten seconds with no requests or open streams, and running containers carry on without it. Each container is a machine named `docker-` and the first 12 characters of its id, so `smolvm machine ls` lists it; stop it with `docker stop` or `docker compose down`. Published ports, user-defined networks, volumes, `docker save`, `load`, `push` and `commit` work, and images build through Buildx with its `docker-container` driver. The legacy builder (`DOCKER_BUILDKIT=0`) and network drivers other than `bridge` are not supported.

Windows has no `smolvm engine`. On Linux without a systemd user session the setup fails with `Failed to connect to bus`.

---
title: Docker in a Machine
---

# Docker in a Machine

Run Docker inside a smolvm when a workload expects its own Docker daemon, including Testcontainers, Docker Compose, image builds, and coding agents that launch containers.

smolvm can boot OCI images without Docker. You only need this setup when software inside the machine must call Docker.

## Create the machine

The upstream example installs Docker, allocates storage, and enables the guest Docker socket bridge:

```bash
git clone https://github.com/smol-machines/smolvm.git
cd smolvm

smolvm machine create --name docker \
  -s examples/docker-in-vm/docker.smolfile \
  --net-backend virtio-net
smolvm machine start --name docker
```

Start `dockerd`:

```bash
smolvm machine exec --name docker -- sh -c '
  mkdir -p /storage/docker /var/lib/docker
  mount --bind /storage/docker /var/lib/docker
  rm -f /var/run/docker.pid
  dockerd --storage-driver=overlay2 >/tmp/dockerd.log 2>&1 &
  for i in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
  docker info
'
```

Test it from inside the guest:

```bash
smolvm machine exec --name docker -- \
  docker run --rm alpine echo "hello from Docker"
```

## Keep Docker data on `/storage/docker`

The machine root filesystem is already an overlay. Docker's `overlay2` cannot place its upper layer on that overlay because the backing filesystem does not provide the file-handle support nested overlayfs needs.

`/storage` is the machine's ext4 disk. Docker data must live there:

```bash
dockerd --data-root=/storage/docker --storage-driver=overlay2
```

The local example instead bind-mounts `/storage/docker` onto `/var/lib/docker`. Bind mounts do not survive a stop and start, so reapply that mount before starting `dockerd`.

When separate exec calls use separate mount namespaces, including on the managed cloud path, point `dockerd` directly at `/storage/docker`.

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
smolvm machine create --name docker -p 8080:8080 \
  -s examples/docker-in-vm/docker.smolfile \
  --net-backend virtio-net
```

A container can listen on guest port 8080, and smolvm forwards host port 8080 to it. Dynamic ports chosen later by Docker Compose or Testcontainers are not automatically published through the outer VM boundary. Pin the ports the host must reach.

## Avoid an unauthenticated Docker TCP endpoint

The vsock-backed Unix socket is the preferred host endpoint. If a client requires TCP, bind the host side to loopback and add TLS or another authentication layer. An unauthenticated Docker API exposed on `0.0.0.0` gives remote callers control of the daemon.

## Stop and delete

```bash
smolvm machine stop --name docker
smolvm machine delete --name docker
```

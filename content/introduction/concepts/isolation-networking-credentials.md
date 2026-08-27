---
title: Isolation, Networking, and Credentials
---

# Isolation, Networking, and Credentials

Each machine has its own Linux kernel and a hardware-virtualized boundary. The boundary limits direct access to the host, while configured mounts, sockets, ports, network routes, and credentials deliberately grant capabilities across it.

## Host isolation

A guest can access only the host resources made available to it. Review every host directory mount and forwarded socket before running untrusted code. A mounted directory exposes its contents with provided permissions.

The VM boundary does not make a deliberately shared host resource safe. Treat access to a Docker socket, SSH agent, source directory, or other host service as a security decision.

## Networking

Local smolvm guest networking is off by default, and OCI images are pulled from inside the guest — so a machine created from a registry image needs `--net` for its first pull unless the image is already in the host cache. Beyond the pull, enable guest networking only when the workload must resolve DNS, call an external service, or accept published traffic. A cloud machine created without a `network` block gets open outbound access by default; set `network` explicitly when egress policy matters.

Egress can be restricted with hostname and CIDR allowlists. A platform policy also blocks selected sensitive address ranges. There is no first-class deny-list configuration in the current shipped interface.

Published ports and outbound access are separate choices. Grant only the routes and ports a workload needs.

## Secrets and SSH keys

Secret injection resolves a host environment variable or file and places the value inside the guest. The value is plaintext from the guest's perspective. Code running in the machine can read it.

SSH-agent forwarding follows a different model. Private keys remain in the host agent, and the guest receives access to an agent socket. The guest can request signatures for as long as that socket is available, so forwarding still grants the ability to use the corresponding key.

HTTP credential brokering that swaps guest placeholders for host-held secrets is under development and is not a shipped product surface.

## Practical boundary

For an untrusted workload:

- Keep networking disabled unless it is required
- Restrict egress to necessary hosts or networks
- Avoid mounting sensitive host paths
- Inject only credentials the workload may read
- Forward an SSH agent only when the workload may request signatures

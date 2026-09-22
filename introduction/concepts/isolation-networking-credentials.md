---
title: Isolation, Networking, and Credentials
---

# Isolation, Networking, and Credentials

Each machine has its own Linux kernel and a hardware-virtualized boundary. The boundary limits direct access to the host, while configured mounts, sockets, ports, network routes, and credentials deliberately grant capabilities across it.

## Host isolation

A guest can access only the host resources made available to it. Review every host directory mount and forwarded socket before running untrusted code. A mounted directory exposes its contents with provided permissions.

The VM boundary does not make a deliberately shared host resource safe. Treat access to a Docker socket, SSH agent, source directory, or other host service as a security decision.

## Confining the VMM on Linux

The guest kernel boundary protects the host from the workload. A second boundary protects the host from the process that runs the machine, in case a guest ever escapes into it. On Linux the VMM process can be confined two ways, both applied before it loads the hypervisor library and enters the guest run loop:

- `SMOLVM_SECCOMP` restricts it to a syscall allowlist. `enforce` kills the process on a disallowed syscall, `audit` logs without killing, and `off` disables it. Enforce fails closed: a filter that cannot be installed stops the boot rather than running unconfined. Available on Linux on x86_64 and arm64.
- `SMOLVM_LANDLOCK` restricts its view of the filesystem to that machine's own rootfs, disks, and devices, denying the rest of the host. `enforce` or `off`. Linux only.

Which default applies depends on how the machine is started:

| Started by | Default |
|---|---|
| The SDK (`smolmachines` for Node or Python) | Both enforce, on Linux |
| `smolvm serve` | Both enforce, changeable with `--seccomp` and `--landlock` |
| The boot helper invoked directly | Off unless set |

An explicitly set variable always wins, so `SMOLVM_SECCOMP=off` remains the escape hatch for a workload the allowlist does not cover. On macOS both are ignored, so setting them there changes nothing.

## Networking

Local smolvm guest networking is off by default, and OCI images are pulled from inside the guest, so a machine created from a registry image needs `--net` to pull it. An ephemeral run pulls each time unless `--oci-cache` keeps the image on the host. A persistent machine pulls once too, but on its first start rather than at create: `machine create` records the configuration and starts nothing. Beyond the pull, enable guest networking only when the workload must resolve DNS, call an external service, or accept published traffic. A cloud machine created without a `network` block gets open outbound access by default; set `network` explicitly when egress policy matters.

Egress can be restricted with hostname and CIDR allowlists. A platform policy also blocks selected sensitive address ranges. There is no first-class deny-list configuration in the current shipped interface.

Published ports and outbound access are separate choices. Grant only the routes and ports a workload needs.

A workload that builds its own network interface, such as a VPN client running
in kernel mode, needs the guest's tunnel device. An image workload gets
`/dev/net/tun` inside its container by default, because the microVM is the
isolation boundary and the workload runs VM-grade. Adding `--unprivileged` moves
the workload to a reduced device view that does not include it, so a tunnel
client and `--unprivileged` are mutually exclusive.

## Secrets and SSH keys

Secret injection resolves a host environment variable or file and places the value inside the guest. The value is plaintext from the guest's perspective. Code running in the machine can read it.

SSH-agent forwarding follows a different model. Private keys remain in the host agent, and the guest receives access to an agent socket. The guest can request signatures for as long as that socket is available, so forwarding still grants the ability to use the corresponding key.

## Credential substitution

A credential binding gives a workload the ability to *use* a secret at named hosts without ever holding it. The guest receives an opaque placeholder in the environment variable it expects; the host replaces the placeholder with the real value only on HTTPS requests to the binding's allowed hosts, and only inside a request header.

```bash
NOTION_API_KEY=secret_... smolvm machine create --name notes --image alpine:3.20 \
  --credential notion=NOTION_API_KEY@api.notion.com
smolvm machine start --name notes
smolvm machine exec --name notes -- sh -c \
  'echo "$NOTION_API_KEY"; curl -s -H "Authorization: Bearer $NOTION_API_KEY" https://api.notion.com/v1/users/me'
```

The first line of output is `SMOL_PLACEHOLDER_NOTION_...`, which is all the guest can read or exfiltrate. Notion receives the real key. The same placeholder sent to any other host travels as a literal string; a placeholder in a URL, query string or request body is refused with a `403`.

The value is read on the host for every request, from a `[secrets]` reference of the same variable name or, failing that, from the host environment variable of that name. Rotating it needs no restart. Each binding lists exact hosts, and when the machine also has `allow_hosts` every credential host must fall under it, so widening the network never widens a credential. Branched machines inherit placeholders and keep working; each branch is resolved under its own name, so one branch can be cut off without touching the others.

Clients that honor `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, `NODE_EXTRA_CA_CERTS` or `DENO_CERT` work unmodified; the guest is given a bundle of the image's own roots plus a per-machine CA at `/run/smolvm/ca-bundle.pem`. Substitution covers HTTPS on port 443 and needs the default `virtio-net` backend.

## Practical boundary

For an untrusted workload:

- Keep networking disabled unless it is required
- Restrict egress to necessary hosts or networks
- Avoid mounting sensitive host paths
- Inject only credentials the workload may read
- Forward an SSH agent only when the workload may request signatures

---
title: Registry
---

# Registry

The registry stores `.smolmachine` artifacts using OCI registry conventions. An artifact contains a packaged machine environment that can be pulled and used on a compatible host.

The public catalog is at [smolmachines.com/registry](/registry). Official artifacts use the `library` namespace at `registry.smolmachines.com`.

## Pull an official artifact

Check the catalog for available architectures before pulling. A `.smolmachine` artifact is architecture-specific.

```bash
smolvm pack pull \
  registry.smolmachines.com/library/go:latest \
  -o go.smolmachine
```

Create a local persistent machine from the artifact:

```bash
smolvm machine create --name go --from go.smolmachine
smolvm machine start --name go
smolvm machine exec --name go -- go version
```

Tags are mutable. Use a digest reference when a workflow needs an immutable artifact:

```text
registry.smolmachines.com/library/go@sha256:<64-hex-digest>
```

## Create and publish an artifact

Create a `.smolmachine` locally:

```bash
smolvm pack create \
  --image python:3.12-alpine \
  -o python-tools
```

The command produces a runnable stub and a `python-tools.smolmachine` sidecar. Push the sidecar to a registry:

```bash
smolvm pack push \
  registry.example.com/team/python-tools:v1 \
  -f ./python-tools.smolmachine
```

Pull it later:

```bash
smolvm pack pull \
  registry.example.com/team/python-tools:v1 \
  -o python-tools.smolmachine
```

## Configure a custom registry

Initialize or edit the smolvm registry configuration:

```bash
smolvm config registries init
smolvm config registries edit
```

Machine artifact credentials belong under `[machines]`. Reference the secret through an environment variable:

```toml
[machines.registries."registry.example.com"]
username = "your-username"
password_env = "REGISTRY_PASSWORD"
```

Then export the credential before pushing or pulling:

```bash
export REGISTRY_PASSWORD="your-token"
```

Use `[images]` for OCI image registry credentials. Those credentials are separate from `.smolmachine` artifact registry credentials.

### A `docker login` on the host is enough for image pulls

Before reaching for `[images]`, check whether you already have the credential. smolvm resolves OCI
image credentials from the host's Docker configuration on every pull, and that includes
credential helpers, so a registry you have already run `docker login` against needs nothing
configured here. It reads `DOCKER_CONFIG` if that is set, and `~/.docker/` otherwise.

The resolution happens on the host, and the credential is never handed to the guest. There is a
`--docker-config` flag that mounts `~/.docker/` into the machine, and it is not what makes a
private pull work; it exists for the other contents of that directory.

With no credential for the registry, from either source, the pull fails naming the registry:

```text
No matching credentials were found for "ghcr.io"
```

`[images]` is still the way to configure a registry you have not logged in to, or to keep smolvm's
credentials separate from Docker's.

## Cloud support status

The public catalog and local `smolvm pack pull` workflow are live.

An account can also push an artifact into its own namespace, `tenants/<tenant>/name:tag`, authenticated by its cloud API key, and run a cloud machine from it with the `smolmachine` source below; the [cloud-registry](/docs/guides/skills/cloud-registry) skill packet does both end to end. A push cannot be undone, because no shipped command deletes a pushed artifact. One-click launch from the public catalog does not exist.

Creating a cloud machine from a `.smolmachine` reference, where enabled, uses a source shaped like:

```json
{
  "source": {
    "type": "smolmachine",
    "reference": "namespace/app:v1"
  }
}
```

A bare name such as `debian` or `alpine:3.20` resolves to your own artifact of that name when you have one, otherwise to the official `library/` artifact, and to the Docker Hub image of that name only when the registry answers that neither exists. A hostless `namespace/name` resolves to your own artifact of that name when you have one, otherwise to that Docker Hub image; a reference with a registry host is used as written.

Packed artifacts are architecture-specific. Set optional `arch` to `amd64` or `arm64` when you need an explicit placement constraint. When it is omitted, the control plane attempts to resolve the architecture from the registry manifest and place the machine on a matching node; specify it if manifest resolution is unavailable.

To run a private image from a registry smol cloud does not host, such as `ghcr.io` or Docker Hub, store a pull credential for that host first:

```text
PUT    /v1/registry/credentials             {"registry": "ghcr.io", "username": "...", "password": "..."}
GET    /v1/registry/credentials
DELETE /v1/registry/credentials/{registry}
```

`docker.io` covers references with no host. The password is sent to the node for each start only and is never returned; the list shows the username. Without a credential the pull fails inside the guest with `401`.

This artifact workflow does not move a running local VM into cloud; `smol machine move` does, as [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking#branches-and-checkpoints) describes.

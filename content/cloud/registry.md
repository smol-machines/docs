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

## Cloud support status

The public catalog and local `smolvm pack pull` workflow are live.

Starting a smol cloud machine directly from a registry artifact is represented in current cloud request types, but one-click launch from the public catalog is still being developed. User-owned namespaces and the complete publish-to-cloud workflow are also still in development. Do not build a production workflow around those paths until they are documented as supported for your account.

Creating a cloud machine from a `.smolmachine` reference, where enabled, uses a source shaped like:

```json
{
  "source": {
    "type": "smolmachine",
    "reference": "namespace/app:v1"
  }
}
```

Packed artifacts are architecture-specific. Set optional `arch` to `amd64` or `arm64` when you need an explicit placement constraint. When it is omitted, the control plane attempts to resolve the architecture from the registry manifest and place the machine on a matching node; specify it if manifest resolution is unavailable.

This artifact workflow does not move a running local VM into cloud. Live local-to-cloud migration is a separate capability and is not generally available.

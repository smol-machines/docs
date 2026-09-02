---
title: Smolfile
---

# Smolfile

A `Smolfile` is a TOML file that declaratively describes a machine workload. It keeps the image, command, resources, networking, development settings, health checks, and selected capabilities in one reviewable file.

The file is conventionally named `Smolfile` (without an extension) and lives in the project root. Pass another path with `-s` or `--smolfile`:

```bash
smolvm machine run -s Smolfile
smolvm machine create --name my-machine --smolfile ./deploy/Smolfile
```

Smolfile rejects unknown fields. A misspelled or unsupported key is a parse error, rather than an ignored setting.

## Minimal example

```toml
image = "python:3.12-alpine"
cmd = ["python", "-m", "http.server", "8080"]
cpus = 2
memory = 2048
net = true

[dev]
volumes = ["./src:/app"]
ports = ["8080:8080"]
workdir = "/app"
```

## Workload fields

These fields describe the machine and its workload. All are optional.

| Field | Type | Description |
| --- | --- | --- |
| `image` | string | OCI image reference. Omit it for a bare Alpine VM. |
| `entrypoint` | string array | Executable and fixed arguments. Overrides the image's `ENTRYPOINT`. |
| `cmd` | string array | Default arguments. Overrides the image's `CMD`. |
| `env` | string array | Environment variables written as `KEY=VALUE`. |
| `workdir` | string | Working directory inside the VM. |
| `cpus` | integer | Number of vCPUs. Default: `4`. |
| `memory` | integer | Memory in MiB. Default: `8192`. |
| `storage` | integer | Storage disk size in GiB. |
| `overlay` | integer | Overlay disk size in GiB. |
| `net` | boolean | Enable outbound networking. Networking is off by default. |
| `gpu` | boolean | Enable Vulkan GPU acceleration through virtio-gpu. |
| `gpu_vram` | integer | GPU shared-memory size in MiB. Ignored unless `gpu = true`. |
| `cuda` | boolean | Enable CUDA-over-vsock on supported Linux hosts with an NVIDIA driver. |
| `auto_graph` | boolean | Ask compatible CUDA frameworks to capture safe graph regions. Implies `cuda`. |
| `rosetta` | boolean | Enable Rosetta 2 translation for x86_64 binaries on Apple Silicon macOS. |
| `docker_socket` | boolean | Expose the guest Docker socket to the host as a Unix socket. |

`entrypoint` and `cmd` follow Docker/OCI semantics. If they are omitted, the image's built-in values are used. A command supplied after `--` replaces both Smolfile fields.

## Development profile

`[dev]` contains local-development settings. It is used by machine run/create workflows and is not included in packed artifacts.

| Field | Type | Description |
| --- | --- | --- |
| `volumes` | string array | Host bind mounts, such as `"./src:/app"`. |
| `ports` | string array | Port mappings, such as `"8080:8080"`. |
| `env` | string array | Development-only `KEY=VALUE` variables. |
| `init` | string array | Commands run on every VM start. |
| `workdir` | string | Development-only working directory. |

```toml
[dev]
volumes = ["./src:/app"]
env = ["APP_MODE=development"]
init = ["pip install -r requirements.txt"]
ports = ["8080:8080"]
workdir = "/app"
```

The legacy top-level `volumes`, `ports`, and `init` fields are also accepted. Prefer the `[dev]` fields for new Smolfiles.

## Network policy

`[network]` narrows outbound access. Both fields imply networking when they contain entries.

| Field | Type | Description |
| --- | --- | --- |
| `allow_hosts` | string array | Hostnames whose resolved IP addresses may be reached. |
| `allow_cidrs` | string array | Allowed IP addresses or CIDR ranges, such as `"10.0.0.0/8"`. |

```toml
net = true

[network]
allow_hosts = ["pypi.org", "files.pythonhosted.org"]
allow_cidrs = ["10.0.0.0/8"]
```

Hostnames are resolved when the VM starts. Use an allowlist instead of unrestricted `net = true` when the workload only needs a few destinations.

## Artifact profile

`[artifact]` overrides values when `smol pack create` builds a `.smolmachine` artifact. `[pack]` is an alias.

| Field | Type | Description |
| --- | --- | --- |
| `cpus` | integer | vCPU count for the artifact. |
| `memory` | integer | Memory in MiB for the artifact. |
| `entrypoint` | string array | Artifact entrypoint override. |
| `cmd` | string array | Artifact command override. |
| `oci_platform` | string | Target OCI platform, such as `"linux/amd64"`. |

```toml
[artifact]
cpus = 4
memory = 4096
oci_platform = "linux/amd64"
```

Development mounts and development initialization belong in `[dev]`; they are not part of the packed artifact.

## Health checks

`[health]` configures checks for `machine monitor`. `exec` is invoked directly as a command and argument array. To use shell syntax, set it to `['sh', '-c', '...']`.

| Field | Type | Description |
| --- | --- | --- |
| `exec` | string array | Command to execute. |
| `interval` | string | Time between checks, such as `"10s"`. |
| `timeout` | string | Maximum duration of one check. |
| `retries` | integer | Consecutive failures before the machine is unhealthy. |
| `startup_grace` | string | Delay before the first check. |

```toml
[health]
exec = ["curl", "-f", "http://127.0.0.1:8080/health"]
interval = "10s"
timeout = "2s"
retries = 3
startup_grace = "20s"
```

## Restart policy

`[restart]` controls restart behavior for managed workloads.

| Field | Type | Description |
| --- | --- | --- |
| `policy` | string | `"never"`, `"always"`, `"on-failure"`, or `"unless-stopped"`. |
| `max_retries` | integer | Maximum restart attempts. |
| `max_backoff` | string | Maximum delay between restarts, such as `"60s"`. |

## Forking

`[fork]` configures a copy-on-write fork base and CUDA clone capacity.

| Field | Type | Description |
| --- | --- | --- |
| `enabled` | boolean | Start the machine as a fork base. |
| `pool_size` | integer | Planned number of runnable CUDA clones. Implies `enabled` and requires `cuda = true` or `auto_graph = true`. |
| `cuda_vram_limit_mib` | integer | Logical VRAM limit per golden machine or clone. Requires `pool_size`. |

## Authentication and secrets

`[auth]` can forward the host SSH agent without copying private keys into the VM:

```toml
[auth]
ssh_agent = true
```

`[secrets]` maps guest environment variable names to host-side references. Never put plaintext secret values in a Smolfile.

```toml
[secrets]
DATABASE_URL = { from_env = "PROD_DATABASE_URL" }
TLS_KEY = { from_file = "/absolute/path/to/tls.key" }
```

`from_env` reads a host environment variable and `from_file` reads an absolute host file path at workload launch. The resolved plaintext is injected into the guest, while the reference is stored in the machine record and packed artifact so it can be resolved again on a trusted local host. See [Isolation, networking, and credentials](/docs/introduction/concepts/isolation-networking-credentials).

## Service metadata

`[service]` describes the port a deployed service listens on inside the VM.

| Field | Type | Description |
| --- | --- | --- |
| `port` | integer | Guest listening port. |
| `listen` | integer | A separate field, not resolved into `port`. Setting only `listen` leaves `port` unset. |
| `protocol` | string | Free text. `"http"` and `"tcp"` are the intended values, but the value is not checked. |

Only the key names in this table are constrained. A misspelled key such as
`protocl` fails the parse, while a misspelled value such as `"htpp"` does not.

## Configuration precedence

When the same setting is supplied in multiple places, command-line flags take precedence over the Smolfile. The development profile extends the top-level environment, mounts, ports, and initialization commands.

For workload commands, the precedence is:

1. Command arguments after `--` (replaces the Smolfile `entrypoint` and `cmd`)
2. `entrypoint`/`cmd` in the Smolfile
3. Image metadata

For resources, CLI flags override Smolfile values, which override defaults. `[artifact]` values apply when creating a packed artifact, while `[dev]` values apply to local development workflows.

## Configuration versus machine state

A Smolfile describes how to create, start, and connect to a machine. It is not the machine's persistent disk or RAM. To capture prepared disk state for reuse, create a [`.smolmachine` pack](/docs/introduction/concepts/packs-and-smolmachine).

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
| `image` | string | OCI image reference, or a path to a local `docker save` archive or unpacked rootfs. Omit it for a bare Alpine VM. |
| `entrypoint` | string array | Executable and fixed arguments. Overrides the image's `ENTRYPOINT`. |
| `cmd` | string array | Default arguments. Overrides the image's `CMD`. |
| `env` | string array | Environment variables written as `KEY=VALUE`. |
| `workdir` | string | Working directory inside the VM. |
| `user` | string | User the workload runs as: a name from the image's passwd database, or a numeric `uid[:gid]`. Overrides the image's `USER`. |
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
| `net_backend` | string | Networking backend: `"tsi"` or `"virtio-net"`. |

`image` resolves the same way as the `--image` flag, so it takes a locally built
archive as well as a registry reference:

```toml
image = "./myapp.tar"
```

A bare name is always a registry reference. A path, or a name ending in an
archive suffix, is read as a `docker save` archive, and an existing directory is
read as an unpacked rootfs. `file://` is not a supported prefix and is rejected
with a message telling you to give the path directly.

At import the archive's architecture is checked against the guest: an archive
built for another CPU is refused with a message naming both, and on Apple
Silicon an `amd64` archive is accepted when Rosetta is enabled.

A local archive needs no networking to start, which is the offline path for a
machine built elsewhere.

`entrypoint` and `cmd` follow Docker/OCI semantics. If they are omitted, the image's built-in values are used. A command supplied after `--` replaces both Smolfile fields.

### Choosing the workload user

`user` sets the account the workload runs as, in the same form `docker run --user`
takes. The usual reason to set it is a mounted host directory: an image built for
`root` writes files the host user then cannot edit, and naming the mount's owner
here avoids that.

```toml
image = "python:3.12-alpine"
user = "1000:1000"
```

It overrides the image's own `USER`. The CLI equivalent is `--user` on
`machine run` and `machine create`, and a flag beats the Smolfile when both are
given.

::: warning Init commands always run as root
`init` provisions the machine, so it runs as root whatever `user` says and
whatever the image's `USER` is. That is deliberate: package installs and mounts
need the privilege. Only the workload runs as `user`.
:::

## Development profile

`[dev]` contains local-development settings. It is used by machine run/create workflows and is not included in packed artifacts.

| Field | Type | Description |
| --- | --- | --- |
| `volumes` | string array | Host bind mounts, such as `"./src:/app"`. |
| `ports` | string array | Port mappings, such as `"8080:8080"`. |
| `env` | string array | Development-only `KEY=VALUE` variables. |
| `init` | string array | Commands run once, on first start. |
| `workdir` | string | Development-only working directory. |
| `user` | string | Development-only user override, in the same form as the top-level `user`. |

```toml
[dev]
volumes = ["./src:/app"]
env = ["APP_MODE=development"]
init = ["pip install -r requirements.txt"]
ports = ["8080:8080"]
workdir = "/app"
```

The legacy top-level `volumes`, `ports`, and `init` fields are also accepted. Prefer the `[dev]` fields for new Smolfiles.

### When init runs

`init` runs once, on the machine's first start, not on every start. Later starts
skip it and say so:

```text
Init already completed, skipping 3 command(s)
```

That is why init is the place for provisioning that should happen once, such as
installing packages, and not for anything a restart needs to redo. A machine
restored from a checkpoint counts as already initialized, because the restored
memory already contains the provisioned guest.

For an ephemeral run, `image` plus `init` is baked once into a cached artifact
and later runs of the same pair start from it. Files init wrote under the
working directory are captured with it, so a cached run does not start with them
missing. Pass `--no-init-cache` when init depends on live volume contents and
cannot safely be reused, or `--rebuild-init-cache` to rebuild it once.

The same commands can be given on the command line with `--init`, which is
accepted on `machine run` as well as `machine create`. The flag wins when a
Smolfile also sets `init`.

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

### Choosing a networking backend

`net_backend` picks how the guest reaches the network. It takes the same two
values as the `--net-backend` flag, and the flag and the field are parsed by the
same code, so the spellings cannot drift apart.

| Value | What it is |
| --- | --- |
| `tsi` | libkrun's transparent socket layer. Outbound connections only. |
| `virtio-net` | A virtual interface served by the host-side network stack. |

`tsi` is the default and is enough for a workload that only makes outbound
connections. Choose `virtio-net` when the guest needs a real network interface
and a default route of its own, which is what anything doing its own routing
requires: a kernel-mode VPN client such as Tailscale is the usual case.

```toml
image = "alpine"
net = true
net_backend = "virtio-net"
```

Publishing a port needs `virtio-net` too: with `tsi` the engine refuses a
published port rather than switching backends, because TSI is outbound only.
So set it both when publishing and when the guest needs the interface without
publishing anything.

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

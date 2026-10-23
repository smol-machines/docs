---
title: smol CLI Reference
---

# smol CLI Reference

`smol` is one command line for machines on this computer and on smol cloud. It carries its own copy of the smolvm engine, so it needs no separate `smolvm` install, and it reaches smol cloud once you sign in. `smolvm` remains the runtime's own CLI, described in the [Machine Lifecycle CLI Reference](/docs/local/machine-lifecycle-cli-reference).

## Install

On macOS (Apple Silicon) and Linux:

```bash
curl -sSL https://raw.githubusercontent.com/smol-machines/smol/v1.31.0/scripts/install.sh | bash
smol --version
```

The script downloads the release bundle, checks its checksum, unpacks it under `~/.smol` and links `smol` into `~/.local/bin`. It installs the latest release; `SMOL_VERSION=v1.31.0` pins one, and `PREFIX` and `BIN_DIR` change those places. `smol --version` prints the CLI version and the engine version it carries, for example `smol 1.31.0 (engine smolvm 1.31.0)`.

Sign in to reach smol cloud:

```bash
smol auth login
```

One login covers the cloud API and the registry. Without it, commands work on local machines only, and `smol machine ls` says that cloud machines were left out.

## Local or cloud

`smol machine` commands find a machine wherever it lives, so `smol machine ls` lists both sides. To pick one, pass `--local` or `--cloud`, or prefix the name with `local/` or `cloud/`. A machine id that starts with `mach-` is always a cloud machine. `create`, `update`, `resize`, `images`, `prune`, `monitor` and `data-dir` act on local machines only; `smol cloud deploy` creates a cloud one.

Run `smol <command> --help` for every flag of a command.

## Commands

| Command | What it does |
|---|---|
| `smol run -I IMAGE -- CMD` | Run a command in a throwaway machine, print its output when it finishes, and exit with its code |
| `smol new` | Scaffold a project: app code, a Smolfile and a README, from the `flask` or `node` template |
| `smol machine ...` | A machine's whole lifecycle, below |
| `smol file init`, `up`, `down` | Create a Smolfile, and bring its machine up or down |
| `smol pack create`, `push`, `pull`, `inspect` | Build and publish `.smolmachine` artifacts |
| `smol registry ls`, `catalog`, `tags`, `login`, `logout` | Browse registries and store their credentials |
| `smol auth login`, `logout`, `status` | Sign in to smol cloud and its registry |
| `smol cloud ...` | Cloud-only operations, below |
| `smol config set`, `show` | Read and change the CLI's configuration |
| `smol rollout ...` | Manage fused rollout executors and policy versions on a CUDA node |

### `smol machine`

`create`, `start`, `stop`, `pause`, `resume`, `rm`, `ls`, `status`, `exec`, `shell`, `logs`, `cp`, `sync`, `branch`, `branch-batch`, `checkpoint`, `checkpoint-log`, `checkpoint-prune`, `checkpoint-warm`, `restore`, `move`, `images`, `prune`, `resize`, `update`, `monitor` and `data-dir`. A machine is named with `--name`:

```bash
smol machine create --name dev --image alpine
smol machine start --name dev
smol machine exec --name dev -- uname -a
smol machine rm --name dev --yes
```

`smol machine move --name NAME` moves a running local machine to smol cloud, processes and memory included; see [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking#branches-and-checkpoints).

### `smol file up`

`smol file up` mounts each Smolfile volume read-only unless it ends in `:rw` or `:staged`, and refuses a host directory outside the Smolfile's own folder unless `--allow-mount PATH` names it. It shows the mounts for approval the first time and whenever they change; `--yes` approves them without asking.

### `smol cloud`

| Command | What it does |
|---|---|
| `deploy [REFERENCE]` | Create and start a cloud machine |
| `ls`, `rm`, `scale` | List, delete and scale cloud machines |
| `exec`, `shell` | Run a command, or open a shell, on a cloud machine; `exec --detach` runs it in the background and `logs` reads its output back |
| `export` | Export a stopped machine as a `.smolmachine` in your registry namespace |
| `checkpoint` | Capture, list, download, restore or delete live checkpoints, or upload one taken on this computer |
| `share`, `unshare` | Mint a login-free link to a machine's published app, or revoke it |

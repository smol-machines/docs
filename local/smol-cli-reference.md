---
title: smol CLI Reference
---

# smol CLI Reference

`smol` is one command line for machines on this computer and on smol cloud. It carries its own copy of the smolvm engine, so it needs no separate `smolvm` install, and it reaches smol cloud once you sign in. `smolvm` remains the runtime's own CLI, described in the [Machine Lifecycle and CLI Reference](/docs/local/machine-lifecycle-cli-reference).

## Install

On macOS (Apple Silicon) and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/smol-machines/smol/v1.37.4/scripts/install.sh | bash
smol --version
```

The script downloads the release bundle, checks its checksum, unpacks it under `~/.smol` and links `smol` into `~/.local/bin`. It installs the latest release; `SMOL_VERSION=v1.37.4` pins one, and `PREFIX` and `BIN_DIR` change those places. `smol --version` prints the CLI version and the engine version it carries, for example `smol 1.37.4 (engine smolvm 1.37.4)`.

Sign in to reach smol cloud:

```bash
smol auth login
```

One login covers the cloud API and the registry. Without it, commands work on local machines only, and `smol machine ls` says that cloud machines were left out.

For CI, `smol auth login --token-stdin` saves a key read from stdin, or set `SMOL_CLOUD_TOKEN`: the CLI reads it only when no key is saved, so a key saved by `smol auth login` takes precedence. The CLI does not read `SMOL_CLOUD_URL`; it uses its configured endpoint.

## Local or cloud

`smol machine` commands find a machine wherever it lives, so `smol machine ls` lists both sides. To pick one, pass `--local` or `--cloud`, or prefix the name with `local/` or `cloud/`. A machine id that starts with `mach-` is always a cloud machine. `create`, `update`, `resize`, `images`, `prune`, `monitor` and `data-dir` act on local machines only; `smol cloud deploy` creates a cloud one.

`--disk-durability deferred` on `smol machine create`, `smol run` and `smol cloud deploy` lets guest writes reach the disk on the host's schedule, faster for fsync-heavy work such as database commits; `full`, the default, makes a guest `fsync` wait for the disk.

Run `smol <command> --help` for every flag of a command.

## Commands

| Command | What it does |
|---|---|
| `smol run -I IMAGE -- CMD` | Run a command in a throwaway machine, print its output when it finishes, and exit with its code |
| `smol new` | Scaffold a project: app code, a Smolfile and a README, from the `flask` or `node` template |
| `smol machine ...` | A machine's whole lifecycle, below |
| `smol kubernetes ...` | A local development Kubernetes cluster in one machine, below |
| `smol file init`, `up`, `down` | Create a Smolfile, and bring its machine up or down |
| `smol pack create`, `push`, `pull`, `inspect` | Build and publish `.smolmachine` artifacts |
| `smol registry ls`, `catalog`, `tags`, `login`, `logout` | Browse registries and store their credentials |
| `smol auth login`, `logout`, `status` | Sign in to smol cloud and its registry |
| `smol cloud ...` | Cloud-only operations, below |
| `smol config set`, `show` | Read and change the CLI's configuration |
| `smol rollout ...` | Manage fused rollout executors and policy versions on a CUDA node |

### `smol machine`

`create`, `start`, `stop`, `pause`, `resume`, `rm`, `ls`, `status`, `exec`, `shell`, `logs`, `cp`, `sync`, `branch`, `branch-batch`, `checkpoint`, `checkpoint-requirements`, `checkpoint-log`, `checkpoint-prune`, `checkpoint-warm`, `restore`, `move`, `images`, `prune`, `resize`, `update`, `monitor`, `data-dir`, `ssh` and `ssh-config`. A machine is named with `--name`:

```bash
smol machine create --name dev --image alpine
smol machine start --name dev
smol machine exec --name dev -- uname -a
smol machine rm --name dev --yes
```

`smol machine move --name NAME` moves a running local machine to smol cloud, processes and memory included. It does not move every machine yet; [Move a local machine to the cloud](/docs/cloud/lifecycle-storage-networking#move-a-local-machine-to-the-cloud) lists which.

`smol machine ssh --name NAME` opens SSH to a local machine, starting it first when it is stopped, and `smol machine ssh --name NAME -- COMMAND` runs one command; SSH joins the words of `COMMAND` into one line, as `ssh` does. `smol machine ssh-config --name NAME` prints the host name and the path of a generated SSH config as JSON, `{"host": ..., "config": ...}`, for an editor or `ssh -F`; [Connect over SSH](/docs/local/machine-lifecycle-cli-reference#connect-over-ssh) shows that config at work.

### `smol kubernetes`

`smol kubernetes create NAME` starts a k3s cluster in one local machine named `smol-k8s-NAME` and prints it as JSON once it is ready. `--cpus`, `--memory-mib` and `--storage-gib` size it, 2, 3072 and 8 by default:

```bash
smol kubernetes create dev
smol kubernetes kubectl dev get nodes
smol kubernetes kubeconfig dev --output dev-kubeconfig.yaml
smol kubernetes stop dev
smol kubernetes start dev
smol kubernetes delete dev --yes
```

`kubectl` runs the cluster's own kubectl inside the machine, so file paths refer to the guest. `kubeconfig` writes a kubeconfig for the cluster's API on `127.0.0.1` to a new file that only you can read, refuses a file that already exists, and leaves `~/.kube` alone. `stop` keeps the cluster's data for `start`, and `delete` removes the cluster and its persistent volumes and needs `--yes`. `list` and `status` print JSON, and `logs` reads the server's recent logs.

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

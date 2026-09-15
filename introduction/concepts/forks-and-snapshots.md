---
title: Branches and Checkpoints
---

# Branches and Checkpoints

A branch creates a new machine from a live, branchable source. The child starts from the source machine's memory, processes, and disk state, then diverges through copy-on-write.

## Branches

Prepare a branchable machine as a source environment, start the workload, and branch children from that point. Each child continues with the cloned process state. This is useful for parallel agent tasks, test branches, and warm model-serving workers.

Copy-on-write avoids duplicating all memory and disk data at branch time. The source and children remain separate machines after the branch.

Branch support is host and feature dependent. Native Windows does not currently support VM branching.

### The older fork names

`fork` is the earlier name for this operation and still works everywhere, so existing scripts and Smolfiles keep running:

| Older name | Current name |
|---|---|
| `smolvm machine fork` | `smolvm machine branch` |
| `smolvm machine fork-release` | `smolvm machine branch-release` |
| `--forkable` | `--branchable` |
| `--golden` | `--from` on `machine branch` |
| `[fork]` in a Smolfile | `[branch]` |
| `fork()` in the Node and Python SDKs | `branch()` |

The rest of the documentation uses the current names only.

## Branches, packs, and checkpoints

These mechanisms preserve different state:

| Mechanism | Disk | RAM and processes | Independent artifact |
|---|---|---|---|
| Branch | Yes, then copy-on-write | Yes | No |
| Pack from VM | Yes | No | Yes, `.smolmachine` |
| Checkpoint | Yes | Yes | Yes, `.smolcheckpoint` |

A pack from a VM requires the source VM to be stopped. It captures disk state and boots as a new machine later. It does not preserve running processes.

A branch is host-local, not an exportable artifact. Use a checkpoint when you
need a file to retain or transfer independently of the live machine lifecycle.

## Checkpoints

A checkpoint captures a running machine, including guest RAM and processes, into a single `.smolcheckpoint` file. The machine must have been started branchable, with `--branchable` on `machine start`. A machine started without it can be stopped and started again with the flag. Unlike a branch it is an independent artifact: the source machine keeps running, and the file can be kept, copied, and restored later.

Restoring one creates a machine that resumes from the captured instant rather than booting. That is the difference from a pack, which captures disk state only and starts the machine from the beginning.

A checkpoint is portable between hosts, within limits the runtime checks before it restores:

- The host operating system and architecture must match the ones that captured it. A checkpoint taken on macOS on Apple Silicon restores on macOS on Apple Silicon.
- On Arm hosts, the host must also provide the CPU features the captured guest was given. A restore onto a host missing any of them fails and names the ones that are absent, rather than resuming a guest whose instructions the host cannot execute.
- The checkpoint format and runtime interface are versioned. A file written by an incompatible runtime is refused with the version it needs.

Restoring keeps the captured machine's shape. The CPU, memory, disk, and device topology come from the checkpoint, so they cannot be changed on the way in.

## Migration boundary

Branching is a same-runtime clone operation. It is not live migration between hosts.

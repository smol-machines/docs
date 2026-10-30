---
title: Branches and Checkpoints
---

# Branches and Checkpoints

A branch creates a new machine from a live, branchable source. The child starts from the source machine's memory, processes, and disk state, then diverges through copy-on-write.

## Branches

Prepare a branchable machine as a source environment, start the workload, and branch children from that point. Each child continues with the cloned process state. This is useful for parallel agent tasks, test branches, and warm model-serving workers.

Copy-on-write avoids duplicating all memory and disk data at branch time. The source and children remain separate machines after the branch.

`smolvm machine branch --from SOURCE --count N --name-prefix PREFIX` makes `PREFIX-0` to
`PREFIX-(N-1)` from one checkpoint of the source, booting `--parallel` of them at a time (four by
default). A batch waits until the source's workload runs `smolvm-branch-ready`, its declared branch
point. A workload that never declares one, such as a CI runner or a server, needs
`--no-wait-ready`, which checkpoints the source where it is.

Branch support is host and feature dependent. Native Windows branches a machine only with
`--freeze-source`, which pauses the source for the clone instead of branching it live.

A frozen source can be stopped once none of its branches is running, and cannot be started again
while any branch of it still exists, because the branches' disks are layered on its own.

On Linux, a source still running under an older smolvm engine is not branched after an upgrade:
the branch is refused with `409` and a message to restart the source (stop, then start), which
puts it on the new engine.

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
| Checkpoint | Yes | Yes | Yes, `.checkpoint` |

A pack from a VM requires the source VM to be stopped. It captures disk state and boots as a new machine later. It does not preserve running processes.

A branch is host-local, not an exportable artifact. Use a checkpoint when you
need a file to retain or transfer independently of the live machine lifecycle.

## Checkpoints

A checkpoint captures a running machine, including guest RAM and processes, into a single `.checkpoint` file. Any running machine can be checkpointed; starting it `--branchable` only makes the pause shorter. Unlike a branch it is an independent artifact: the source machine keeps running, and the file can be kept, copied, and restored later.

Restoring one creates a machine that resumes from the captured instant rather than booting. That is the difference from a pack, which captures disk state only and starts the machine from the beginning.

A checkpoint is portable between hosts, within limits the runtime checks before it restores:

- The host operating system and architecture must match the ones that captured it, with one exception: a checkpoint taken on an Apple Silicon Mac also restores on arm64 Linux when it was captured by a current smolvm; the restore names any check that fails. A Linux checkpoint does not restore on a Mac, and none crosses architectures.
- On Arm hosts, the host must also provide the CPU features the captured guest was given. A restore onto a host missing any of them fails and names the ones that are absent, rather than resuming a guest whose instructions the host cannot execute.
- The checkpoint format and runtime interface are versioned. A file written by an incompatible runtime is refused with the version it needs.

Restoring keeps the captured machine's shape. The CPU, memory, disk, and device topology come from the checkpoint, so they cannot be changed on the way in.

Capture is the fussier side. A checkpoint has to be able to resume every device it captured, so a
machine holding host-bound state is refused rather than captured into an artifact that could not
be restored. The initial profile refuses a machine with any of:

- host mounts, unless the capture asks to keep them with `--host-mounts`
- staged mounts, with or without it
- published sockets
- remote volumes
- host secret references
- image layers found only under a host path the image names; a machine created from a pack, or from an image the host fetched for it, is captured with its source
- custom DNS
- named inter-VM networking
- Vulkan GPU state, CUDA state, or Rosetta
- SSH agent forwarding or Docker socket forwarding

A checkpoint taken with `machine checkpoint --host-mounts` restores only on a host where the same host paths exist, and attaches each one again at its guest path. `machine pause` keeps a machine's host mounts without being asked.

The error names the ones in the way and asks you to stop or detach them before capture. A machine
that needs a socket or a staged mount for its work is therefore a machine to pack, not to checkpoint.

`machine branch` is the other way round: it takes no mount or socket flag at all, and children
inherit whatever the source was created with. To give each child its own mount, build the base as
an artifact and create from it, as the packs page shows.

## Migration boundary

Branching is a same-runtime clone operation. It is not live migration between hosts.

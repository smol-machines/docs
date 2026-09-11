---
title: Forks and Snapshots
---

# Forks and Snapshots

A fork creates a new machine from a live, forkable source. The child starts from the source machine's memory, processes, and disk state, then diverges through copy-on-write.

## Forks

Prepare a forkable machine as a golden environment, start the workload, and fork children from that point. Each child continues with the cloned process state. This is useful for parallel agent tasks, test branches, and warm model-serving workers.

Copy-on-write avoids duplicating all memory and disk data at fork time. The source and children remain separate machines after the fork.

Fork support is host and feature dependent. Native Windows does not currently support VM fork.

### Generations, disk layers, and sibling count

SmolVM limits a live branch lineage and its QCOW2 disk backing chain to 32
levels. This is not a limit of 32 children.

A **lineage generation** is one parent-to-child step. If `source` branches into
`child`, the child is one generation deep. If that branchable child branches
again, its child is two generations deep. A tree can have many siblings at the
same depth; host CPU, memory, and storage capacity determine how many can run.

A **disk layer** is a copy-on-write boundary. Reads fall through unchanged
blocks to older backing layers, while writes land in the machine's newest
private overlay. Bounding the chain prevents disk reads and lifecycle work from
walking an indefinitely long history.

The two counts usually move together for nested branches, but repeated fresh
branches from one continuing source can also add disk layers to that source.
When many workers should start from exactly the same state, use one batch:

```bash
smolvm machine branch --from source --count 100 --name-prefix worker --parallel 16
```

That command captures one generation and creates 100 sibling children from it;
it does not create 100 nested generations. By contrast, running 100 separate
single-child branch commands captures the source's current state each time and
can advance its disk backing chain.

SmolVM refuses an operation before either chain would exceed 32 levels. Stop
and pack the desired machine into a new root before continuing from a long
history. Automatic live disk-chain compaction is not currently available.

## Forks, packs, and snapshots

These mechanisms preserve different state:

| Mechanism | Disk | RAM and processes | Independent artifact |
|---|---|---|---|
| Fork | Yes, then copy-on-write | Yes | No |
| Pack from VM | Yes | No | Yes, `.smolmachine` |
| Checkpoint | Yes | Yes | Yes, `.smolcheckpoint` |

A pack from a VM requires the source VM to be stopped. It captures disk state and boots as a new machine later. It does not preserve running processes.

A branch is host-local, not an exportable artifact. Use a checkpoint when you
need a file to retain or transfer independently of the live machine lifecycle.

## Checkpoints

A checkpoint captures a running machine, including guest RAM and processes, into a single `.smolcheckpoint` file. The machine must have been started branchable, with `--branchable` on `machine start`, which the engine also accepts as `--forkable`. A machine started without it can be stopped and started again with the flag. Unlike a fork it is an independent artifact: the source machine keeps running, and the file can be kept, copied, and restored later.

Restoring one creates a machine that resumes from the captured instant rather than booting. That is the difference from a pack, which captures disk state only and starts the machine from the beginning.

A checkpoint is portable between hosts, within limits the runtime checks before it restores:

- The host operating system and architecture must match the ones that captured it. A checkpoint taken on macOS on Apple Silicon restores on macOS on Apple Silicon.
- On Arm hosts, the host must also provide the CPU features the captured guest was given. A restore onto a host missing any of them fails and names the ones that are absent, rather than resuming a guest whose instructions the host cannot execute.
- The checkpoint format and runtime interface are versioned. A file written by an incompatible runtime is refused with the version it needs.

Restoring keeps the captured machine's shape. The CPU, memory, disk, and device topology come from the checkpoint, so they cannot be changed on the way in.

## Migration boundary

Fork is a same-runtime clone operation. It is not live migration between hosts.

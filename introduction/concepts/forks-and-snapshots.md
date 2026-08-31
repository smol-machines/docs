---
title: Forks and Snapshots
---

# Forks and Snapshots

A fork creates a new machine from a live, forkable source. The child starts from the source machine's memory, processes, and disk state, then diverges through copy-on-write.

## Forks

Prepare a forkable machine as a golden environment, start the workload, and fork children from that point. Each child continues with the cloned process state. This is useful for parallel agent tasks, test branches, and warm model-serving workers.

Copy-on-write avoids duplicating all memory and disk data at fork time. The source and children remain separate machines after the fork.

Fork support is host and feature dependent. Native Windows does not currently support VM fork.

## Forks, packs, and snapshots

These mechanisms preserve different state:

| Mechanism | Disk | RAM and processes | Independent artifact |
|---|---|---|---|
| Fork | Yes, then copy-on-write | Yes | No |
| Pack from VM | Yes | No | Yes, `.smolmachine` |
| Checkpoint | Yes | Yes | Yes, `.smolcheckpoint` |

A pack from a VM requires the source VM to be stopped. It captures disk state and boots as a new machine later. It does not preserve running processes.

A fork is tied to its running source. It is not an exportable artifact that can be retained on its own.

## Checkpoints

A checkpoint captures a running machine, including guest RAM and processes, into a single `.smolcheckpoint` file. Unlike a fork it is an independent artifact: the source machine keeps running, and the file can be kept, copied, and restored later.

Restoring one creates a machine that resumes from the captured instant rather than booting. That is the difference from a pack, which captures disk state only and starts the machine from the beginning.

A checkpoint is portable between hosts, within limits the runtime checks before it restores:

- The host operating system and architecture must match the ones that captured it. A checkpoint taken on macOS on Apple Silicon restores on macOS on Apple Silicon.
- On Arm hosts, the host must also provide the CPU features the captured guest was given. A restore onto a host missing any of them fails and names the ones that are absent, rather than resuming a guest whose instructions the host cannot execute.
- The checkpoint format and runtime interface are versioned. A file written by an incompatible runtime is refused with the version it needs.

Restoring keeps the captured machine's shape. The CPU, memory, disk, and device topology come from the checkpoint, so they cannot be changed on the way in.

## Migration boundary

Fork is a same-runtime clone operation. It is not live migration between hosts.

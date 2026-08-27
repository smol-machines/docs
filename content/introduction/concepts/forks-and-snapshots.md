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
| General portable snapshot | Intended to include restorable runtime state | Intended to restore later | Not currently available as a user-facing API |

A pack from a VM requires the source VM to be stopped. It captures disk state and boots as a new machine later. It does not preserve running processes.

A fork is tied to its running source. It is not an exportable snapshot that can be retained independently or restored across architectures.

## Migration boundary

Fork is a same-runtime clone operation. It is not live migration between hosts.

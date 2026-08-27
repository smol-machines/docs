---
title: Packs and .smolmachine
---

# Packs and .smolmachine

A pack is a portable, self-contained machine artifact. Its `.smolmachine` file contains a prepared Linux environment that can start without pulling the original OCI image or reinstalling its dependencies.

## What a pack captures

A pack created from an image captures the prepared disk environment. A pack created from an existing VM also captures disk state.

The source VM must be stopped before `pack create --from-vm` can package it. The pack does not capture RAM or running processes. Starting the artifact boots a new machine from its packaged disk state.

External volumes are not embedded into the artifact. Attach required volumes each time the pack runs.

## When to use a pack

Packs fit workloads that need:

- A preinstalled, reproducible environment
- Less setup before useful work begins
- A single artifact for distribution
- A prepared base for local or supported cloud workflows

## Time to ready

Boot time is only part of the wait before a workload can do useful work. Pulling an image, installing dependencies, and preparing a workspace can take longer than starting the VM.

A pack moves that preparation into the artifact. Use one when repeated setup dominates the time before an agent, developer, or job can begin work.

A pack is different from a [fork](/docs/introduction/concepts/forks-and-snapshots). A fork clones a live machine, including running process state, through copy-on-write. A pack is a disk-based artifact that can outlive the source process.

## Compatibility

The host must support smolvm and match the artifact's architecture. GPU-enabled packs also require the corresponding supported host GPU path.

The same machine model supports local and cloud workflows, but artifact support does not imply live migration.

## Registry

The registry distributes official and custom `.smolmachine` artifacts. Pull an artifact for local use or publish one through the supported registry workflow. See [Registry](/docs/cloud/registry) for names, authentication, publishing, and cloud availability.

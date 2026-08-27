---
title: Machines and Lifecycle
---

# Machines and Lifecycle

A smol machine is a Linux virtual machine with its own guest kernel. It can start from an OCI image or a compatible `.smolmachine` artifact.

## Ephemeral runs

An ephemeral run creates a machine for one command or session and destroys the machine when the run exits. This mode fits one-off jobs, tests, and workloads whose state belongs in external storage.

Local `smolvm machine run` pulls its OCI image for the run and cleans up the VM afterward. If repeated setup or installation dominates startup time, create a [pack](/docs/introduction/concepts/packs-and-smolmachine).

## Persistent machines

A persistent machine has an identity and a disk that survive stop and start operations. Installed packages and files written to its machine storage remain available after a restart.

The common lifecycle is:

- **Create** the machine and its configuration
- **Start** its guest
- **Execute** commands or attach a shell
- **Stop** it while retaining persistent state
- **Delete** it when its disk and identity are no longer needed

Stopping a machine ends running processes and clears RAM. Its persistent disk remains. Deleting the machine removes its managed state.

## Local and cloud lifecycles

smolvm manages machines on the current host. smol cloud manages machines on smol machines infrastructure. The SDK can control either target, but the targets remain distinct.

You can reproduce or package an environment for another compatible target.

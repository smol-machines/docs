---
title: Overview
---

# Overview

smol machines provides a local microVM runtime, a managed cloud service, and an optional application SDK.

All three use the same basic machine model: an isolated Linux guest with explicit resources, storage, networking, and lifecycle controls.

<p class="doc-cards-lead">Choose where machines run and how to control them:</p>

<div class="doc-cards">
	<a class="doc-card" href="/docs/local">
		<span class="doc-card-title">Local CLI</span>
		<span class="doc-card-desc">Run and manage Linux microVMs on your own device.</span>
	</a>
	<a class="doc-card" href="/docs/cloud">
		<span class="doc-card-title">Cloud API</span>
		<span class="doc-card-desc">Managed, persistent machines on smol machines infrastructure.</span>
	</a>
	<a class="doc-card" href="/docs/sdk">
		<span class="doc-card-title">SDK</span>
		<span class="doc-card-desc">Create and control machines from a TypeScript, Python, Go or Rust application.</span>
	</a>
</div>

For more guidance on choosing the most suitable smol machines product for your use case, refer to the [FAQ](/faq).

## smolvm

`smolvm` is the open-source engine and CLI. It boots OCI images as Linux microVMs on a local macOS, Linux, or Windows host. Each machine has its own guest kernel and runs through the host's native virtualization interface.

Use `smolvm` for local command-line workflows, self-managed infrastructure, portable `.smolmachine` artifacts, VM branching, and supported local GPU workloads. It does not require a Docker daemon.


## smol cloud

smol cloud is the hosted service for managed smolvm-based machines. Clients create and manage machines through the Cloud API, the SDK, or supported CLI workflows.

Cloud clients do not need a local hypervisor. A local machine and a cloud machine can use the same configuration or compatible packaged environment, but they are separate runtime instances.


## smol SDK and CLI

The public `smol` project provides SDKs for TypeScript, Python, Go and Rust, plus the `smol` orchestration CLI. Its `Machine` API can embed smolvm for local use or connect to smol cloud.

The SDK is a control surface, not a prerequisite. Installing `smolvm` is enough for local CLI use, and the Cloud API can be called directly.


## How the pieces relate

| Layer | Runs the machine | Main interface |
|---|---|---|
| smolvm | Your computer or infrastructure | `smolvm` CLI and local engine |
| smol cloud | smol machines infrastructure | Cloud API, SDK, or CLI |
| smol SDK / CLI | Local engine or smol cloud | TypeScript, Python, Go, Rust, or `smol` |

## Common tasks

| Task | Where |
|---|---|
| Run GitHub Actions jobs on smol machines | [smol ci](/docs/cloud/ci) |
| Change a running cloud machine's ports, network, size, labels, environment or credential values | [Change a machine after create](/docs/cloud/lifecycle-storage-networking#change-a-machine-after-create) |
| Change a running local machine's ports, allow list, mounts, size or credentials | [Change a running machine](/docs/local/machine-lifecycle-cli-reference#change-a-running-machine) |
| Restrict what a local machine can reach, your computer's loopback included | [Networking](/docs/introduction/concepts/isolation-networking-credentials#networking) |
| Give a local machine an API key it never holds | [Credential substitution](/docs/introduction/concepts/isolation-networking-credentials#credential-substitution) |
| Open ssh, scp or an editor's remote session on a local machine | [Connect over SSH](/docs/local/machine-lifecycle-cli-reference#connect-over-ssh) |
| Move a local machine to another host as a file | [Checkpoint and restore a running machine](/docs/local/machine-lifecycle-cli-reference#checkpoint-and-restore-a-running-machine) |
| Move a running local machine to smol cloud | [Move a local machine to the cloud](/docs/cloud/lifecycle-storage-networking#move-a-local-machine-to-the-cloud) |
| Checkpoint a cloud machine and restore it | [Branches and checkpoints](/docs/cloud/lifecycle-storage-networking#branches-and-checkpoints) |
| Give a cloud machine a secret it never holds | [Credentials the machine never holds](/docs/cloud/lifecycle-storage-networking#credentials-the-machine-never-holds) |
| Publish a cloud port and get its URL | [Ingress and published ports](/docs/cloud/lifecycle-storage-networking#ingress-and-published-ports) |
| Authenticate the CLI and SDKs in CI | [Cloud Quick Start](/docs/cloud) |
| Run a long command an agent can come back to | [Commands and sessions](/docs/cloud/api-reference#commands-and-sessions) |

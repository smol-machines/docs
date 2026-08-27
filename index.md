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
		<span class="doc-card-desc">Create and control machines from a TypeScript or Python application.</span>
	</a>
</div>

For more guidance on choosing the most suitable smol machines product for your use case, refer to the [FAQ](/faq).

## smolvm

`smolvm` is the open-source engine and CLI. It boots OCI images as Linux microVMs on a local macOS, Linux, or Windows host. Each machine has its own guest kernel and runs through the host's native virtualization interface.

Use `smolvm` for local command-line workflows, self-managed infrastructure, portable `.smolmachine` artifacts, VM forks, and supported local GPU workloads. It does not require a Docker daemon.


## smol cloud

smol cloud is the hosted service for managed smolvm-based machines. Clients create and manage machines through the Cloud API, the SDK, or supported CLI workflows.

Cloud clients do not need a local hypervisor. A local machine and a cloud machine can use the same configuration or compatible packaged environment, but they are separate runtime instances.


## smol SDK and CLI

The public `smol` project provides the `smolmachines` packages for TypeScript and Python, plus the `smol` orchestration CLI. Its `Machine` API can embed smolvm for local use or connect to smol cloud.

The SDK is a control surface, not a prerequisite. Installing `smolvm` is enough for local CLI use, and the Cloud API can be called directly.


## How the pieces relate

| Layer | Runs the machine | Main interface |
|---|---|---|
| smolvm | Your computer or infrastructure | `smolvm` CLI and local engine |
| smol cloud | smol machines infrastructure | Cloud API, SDK, or CLI |
| smol SDK / CLI | Local engine or smol cloud | TypeScript, Python, or `smol` |

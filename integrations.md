---
title: Integrations
---

# Integrations

Use smol machines from tools you already run. Each integration below starts ordinary smol machines, through the `smolmachines` SDK, the `smolvm` CLI or the Cloud API: each one its own Linux guest, with branching where the integration uses it.

Most of these live in another project's repository. The **Code** column says where, and that project's issue tracker is the place to report problems with the integration itself.

## Testing

| Integration | What it does | Code | Runs on |
|---|---|---|---|
| [e2e by TesterArmy](/docs/integrations/testerarmy) | Runs each web test attempt in its own branch of a warm, signed-in Chromium machine | [`@e2e-dev/smol`](https://github.com/tester-army/e2e/tree/main/packages/smol), in TesterArmy's repository, written by smol machines | Local engine |

## Agent evaluation and RL

| Integration | What it does | Code | Runs on |
|---|---|---|---|
| [Harbor](https://github.com/harbor-framework/harbor) | `-e smol` runs each trial in a machine branched from one warm machine per task environment | [`environments/smol.py`](https://github.com/harbor-framework/harbor/blob/main/src/harbor/environments/smol.py), built into Harbor, written by smol machines | Local engine or smol cloud |
| [AgentEnv Framework](https://github.com/scaleapi/agentenv-framework) by Scale AI | A sandbox provider that runs AgentEnv agents and environments in local machines | [`smol_vm`](https://github.com/scaleapi/agentenv-framework/tree/main/src/agent_env/providers/sandbox_providers/smol_vm), in Scale AI's repository, written by smol machines | Local engine |
| [NeMo Gym](https://github.com/NVIDIA-NeMo/Gym) | A sandbox provider: install `smolmachines[nemo-gym]` and select `smol` in NeMo Gym's sandbox configuration. An image mapped in `checkpoints` forks a prepared, running machine | [`smol.nemo_gym`](https://github.com/smol-machines/smol/blob/main/sdk/python/python/smol/nemo_gym.py), in the smol Python SDK | Local engine or smol cloud |
| [verifiers](https://github.com/PrimeIntellect-ai/verifiers) by Prime Intellect | `smol.verifiers.SmolRuntime`, a runtime where each rollout runs in its own machine, or in a fork of a running golden machine. Install `smolmachines[verifiers]` | [`smol.verifiers`](https://github.com/smol-machines/smol/blob/main/sdk/python/python/smol/verifiers.py), in the smol Python SDK | Local engine or smol cloud |

## Agents and orchestration

| Integration | What it does | Code | Runs on |
|---|---|---|---|
| [exo](https://github.com/exoharness/exo) | `--sandbox-provider smolvm` runs an exo agent's sandbox as a microVM | [`sandbox_provider/smolvm`](https://github.com/exoharness/exo/tree/main/crates/exoharness/src/sandbox_provider/smolvm), in exo's repository, written by smol machines | Local engine |
| [Ray Sandboxes](https://github.com/ray-project/ray) | A backend for `ray.experimental.sandbox`, with live branching of a running sandbox. Install `smolmachines[ray]` and call `ray.init(runtime_env=ray_sandbox.use_smol())` | [`smol.ray_sandbox`](https://github.com/smol-machines/smol/blob/main/sdk/python/python/smol/ray_sandbox.py), in the smol Python SDK | Local engine or smol cloud |
| [Sandbox orchestration harness](https://github.com/temporal-community/sandbox-orchestration-harness) by the Temporal community | A smol cloud compute provider, with checkpoints and restores | [`sdk/compute/smolcloud`](https://github.com/temporal-community/sandbox-orchestration-harness/tree/main/sdk/compute/smolcloud), in the harness repository, written by smol machines | smol cloud |

Ray's sandbox API is experimental in Ray itself, so its shape can change between Ray releases.

## Agent tools

| Integration | What it does | Code | Runs on |
|---|---|---|---|
| [MCP server](https://github.com/smol-machines/smol/tree/main/sdk/mcp) | `npx -y smolmachines-mcp` gives any MCP client tools to create a machine with a project copied in, run commands, branch, checkpoint, restore and export | [`smolmachines-mcp`](https://www.npmjs.com/package/smolmachines-mcp), in the smol repository | Local engine, or smol cloud with `SMOL_CLOUD_TOKEN` |

## Add an integration

To propose an integration or report one that is missing from this page, open an issue on [smol-machines/docs](https://github.com/smol-machines/docs/issues).

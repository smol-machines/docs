---
title: Codex CLI
---

# Codex CLI

Register the server in Codex's configuration and Codex can create machines,
branch them, and bring results back.

## Install

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.smol]
command = "npx"
args = ["-y", "smolmachines-mcp"]
```

Recent Codex versions also accept the same registration from the command line:

```bash
codex mcp add smol -- npx -y smolmachines-mcp
```

To run on smol cloud, add the token under the server's environment:

```toml
[mcp_servers.smol.env]
SMOL_CLOUD_TOKEN = "smk_..."
```

## Try it

In a project, ask Codex:

> Create a machine from node:22 with this directory as the workspace and run
> the build. Branch it and switch the build to the newer bundler config in the
> branch; if the build passes there, export dist/ back to ./dist-candidate,
> otherwise delete the branch.

## Notes

- Codex runs its own sandbox for host commands; the smol tools are separate
  machines with their own kernel, so work inside them does not need Codex's
  host approvals.
- Requirements and troubleshooting are on the
  [overview page](/docs/guides/agents).

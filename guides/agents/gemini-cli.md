---
title: Gemini CLI
---

# Gemini CLI

Register the server in Gemini CLI's settings and Gemini can run work in
branchable machines.

## Install

Add to `~/.gemini/settings.json` (or `.gemini/settings.json` in a project):

```json
{
  "mcpServers": {
    "smol": {
      "command": "npx",
      "args": ["-y", "smolmachines-mcp"]
    }
  }
}
```

Recent versions also accept:

```bash
gemini mcp add smol npx -y smolmachines-mcp
```

For smol cloud, add `"env": { "SMOL_CLOUD_TOKEN": "smk_..." }` to the server
entry.

## Try it

> Create a machine from python:3.12 with this directory as the workspace and
> run the notebook's export script. Checkpoint the machine, then try the
> refactor; if anything breaks, restore the checkpoint and show me the diff of
> what you changed.

## Notes

- `/mcp` in a Gemini CLI session lists connected servers and their tools.
- Requirements and troubleshooting are on the
  [overview page](/docs/guides/agents).

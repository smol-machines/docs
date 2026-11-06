---
title: Cursor
---

# Cursor

Add the server to Cursor's MCP configuration and the agent in Cursor can run
builds, tests and experiments in branchable machines instead of on your host.

## Install

Create `.cursor/mcp.json` in the project (or `~/.cursor/mcp.json` for every
project):

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

For smol cloud, add `"env": { "SMOL_CLOUD_TOKEN": "smk_..." }` to the server
entry. Enable the server under Cursor Settings, MCP, if it does not appear
automatically.

## Try it

In agent mode:

> Create a machine from node:22 with this repo as the workspace and run the
> tests. Branch it and attempt the migration described in TODO.md inside the
> branch. If tests pass, export src/ back to ./src-migrated; if not, delete
> the branch and tell me what failed.

## Notes

- Cursor shows each tool call for approval unless the server's tools are
  allowed in settings.
- Requirements and troubleshooting are on the
  [overview page](/docs/guides/agents).

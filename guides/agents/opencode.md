---
title: OpenCode
---

# OpenCode

Add the server to OpenCode's configuration, in the project or globally, and
OpenCode's agents gain branchable machines.

## Install

In `opencode.json` at the project root (or `~/.config/opencode/opencode.json`
for every project):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "smol": {
      "type": "local",
      "command": ["npx", "-y", "smolmachines-mcp"],
      "enabled": true
    }
  }
}
```

For smol cloud, add the token to the server's environment:

```json
{
  "mcp": {
    "smol": {
      "type": "local",
      "command": ["npx", "-y", "smolmachines-mcp"],
      "enabled": true,
      "environment": { "SMOL_CLOUD_TOKEN": "smk_..." }
    }
  }
}
```

## Try it

> Create a machine from ubuntu:24.04 with this repo as the workspace, install
> the toolchain, and run the test suite. Then branch three times and try a
> different fix for the failing test in each branch. Keep the branch whose
> tests pass and delete the others.

## Notes

- OpenCode lists the server's tools under the `smol_` prefix once the config
  loads; restart OpenCode after editing the file.
- Requirements and troubleshooting are on the
  [overview page](/docs/guides/agents).

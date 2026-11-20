---
title: Claude Code
---

# Claude Code

Give Claude Code a branchable machine with one command. Claude then creates its
own environment, runs commands in it, and branches before risky steps instead
of working on your host.

## Install

```bash
claude mcp add smol -- npx -y smolmachines-mcp
```

Add `--scope user` to make the server available in every project rather than
the current one. To run the tools on smol cloud instead of the local engine,
pass the token as an environment variable:

```bash
claude mcp add smol -e SMOL_CLOUD_TOKEN=smk_... -- npx -y smolmachines-mcp
```

Check it is connected:

```bash
claude mcp list
```

Inside a session, `/mcp` shows the server and its tools.

## Try it

Start Claude Code in a project and ask:

> Create a machine from python:3.12 with this directory as the workspace, run
> the tests, then branch it and try upgrading the dependencies in the branch.
> If the tests still pass in the branch, export the branch's requirements file
> back here; otherwise discard the branch.

Claude will call `smol_create`, `smol_exec`, `smol_branch`, and then either
`smol_export` or `smol_delete`. Your working directory is not touched until an
export brings results back.

## Notes

- Claude Code asks before each tool call unless you allow the server's tools.
  Allowing `mcp__smol__*` lets an agentic run proceed without prompts.
- Machines created with the default `persistent: true` survive the end of a
  session; `smol_list` finds them and `smol_delete` removes them.
- Requirements and troubleshooting are on the
  [overview page](/docs/guides/agents).

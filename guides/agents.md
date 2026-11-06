---
title: Give your agent a machine
---

# Give your agent a machine

`smolmachines-mcp` is an MCP server that lets a coding agent assemble its own
environment: a real Linux microVM with your project copied in, where it can run
commands, branch before a risky step and keep or discard the result, and save
checkpoints it can come back to. You install nothing inside the machine by
hand; the agent does it with the tools below.

The server runs the local engine bundled in the `smolmachines` npm package, so
there is no daemon and no account. With `SMOL_CLOUD_TOKEN` set, the same tools
run on smol cloud instead.

## Requirements

- Node.js 18 or newer on the host (`npx` starts the server).
- A host the local engine supports: macOS on Apple Silicon, or Linux with
  readable and writable `/dev/kvm`. Without local virtualization, set
  `SMOL_CLOUD_TOKEN` and the tools use the cloud target.
- Network access on first start, to fetch the package and pull the first image.

## Add the server to your agent

One line per agent; each page below has the exact file or command and an
example prompt to try:

- [Claude Code](/docs/guides/agents/claude-code)
- [Codex CLI](/docs/guides/agents/codex)
- [OpenCode](/docs/guides/agents/opencode)
- [Gemini CLI](/docs/guides/agents/gemini-cli)
- [Cursor](/docs/guides/agents/cursor)

Any other MCP client that can start a stdio server works the same way:

```json
{ "mcpServers": { "smol": { "command": "npx", "args": ["-y", "smolmachines-mcp"] } } }
```

## What the agent can do

| Tool | Effect |
|---|---|
| `smol_create` | Boot a machine from an OCI image (`python:3.12`, `node:22`, `ubuntu:24.04`, …) and copy a host directory in as `/workspace`. Network is on by default; `allowHosts` restricts egress to named hosts. |
| `smol_exec` | Run a shell command in the machine; returns exit code, stdout and stderr. |
| `smol_branch` | Fork a running machine into an independent child from the exact same state, in about a tenth of a second. The child is branchable too. |
| `smol_delete` | Delete a machine, or discard a branch. |
| `smol_checkpoint` | Save the machine's complete state while it keeps running. |
| `smol_restore` | Start a new machine from a checkpoint: a rewind. |
| `smol_read_file`, `smol_write_file` | Move text in and out of a machine. |
| `smol_export` | Copy a directory from a machine to a host directory, for results worth keeping. |
| `smol_list` | List machines and their states. |

## The flow an agent follows

1. `smol_create` with `workspace` set to the project directory. The copy is the
   machine's own; the host directory is never written by the machine.
2. `smol_exec` to install, build, test, run. `/workspace` is the default working
   directory.
3. Before a change it might regret, `smol_branch`, then continue in the child.
   If the change worked, keep working there or `smol_export` the results to the
   host. If not, `smol_delete` the child; the source is exactly as it was.
4. `smol_checkpoint` at a point worth returning to. `smol_restore` brings it
   back as a fresh, branchable machine.

A branch or a checkpoint costs only what changed since, at any depth, so an
agent can try several approaches from one prepared state and keep one.

## Credentials and network

A machine has no access to the host's files or environment except what the
agent passes through these tools. Give a machine only the network it needs with
`allowHosts` on `smol_create`, for example `["api.anthropic.com",
"registry.npmjs.org"]`. Pass secrets as `env` on `smol_exec` for the one command
that needs them rather than baking them into the machine.

## Using the cloud target

Set `SMOL_CLOUD_TOKEN` in the server's environment (each agent page shows
where) and every tool runs on smol cloud with the same names and arguments. The
host then needs no virtualization support, and machines keep running after the
agent session ends.

## Troubleshooting

- `smol_create` fails with a KVM or Hypervisor error: on Linux check
  `test -r /dev/kvm -a -w /dev/kvm`; on macOS the engine needs Apple Silicon.
  Otherwise use the cloud target.
- The first `smol_create` of an image is slower while the image is pulled; later
  machines from the same image start in about a second.
- A source with live branches cannot be deleted; delete the branches first.

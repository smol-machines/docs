---
title: Agent Sandboxes and CI
---

# Agent Sandboxes and CI

Give each agent task or CI job its own microVM. Choose the lifecycle based on what must survive after the command finishes.

For a complete example with no existing project, follow the
[agent quickstart](/docs/guides/agent-quickstart): it prepares a machine,
checks four branches for isolation, saves a checkpoint, restores it, and cleans up.

## Choose a lifecycle

| Mode | Behavior | Use it for |
|---|---|---|
| Ephemeral run | Creates a machine, runs one command, then deletes it | Untrusted scripts, CI jobs, one agent turn |
| Persistent machine | Keeps disk state across stop and start | Development agents and jobs that need later inspection |
| Pack | Prebuilds dependencies into a portable `.smolmachine` artifact | Repeated jobs on compatible hosts |
| Fork | Clones a running golden machine with copy-on-write RAM and disk | Many short workers from one warm state |

The [sandbox](/docs/local/skills/sandbox) and [dev-env](/docs/local/skills/dev-env) skill packets are the first two rows as procedures, with the preflight, verification and cleanup steps each one needs.

## Run an ephemeral job

Network access is off unless enabled — but the image pull runs inside the
guest, so a registry image needs `--net` even when the job itself needs no
egress. On a CI host that runs the same image repeatedly, add `--oci-cache` so
later runs start from the host copy instead of pulling again:

```bash
smolvm machine run --net --image alpine:3.20 -- \
  sh -c "uname -a && echo isolated"
```

For an existing Node project with a `test` script and dependencies already
available to the guest, mount the source tree read-only and give generated
output a separate writable directory (tests must not write into the source tree):

```bash
mkdir -p artifacts

smolvm machine run --net --image node:22-alpine \
  --volume "$PWD:/workspace:ro" \
  --volume "$PWD/artifacts:/artifacts" -- \
  sh -c "cd /workspace && npm test > /artifacts/test.log"
```

A mount deliberately exposes a host directory to guest code. Do not mount the repository writable unless the job must edit it.

## Restrict egress

Enable only the destinations the job needs. This standalone example checks
the npm registry; it does not assume a project or lockfile exists in the image.
Pre-pull the image with networking first, then reuse the host OCI cache so
the restricted job does not need additional registry/auth/CDN hosts:

```bash
smolvm machine run --net --oci-cache --image node:22-alpine -- node --version
smolvm machine run --net --oci-cache \
  --allow-host registry.npmjs.org \
  --image node:22-alpine -- \
  npm ping --registry=https://registry.npmjs.org
```

Hostname and CIDR allow lists reduce the network authority of compromised dependencies or prompt-injected agents. A first-class deny-list is not currently available; if a job needs broad internet access, apply host or fleet network controls as well.

## Use a persistent machine for debugging

```bash
smolvm machine create --name failed-job --net --image ubuntu:24.04
smolvm machine start --name failed-job
smolvm machine exec --name failed-job -- sh -c 'echo "test failed" > /root/test.log; exit 1'
```

If the job fails, inspect it before cleanup:

```bash
smolvm machine status --name failed-job
smolvm machine shell --name failed-job
smolvm machine stop --name failed-job
smolvm machine delete --name failed-job
```

Stopping preserves disk state but loses RAM. To retain RAM and process state,
start the machine with `--branchable` before running the job and use
`machine checkpoint` while it is still running; capture eligibility depends on
the host and attachments. See the [checkpoint reference](/docs/introduction/concepts/forks-and-snapshots).

## Prebuild repeated environments

For an existing project whose Smolfile installs dependencies and includes
`ci.sh`, create a pack:

```bash
smolvm pack create -s Smolfile -o ci-worker
./ci-worker run -- ./ci.sh
```

Packs avoid repeating image pulls and setup. They are cold artifacts and require a compatible host architecture.

For repeated jobs, prepare and start a persistent source machine as branchable:

```bash
smolvm machine create --name agent-golden --net --image alpine
smolvm machine start --name agent-golden --branchable
smolvm machine exec --name agent-golden -- apk add git
smolvm machine branch --from agent-golden --name agent-1
smolvm machine branch --from agent-golden --name agent-2
smolvm machine exec --name agent-1 -- git --version
smolvm machine exec --name agent-2 -- git --version
smolvm machine delete --name agent-1 --force
smolvm machine delete --name agent-2 --force
smolvm machine delete --name agent-golden --force
```

Each branch gets copy-on-write RAM and disk; the source continues after a brief
capture pause. Branches remain on the source's host and architecture. Delete
every worker when its task ends.

## Handle secrets

Secret injection places plaintext in the guest:

```bash
export API_TOKEN

smolvm machine run --net --secret-env AGENT_TOKEN=API_TOKEN \
  --image alpine:3.20 -- sh -c 'test -n "$AGENT_TOKEN" && echo "token available"'
```

Guest code can read `AGENT_TOKEN`. Use injection only when the whole guest workload is trusted with the value.

SSH-agent forwarding keeps private key material on the host, but the guest can request signatures while the socket is connected:

```bash
smolvm machine run --ssh-agent --net --image alpine:3.20 -- \
  sh -c "apk add -q openssh-client && ssh-add -l"
```

There is no shipped general HTTP credential broker or cloud-native secrets store. Avoid passing production credentials to untrusted agent code. Prefer short-lived, least-privilege credentials and scope them to one job.

## Cleanup on every path

For a previously created `ci-job` with `/root/ci.sh` installed, preserve the
workload's exit code while still deleting the persistent machine:

```bash
set +e
smolvm machine exec --name ci-job -- sh /root/ci.sh
status=$?
set -e

smolvm machine delete --name ci-job --force
exit "$status"
```

SDK callers should delete machines in `finally` blocks or use the Python context manager. Add a TTL for cloud jobs when the SDK or API supports it so process crashes do not leave machines running indefinitely.

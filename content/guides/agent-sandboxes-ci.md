---
title: Agent Sandboxes and CI
---

# Agent Sandboxes and CI

Give each agent task or CI job its own microVM. Choose the lifecycle based on what must survive after the command finishes.

## Choose a lifecycle

| Mode | Behavior | Use it for |
|---|---|---|
| Ephemeral run | Creates a machine, runs one command, then deletes it | Untrusted scripts, CI jobs, one agent turn |
| Persistent machine | Keeps disk state across stop and start | Development agents and jobs that need later inspection |
| Pack | Prebuilds dependencies into a portable `.smolmachine` artifact | Repeated jobs on compatible hosts |
| Fork | Clones a running golden machine with copy-on-write RAM and disk | Many short workers from one warm state |

## Run an ephemeral job

Network access is off unless enabled:

```bash
smolvm machine run --image alpine:3.20 -- \
  sh -c "uname -a && echo isolated"
```

Mount the source tree read-only and give generated output a separate writable directory:

```bash
mkdir -p artifacts

smolvm machine run --image node:22-alpine \
  --volume "$PWD:/workspace:ro" \
  --volume "$PWD/artifacts:/artifacts" -- \
  sh -c "cd /workspace && npm test > /artifacts/test.log"
```

A mount deliberately exposes a host directory to guest code. Do not mount the repository writable unless the job must edit it.

## Restrict egress

Enable only the destinations the job needs:

```bash
smolvm machine run --net \
  --allow-host registry.npmjs.org \
  --allow-host github.com \
  --image node:22-alpine -- \
  sh -c "npm ci && npm test"
```

Hostname and CIDR allow lists reduce the network authority of compromised dependencies or prompt-injected agents. A first-class deny-list is not currently available; if a job needs broad internet access, apply host or fleet network controls as well.

## Use a persistent machine for debugging

```bash
smolvm machine create --name failed-job --net --image ubuntu:24.04
smolvm machine start --name failed-job
smolvm machine exec --name failed-job -- ./ci.sh
```

If the job fails, inspect it before cleanup:

```bash
smolvm machine status --name failed-job
smolvm machine shell --name failed-job
smolvm machine stop --name failed-job
smolvm machine delete --name failed-job
```

Stopping preserves disk state but loses RAM. smolvm does not currently expose a general portable RAM snapshot for failed jobs.

## Prebuild repeated environments

Define dependencies in a Smolfile and create a pack:

```bash
smolvm pack create -s Smolfile -o ci-worker
./ci-worker run -- ./ci.sh
```

Packs avoid repeating image pulls and setup. They are cold artifacts and require a compatible host architecture.

For high fan-out jobs, prepare and start a persistent golden machine as forkable:

```bash
smolvm machine create --name agent-golden --net --image alpine
smolvm machine start --name agent-golden --forkable
smolvm machine exec --name agent-golden -- apk add git
smolvm machine fork --golden agent-golden --name agent-1
smolvm machine fork --golden agent-golden --name agent-2
```

Each fork gets copy-on-write RAM and disk while sharing the frozen base. Forks remain tied to the golden's host and architecture. Delete every worker when its task ends.

## Handle secrets

Secret injection places plaintext in the guest:

```bash
export API_TOKEN

smolvm machine run --secret-env AGENT_TOKEN=API_TOKEN \
  --image alpine:3.20 -- env
```

Guest code can read `AGENT_TOKEN`. Use injection only when the whole guest workload is trusted with the value.

SSH-agent forwarding keeps private key material on the host, but the guest can request signatures while the socket is connected:

```bash
smolvm machine run --ssh-agent --net --image alpine:3.20 -- \
  sh -c "apk add -q openssh-client && ssh-add -l"
```

There is no shipped general HTTP credential broker or cloud-native secrets store. Avoid passing production credentials to untrusted agent code. Prefer short-lived, least-privilege credentials and scope them to one job.

## Cleanup on every path

Shell scripts should preserve the workload's exit code while still deleting persistent machines:

```bash
set +e
smolvm machine exec --name ci-job -- ./ci.sh
status=$?
set -e

smolvm machine delete --name ci-job
exit "$status"
```

SDK callers should delete machines in `finally` blocks or use the Python context manager. Add a TTL for cloud jobs when the SDK or API supports it so process crashes do not leave machines running indefinitely.

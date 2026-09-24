---
title: Agent quickstart
---

# Agent quickstart

Install the local runtime, prepare one machine, run four independent branches,
and restore its disk and RAM from a checkpoint. No cloud account or existing
project is required.

## Install and check the host

This Bash recipe targets Linux x86_64 with accessible `/dev/kvm`, or macOS on
Apple Silicon. Native Windows does not support this branching workflow.
Allow several GiB of free disk and RAM for the example. The first image pull
needs internet access.

```bash
curl -fsSL https://smolmachines.com/install.sh | bash
smolvm --version
smolvm machine branch --help
smolvm machine checkpoint --help
```

If the installer updated your PATH, open a new terminal first. On Linux,
`test -r /dev/kvm && test -w /dev/kvm` must succeed. If it does not, ask your
host administrator to enable KVM access; do not silently switch to a paid
cloud target. Installed `--help` is authoritative for available flags.

## Prepare, branch, verify, and restore

Run this entire block in Bash. It creates its own input files and keeps the
checkpoint in a new directory under your current working directory. The exit
trap deletes only this run's machines, including after a failed assertion.

```bash
set -euo pipefail
prefix="agent-demo-$(date +%s)-$$"
source_name="$prefix-source"
restored_name="$prefix-restored"
artifact_dir="$(mktemp -d "$PWD/smol-agent-demo.XXXXXX")"
machines=()
cleanup() {
  # Children must be deleted before their source.
  for ((index=${#machines[@]}-1; index>=0; index--)); do
    smolvm machine delete --name "${machines[index]}" --force || true
  done
}
trap cleanup EXIT

machines+=("$source_name")
smolvm machine create --name "$source_name" --image alpine:3.20 \
  --net --cpus 2 --mem 1024 --storage 2 --overlay 1
smolvm machine start --name "$source_name" --branchable
smolvm machine exec --name "$source_name" -- sh -ec \
  'printf "prepared\n" > /root/result; printf "ram-marker\n" > /dev/shm/marker'

smolvm machine checkpoint --name "$source_name" \
  --output "$artifact_dir/prepared.smolcheckpoint"

for i in 1 2 3 4; do
  child="$prefix-child-$i"
  machines+=("$child")
  smolvm machine branch --from "$source_name" --name "$child"
  smolvm machine exec --name "$child" -- sh -ec \
    'test "$(cat /root/result)" = prepared
     test "$(cat /dev/shm/marker)" = ram-marker
     printf "%s\n" "$1" > /root/result
     printf "%s\n" "$1" > /dev/shm/marker' sh "branch-$i"
done

for i in 1 2 3 4; do
  smolvm machine exec --name "$prefix-child-$i" -- sh -ec \
    'test "$(cat /root/result)" = "$1"
     test "$(cat /dev/shm/marker)" = "$1"
     printf "%s: disk and RAM isolated\n" "$1"' sh "branch-$i"
done
smolvm machine exec --name "$source_name" -- sh -ec \
  'test "$(cat /root/result)" = prepared
   test "$(cat /dev/shm/marker)" = ram-marker
   printf "source-continued\n" > /root/result'

machines+=("$restored_name")
smolvm machine create --name "$restored_name" \
  --from "$artifact_dir/prepared.smolcheckpoint"
smolvm machine start --name "$restored_name"
smolvm machine exec --name "$restored_name" -- sh -ec \
  'test "$(cat /root/result)" = prepared
   test "$(cat /dev/shm/marker)" = ram-marker
   echo "checkpoint: disk and RAM restored"'
printf 'PASS; checkpoint retained at %s/prepared.smolcheckpoint\n' "$artifact_dir"
```

Each branch starts with the prepared files, then changes them independently.
The source remains usable. The restored machine sees the captured value,
not the source's later write. `/dev/shm/marker` lives in guest RAM, so it also
checks that this is a live checkpoint rather than just a disk image.

These are sequential single-child branches, not a parallel batch benchmark.
Replace the file checks with your tests or agent commands after preparing
dependencies in the source. Use `machine exec` for subsequent commands in
each child; delete the child when its task ends.

To run one task at a time as a procedure, with a preflight that checks the host
first and a cleanup that proves it afterwards, load a packet from
[Skill Packets](/docs/guides/skills).

## Know the boundary

Branching and checkpoint capture briefly pause the source to capture consistent
state; they are not zero-pause operations. A branch is host-local and does not
automatically create a checkpoint file. `machine checkpoint` explicitly writes
the independent artifact. Treat it as sensitive: it contains guest memory and
disk contents, including any credentials in them.

Restore requires a compatible runtime, the same host OS and architecture, and
compatible CPU features. Do not assume a macOS checkpoint restores on Linux,
or that GPU state, external connections, and host mounts are portable. See
[Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots).

## Use it from code or in the cloud

Use the [SDK quickstart](/docs/sdk) for Node or Python. Explicitly select local
or cloud execution; cloud requires an account and API key and incurs usage
charges. Follow the [cloud quickstart](/docs/cloud) for hosted machines rather
than assuming every local CLI flag is a cloud API field.

Agents can discover the documentation through [/llms.txt](/llms.txt) and
[/docs/llms.txt](/docs/llms.txt), and cloud schemas through
[/openapi.json](/openapi.json). Read plain Markdown from the
[public docs repository](https://github.com/smol-machines/docs); the website
serves HTML documentation pages, not `.md` twins.

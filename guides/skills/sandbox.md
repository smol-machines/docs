---
title: "Sandbox: run untrusted code in a throwaway machine"
---

# Sandbox: run untrusted code in a throwaway machine

Runs untrusted code in a throwaway smolvm microVM against a repo it must not modify, with no network unless explicitly granted, and collects artifacts from a writable output directory. Use when executing an agent's generated script, a pull request's test suite, or any code that should not be trusted with the host; when a workload needs egress granted one host at a time; or when a sandbox run has to be cancelled, because Ctrl-C leaves the VM running and invisible to the CLI. Do not use it for a development environment that is re-entered across sessions, for running a Docker daemon inside a machine, or for installing smolvm itself, which is the install packet.

Verified on **smolvm v1.18.2** on macOS arm64 and Linux aarch64, 2026-09-24, by the network-on
route and the cancel on both; the offline route last completed on Linux aarch64 on v1.14.6, and
"Re-verified on v1.18.2" says why. Done means the command's output landed in your writable directory,
the repo is unchanged, the workload could not reach the network, and nothing is left running.

**Two smolvm defects shape this packet and you will meet both.**

- **[#1193](https://github.com/smol-machines/smolvm/issues/1193): Ctrl-C does not stop a cached
  run.** The VM outlives the CLI, `machine list` reports `No machines found`, and it exits only
  when the untrusted workload does. **The cancel is `scripts/cleanup.sh --cancel`, never Ctrl-C.**
  On the network-on route a v1.18.2 run whose wrapper was killed stays in `machine list` as
  `running (eph)` on both hosts here, and `--cancel` still clears it.
- **[#1192](https://github.com/smol-machines/smolvm/issues/1192): on macOS a cached run with any
  mount never boots.** The offline shape below is therefore Linux-only today. macOS has its own
  page with a route that works: read `references/macos.md`.

## Workflow

**If you have no script to sandbox, make one.** A file that reads a path under `/workspace`, tries
to create a file there, and tries to fetch a URL proves all three properties in one run, and the
three lines it prints are the evidence. An agent with an empty directory and no fixture stopped and
asked the user instead of building one.

```
- [ ] 1. preflight.sh, and read result= and device_budget_ok=
- [ ] 2. bake.sh          (offline route only; network on, nothing untrusted mounted)
- [ ] 3. run.sh           (the untrusted command; records the VM pid)
- [ ] 4. verify.sh        (from inside the guest and from the host)
- [ ] 5. cleanup.sh       (or cleanup.sh --cancel to stop a run early)
```

**1. Preflight.** Read-only: starts no VM, bakes nothing.

```bash
scripts/preflight.sh --mounts 2 --ports 0
```

`device_budget_ok=no` means the boot will fail with `no more IRQs are available`. The guest has
eleven IRQs: **four `-v` mounts boot and five do not, and every published port costs one of those
slots**, so the budget is mounts plus ports. Combine directories under one mount rather than
discovering this at boot.

`offline_shape=unavailable` means this host cannot run the shape below. On macOS that is #1192; on
any host it can also mean the bake helper's memory does not fit, which step 2 diagnoses.

**2. Bake the image. This is the only step that talks to a registry.**

```bash
scripts/bake.sh python:3.12-alpine
```

Network on, nothing untrusted mounted, done before the untrusted code is anywhere near the machine.
Afterwards the runs need no network at all, which is a materially stronger sandbox than granting
egress and hoping.

**3. Run the untrusted command.**

```bash
scripts/run.sh --repo ./repo --out ./out -- sh -c 'python3 /workspace/calc.py > /out/result.txt'
```

The repo is mounted read-only at `/workspace`, the output directory writable at `/out`, and the run
has no network. It prints `used_host_cache=yes`, which is the assertion that the bake worked and
that this run reached no registry: without it the run pulled, which means it had network, which
means it was not the sandbox you asked for.

It also prints `vm_pid=` and records it. **That pid is the only route back to the machine** if the
run has to be stopped.

To grant egress, name hosts one at a time:

```bash
scripts/run.sh --allow-host example.com --repo ./repo --out ./out -- <command>
```

**4. Verify. Both halves, because either alone passes on a broken sandbox.**

```bash
scripts/verify.sh --expect-file result.txt --expect 42
```

```
inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (blocked)
artifact=ok (42)
repo_unchanged=ok
result=sandbox_held
```

The inside half proves the workload could not write the repo and could not reach the network; the
host half proves the artifact came out and the repo is unchanged. A run that merely exited zero
tells you neither.

**5. Clean up, or cancel.**

```bash
scripts/cleanup.sh --purge            # after a run finished
scripts/cleanup.sh --cancel --purge   # to stop a run that is still going
```

`--cancel` kills exactly the VMs `run.sh` recorded and then verifies that nothing is left. It waits
before asserting an empty machine list, because the ephemeral entry retires after the run returns
and an immediate assertion fails on a healthy host.

## Cancelling, and why Ctrl-C is not it

On the offline route, interrupting the CLI leaves the VM running with no CLI route to it, and it
exits only when the untrusted workload finishes. For code that hangs or loops that is unbounded
exposure, with roughly 230 MB held per survivor.

**The routes differ, and `references/traps.md` has the measurements.** On the plain path a `SIGINT`
to the CLI does take the VM with it, verified here on Linux. Do not rely on that: interrupting the
*wrapper* rather than the CLI leaves both running on either route, which was observed on both hosts
used for this packet. Use `--cancel`.

## If the workload brings up a VPN

A guest that runs Tailscale or another carrier NAT VPN loses its gateway and its resolver on the
default virtio-net link, and every lookup then fails as `bad address`, which reads like the
allow list rather than a routing clash. `--allow-host` and `--allow-cidr` select that link, so
this applies to any run here that grants egress. Move the link with `--guest-subnet`, passed to
`smolvm machine run` directly:

```bash
smolvm machine run --allow-host example.com --guest-subnet 10.200.0.0/30 --image alpine -- <command>
```

**`--guest-subnet` implies `--net`**, so never add it to an offline run: it opens the network the
offline route exists to keep shut. Pick a range outside `100.64.0.0/10`; the CLI accepts one inside
it without a warning. `references/traps.md` has the measurement.

## Reference pages

Read these when the situation calls for them; they are not needed for a normal run.

- **`references/traps.md`** for every trap with its measurement: the two routes and what Ctrl-C does
  to each, the bake helper's fixed memory, a guest VPN taking the default link, why `pgrep -f` and
  `readlink` both fail as reapers, and what counts as cache rather than residue.
- **`references/macos.md`** if you are on macOS. The offline shape does not work there; that page
  gives a route that does and says what it costs.
- **`references/windows.md`** if you are on Windows. The bake never completes there, so the offline
  shape is unavailable for a different reason, and the reaper has to be broader.

## Security defaults, and why they are the defaults

- **No network is the default because it is the only guarantee that does not depend on the
  workload's cooperation.** An egress policy is a filter on what untrusted code asks for; no network
  is a property of the machine. The bake exists so that the offline run is possible at all.
- **`--allow-host` grants one host, and the run still has a network stack.** Prefer it to `--net`,
  but treat it as a narrower opening rather than as no opening. A denial under it looks like a DNS
  failure, so a workload can fail confusingly rather than obviously.
- **The repo is `:ro` because a read-only mount is enforced by the guest kernel**, not by the
  workload's good behaviour. `verify.sh` tries to write it and asserts the write failed, then checks
  from the host that nothing landed.
- **The output directory is the only writable path out of the sandbox.** Keep it a directory you
  created for this run, not a source tree, and read what lands in it before trusting it.
- **Cleanup kills only the VMs this packet recorded.** A shared host can carry another session's
  machines, and one was live throughout the runs behind this packet; the reaper is scoped by the
  boot config's path and left it alone. A cleanup that kills every smolvm process is fine on your
  laptop and destructive on a build agent.
- **Nothing here escalates privilege**, edits smolvm configuration, or touches `~/.smolvm`. The
  scripts are wrappers over the public CLI.

## Platform arms

- **Linux aarch64**: **the network-on route and the cancel path were run here on v1.18.2**, and
  the offline route, the cancel path on it and the reaper on v1.14.6, the first host on which the
  offline route completed.
- **Linux x86_64**: the offline route is verified in the material behind this packet, not re-run.
- **macOS arm64**: the offline shape is unavailable (#1192, reproduced 3 of 3 on v1.18.2). The
  network-on route and the pull-once-then-disconnect route were run end to end on v1.18.2.
  `references/macos.md`.
- **Windows x86_64**: the offline shape is unavailable for a different reason, the bake never
  completes. `references/windows.md`, **re-run on 2026-09-11 against v1.14.6** on Windows 11 Home
  build 10.0.26200.0 UBR 9445: the mount and the network-off refusal confirmed, and the bake still
  did not complete inside a ten minute cap.

## Eval prompts, and what they produced

Run on 2026-09-08 PT against v1.14.2 from the published release, under an isolated `HOME`, on
macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64). Output is verbatim.

**1. "Run this untrusted script against my repo without letting it modify the repo or reach the
network, and get the output back."**

On Linux aarch64 the **offline route** answers this directly on v1.14.6, with the network off for
the whole run: `used_host_cache=yes`, `inside_network=ok (blocked)`, `artifact=ok (42)`,
`repo_unchanged=ok`, `result=sandbox_held`. On macOS, where #1192 blocks that route, the
network-on route:

```
route=network-on
vm_pid=74421
cli_exit=0

inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (REACHED)
artifact=ok (42)
repo_unchanged=ok
result=sandbox_held
```

`inside_network=REACHED` is the expected result on that route and the reason it is the second
choice: the network was open for the whole run.

**2. "The sandboxed job is hung. Stop it."**

On Lima, a run with a `sleep 600` workload, wrapper interrupted:

```
--- recorded pid file ---
76773 /home/<user>/skp/.cache/smolvm/vms/77196d36f7bb8555/boot-config.json
--- VM still alive after the interrupt? ---
STILL RUNNING 76773 ...
--- machine list after the interrupt ---
vm-1b3d157f running (eph)   4  2048 MiB  2  0  20 GiB  10 GiB
=== cancel with the packet reaper ===
cancelled=76773 config=/home/<user>/skp/.cache/smolvm/vms/77196d36f7bb8555/boot-config.json
machines=clean
vm_processes=none
result=clean
```

The same on macOS, cancelling pid 82510 and ending clean.

**3. "Can I sandbox on this machine?"**

macOS 26.6.2 arm64, where the answer is a qualified no:

```
platform=darwin-aarch64
accel=hypervisor_framework
accel_access=ok
offline_shape=unavailable
offline_shape_blocker=smol-machines/smolvm#1192
device_budget_ok=yes
cancel_route=scripts/cleanup.sh --cancel
result=blocked
```

and `bake.sh` refuses rather than baking something unusable:

```
result=unsupported_on_macos
A baked image is only useful to a run that also mounts something, and on macOS
--oci-cache plus any -v mount times out the boot (smol-machines/smolvm#1192).
```

## Re-verified on v1.18.2

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64).

**macOS.** #1192 still holds: a bake followed by a run with one `:ro` mount failed 3 of 3 with
`agent did not become ready within 30 seconds`, while the mount without `--oci-cache` and
`--oci-cache` without the mount both passed in the same session. The preflight still says
`result=blocked` and `bake.sh` still refuses. The network-on route held:

```
inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (REACHED)
artifact=ok (42)
repo_unchanged=ok
result=sandbox_held
```

The cancel, with the wrapper killed while a `sleep 600` workload ran: `machine list` showed
`vm-552a084a running (eph)`, and `cleanup.sh --cancel --purge` reported `cancelled=72150` and
`result=clean`. The first choice in `references/macos.md` ran end to end for the first time here.

**Linux aarch64.** The network-on route held with the same six values, and the cancel cleared its
VM (`cancelled=141333`, `result=clean`). **The offline route was not re-run, for a host reason.**
That box no longer boots a guest above 2048 MiB inside the fixed 30 s readiness window, v1.16.1
installed on the same box behaves the same, and the bake helper takes 8192 MiB. `bake.sh` named it
the way `references/traps.md` describes, with `control_boot_2048=ok` and a pointer to the
network-on route, which is the diagnosis working rather than the route.

**The VPN trap, on both hosts.** With a policy route for `100.64.0.0/10` into a dummy device added
inside the guest, the way Tailscale adds one, a run on the default link printed
`wget: bad address 'example.com'`; the same routes with `--guest-subnet 10.200.0.0/30` resolved and
fetched.

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 from the published release. **Two things changed on this
release and both matter.**

**The offline route now runs on Linux, for the first time on any host available to this packet.**
On Lima `linux-kvm` (Ubuntu 24.04 aarch64) the bake completed in 59 s and the run held:

```
result=baked
Using cached image f60a20a837dc1a34 (host cache hit; no pull)
used_host_cache=yes
inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (blocked)
artifact=ok (42)
repo_unchanged=ok
result=sandbox_held
```

`inside_network=ok (blocked)` is the line the whole packet exists for: the workload reached no
network at all. Earlier releases could not get this far on any host here.

**The reaper was broken on exactly this route, and is fixed.** The pack-run path forks without
execing, so its VM child inherits the parent's argv and carries no `_boot-vm`. Measured on
v1.14.6 before the fix: `run.sh` reported `vm_pid=not_observed`, and after the CLI was killed
`cleanup.sh` reported `vm_processes=none` and `result=clean` while the VM held 234 MB. After the
fix, the same sequence reports `vm_pid=71676` and
`vm_process=... forked-under ...` with `result=vms_still_running`, and `--cancel` clears it. See
`references/traps.md`.

**macOS is unchanged**: `--oci-cache` with any mount still times out, 3 of 3 with both controls
passing in the same session, so the offline shape is still unavailable there and `bake.sh` still
refuses with the reason. The network-on route held (`artifact=ok (42)`, `result=sandbox_held`) and
the cancel path recorded and killed its VM.

## What was not run

- **The offline route on macOS.** Blocked by #1192, reproduced on v1.18.2 3 of 3 with both
  controls passing. `references/macos.md` gives the route that works there and what it costs.
- **The offline route on v1.18.2.** It last completed on Linux aarch64 on v1.14.6; the host used
  here could not boot the bake helper's 8192 MiB this time, for the reason above.
- **A GPU sandbox.** Nothing here was run against a GPU on either release.
- **The macOS first-choice route** in `references/macos.md`, which needs a `docker`, `crane`,
  `podman` or `nerdctl` binary to produce an image archive. None is installed on that host.
- **Windows.** One earlier run, recorded in `references/windows.md`.
- **S3 and `:staged` mounts**, and driving the sandbox from a CI runner.

## Related packets

- `install` for the boot this assumes and the KVM group check.
- `teardown` for the wider cleanup, and for what a leak check must exclude.
- `dev-env` when state should survive between runs, which is the opposite of this packet.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can run the offline sandbox shape, and whether the
# machine you are planning fits the guest's device budget.
#
# usage: preflight.sh [--mounts N] [--ports N]
#   --mounts N  how many -v mounts your run will pass (default 2: repo plus out)
#   --ports N   how many -p publishes it will pass (default 0)
#
# Read-only: starts no VM, bakes nothing, writes no smolvm state.
# Output is one key=value per line. The last line is result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.18.2"

# The guest gets eleven IRQs. Four -v mounts boot and five fail with "no more
# IRQs are available", and any published port costs one of those slots, so the
# budget is mounts plus ports. Measured on Windows Hypervisor Platform and the
# same budget on Linux.
DEVICE_BUDGET=4

emit() { printf '%s=%s\n' "$1" "$2"; }
note() { printf 'note=%s\n' "$1"; }

mounts=2
ports=0
while [ $# -gt 0 ]; do
    case "$1" in
        --mounts) mounts="$2"; shift ;;
        --ports)  ports="$2";  shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

blocked=0

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    emit smolvm_installed no
    blocked=1
else
    emit smolvm_installed yes
    version="$("$SMOLVM" --version 2>/dev/null | awk '{print $NF}')"
    emit smolvm_version "${version:-unknown}"
fi

emit verified_version "$VERIFIED_VERSION"
if [ -n "${version:-}" ] && [ "$version" != "unknown" ]; then
    if [ "$version" = "$VERIFIED_VERSION" ]; then
        emit version_status match
    else
        newest="$(printf '%s\n%s\n' "$version" "$VERIFIED_VERSION" | sort -V | tail -1)"
        if [ "$newest" = "$version" ]; then
            emit version_status newer
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; a sandbox is exactly where a silently changed flag matters, so check each step's output against the binary before trusting it"
        else
            emit version_status older
        fi
    fi
else
    emit version_status unknown
fi

kernel="$(uname -s)"
arch="$(uname -m)"
case "$arch" in aarch64|arm64) arch=aarch64 ;; esac

case "$kernel" in
    Darwin)
        emit platform "darwin-$arch"
        emit accel hypervisor_framework
        if [ "$(sysctl -n kern.hv_support 2>/dev/null)" = "1" ]; then
            emit accel_access ok
        else
            emit accel_access denied
            blocked=1
        fi
        # The offline shape is bake with --oci-cache, then run with mounts and
        # no network. On macOS that combination never boots.
        emit offline_shape unavailable
        emit offline_shape_blocker "smol-machines/smolvm#1192"
        blocked=1
        note "on macOS --oci-cache with any -v mount times out the boot, deterministically, so the offline shape this packet is built on cannot run here. Use references/macos.md, which gives a route that works and says what it costs you."
        for b in docker crane podman nerdctl; do
            if command -v "$b" >/dev/null 2>&1; then emit image_archive_tool "$b"; break; fi
        done
        ;;
    Linux)
        emit platform "linux-$arch"
        emit accel kvm
        if [ ! -e /dev/kvm ]; then
            emit accel_access missing
            blocked=1
            note "/dev/kvm does not exist; this host has no KVM"
        elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            emit accel_access ok
        else
            emit accel_access denied
            blocked=1
            note "your user cannot open /dev/kvm. Fix without logging out: sudo usermod -aG kvm \$USER, then run the next command through sg kvm -c '...'"
        fi
        emit offline_shape available
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        emit offline_shape unavailable
        blocked=1
        note "this script covers macOS and Linux. On Windows the --oci-cache bake never completes, so the offline shape is unavailable there too; see references/windows.md, written from a run and not re-run by this packet."
        ;;
esac

# The devices your planned run needs, against the budget.
emit planned_mounts "$mounts"
emit planned_ports "$ports"
emit device_budget "$DEVICE_BUDGET"
emit devices_requested "$((mounts + ports))"
if [ "$((mounts + ports))" -le "$DEVICE_BUDGET" ]; then
    emit device_budget_ok yes
else
    emit device_budget_ok no
    blocked=1
    note "mounts plus published ports exceeds the guest's device budget; the boot fails with 'no more IRQs are available'. Combine directories under one mount, or drop a port."
fi

# Ctrl-C does not stop a sandbox. Say so before anything is started, not after.
emit cancel_route "scripts/cleanup.sh --cancel"
emit interrupt_orphans_vm yes
emit interrupt_blocker "smol-machines/smolvm#1193"

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/bake.sh`

```bash
#!/usr/bin/env bash
# Bake an image into the host cache. This is the only step that talks to a
# registry, and it runs with the network on and nothing untrusted mounted.
#
# usage: bake.sh [<image>]      (default python:3.12-alpine)
#
# Do this before the untrusted code is anywhere near the machine. Afterwards the
# sandbox runs need no network at all, which is a materially stronger sandbox
# than granting egress and hoping the workload behaves.

set -uo pipefail

IMAGE="${1:-python:3.12-alpine}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

if [ "$(uname -s)" = "Darwin" ]; then
    printf 'result=unsupported_on_macos\n'
    printf 'A baked image is only useful to a run that also mounts something, and on macOS\n'
    printf '%s\n' '--oci-cache plus any -v mount times out the boot (smol-machines/smolvm#1192).'
    printf 'Read references/macos.md instead. Baking here would succeed and buy you nothing.\n'
    exit 2
fi

start="$(date +%s)"
out="$("$SMOLVM" machine run --mem 2048 --net --oci-cache --image "$IMAGE" -- true 2>&1)"
rc=$?
elapsed=$(( $(date +%s) - start ))
printf '%s\n' "$out" | sed 's/^/  /'

printf 'image=%s\n' "$IMAGE"
printf 'elapsed_s=%s\n' "$elapsed"

# Assert the value, not the exit code. A bake that did not cache still exits
# zero, and the run that depends on it then fails much later with a message
# about the registry.
if printf '%s' "$out" | grep -q 'baked in'; then
    printf 'result=baked\n'
    exit 0
fi

# A second bake of an already-cached image reports the cache hit instead.
if printf '%s' "$out" | grep -q 'host cache hit'; then
    printf 'result=already_baked\n'
    exit 0
fi

printf 'result=FAILED rc=%s\n' "$rc"

# Diagnose rather than hand the error back. A ready timeout here names neither
# the helper VM nor its memory, and the cause is usually one of two things.
if printf '%s' "$out" | grep -q 'did not become ready'; then
    printf 'diagnosis: the bake runs in a helper machine (init-bake-<hash>-<pid>) which takes\n'
    printf '  the DEFAULT memory, 8192 MiB, ignoring the --mem on your command. If this host\n'
    printf '  cannot boot a VM that large, the bake can never succeed and the error says so\n'
    printf '  nowhere. Control boot at 2048 MiB:\n'
    if "$SMOLVM" machine run --mem 2048 --net --image alpine -- echo CONTROL_OK 2>&1 | grep -q CONTROL_OK; then
        printf '  control_boot_2048=ok\n'
        printf '  So small VMs boot here and the helper does not: this host cannot give the bake\n'
        printf '  the memory it takes. Use the network-on route instead (scripts/run.sh\n'
        printf '  --route network-on), and read references/macos.md, which explains what that\n'
        printf '  route costs you. It is the same trade on any host that cannot bake.\n'
    else
        printf '  control_boot_2048=failed\n'
        printf '  Nothing boots here at all. This is not a bake problem: run the install\n'
        printf '  packet preflight, which checks KVM access and the macOS socket path length.\n'
    fi
else
    printf 'The bake is the only networked step. If it failed on the registry, fix that here\n'
    printf 'rather than adding --net to the workload run, which is what the CLI hint suggests\n'
    printf 'and is the opposite of what a sandbox wants.\n'
fi
exit 1
```

### `scripts/run.sh`

```bash
#!/usr/bin/env bash
# Run an untrusted command against a repo it must not modify, with no network,
# and collect its artifacts.
#
# usage: run.sh [--repo <dir>] [--out <dir>] [--image <img>] [--allow-host <h>]... -- <command...>
#   --repo <dir>        mounted read-only at /workspace (default ./repo)
#   --out  <dir>        mounted writable at /out        (default ./out)
#   --image <img>       must already be baked; see bake.sh (default python:3.12-alpine)
#   --allow-host <h>    grant egress to one host. Repeatable. Weakens the sandbox
#                       and the script says so; --allow-host implies --net.
#   --route <r>         offline (default) or network-on.
#                       offline    bake once, then run with no network at all.
#                       network-on no --oci-cache, the run pulls its own image and
#                       therefore has egress for the whole run. Use it only where
#                       offline does not work: macOS, where --oci-cache with any
#                       mount never boots (smol-machines/smolvm#1192), and any host
#                       that cannot give the bake helper its 8192 MiB.
#
# The VM's pid is recorded before the workload finishes, because Ctrl-C does not
# stop a smolvm machine: the VM outlives the CLI, `machine list` cannot see it,
# and it exits only when the untrusted workload does, which for code that hangs
# or loops is never (smol-machines/smolvm#1193). Cancel with
# `scripts/cleanup.sh --cancel`, never with Ctrl-C.

set -uo pipefail

REPO="./repo"
OUT="./out"
IMAGE="python:3.12-alpine"
ROUTE="offline"
allow=()

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO="$2"; shift ;;
        --out)        OUT="$2"; shift ;;
        --image)      IMAGE="$2"; shift ;;
        --allow-host) allow+=(--allow-host "$2"); shift ;;
        --route)      ROUTE="$2"; shift ;;
        --) shift; break ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

case "$ROUTE" in
    offline|network-on) ;;
    *) printf 'unknown route: %s (offline or network-on)\n' "$ROUTE" >&2; exit 2 ;;
esac

if [ $# -eq 0 ]; then
    printf 'no command given; everything after -- is run inside the sandbox\n' >&2
    exit 2
fi

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

if [ ! -d "$REPO" ]; then
    printf 'repo directory not found: %s\n' "$REPO" >&2
    exit 2
fi
mkdir -p "$OUT"
REPO="$(cd "$REPO" && pwd)"
OUT="$(cd "$OUT" && pwd)"

STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/sandbox.vmpids"

case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      VMS_DIR="${SMOLVM_DATA_DIR:-$HOME/.cache/smolvm}/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"

# List this HOME's smolvm VM processes, as "pid marker".
#
# Two process shapes exist and a reaper has to catch both. The plain
# `machine run` path EXECS a child whose argv[1] is `_boot-vm` and whose argv[2]
# is its boot-config path. The pack-run path, which is `--oci-cache` or any
# `init`, FORKS without execing, so the child inherits the parent's argv and
# carries no boot-config at all. Matching `_boot-vm` alone is therefore blind to
# exactly the path whose child survives an interrupt
# (smol-machines/smolvm#1193): measured on v1.14.6, it reported "none" while two
# orphaned VMs held 234 MB each.
#
# On Linux both shapes rename themselves to `libkrun VM`, the one marker that
# covers both and that no shell can hold. macOS exposes no rename, so there the
# executable path scopes the search to this HOME and the parent chain separates
# a VM from the CLI that started it.
#
# `pgrep -f _boot-vm` is not an alternative: it matches any shell whose text
# contains that string, including this script.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                [ "$(cat "$p/comm" 2>/dev/null)" = "libkrun VM" ] || continue
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                # Forked shape: nothing in argv identifies it, so scope by the
                # binary it is running.
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep cannot return ppid and the full
            # command together, and pgrep -f matches this script's own text.
            own=" $(ps -axo pid=,command= 2>/dev/null | grep -F "$SMOLVM_PREFIX/smolvm-bin" | awk '{print $1}' | tr '\n' ' ') "
            ps -axo pid=,ppid=,command= 2>/dev/null | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # Forked shape: its parent is the CLI that started it, or init
                # once that CLI is gone.
                if [ "$ppid" = 1 ]; then
                    printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX"
                else
                    case "$own" in *" $ppid "*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;; esac
                fi
            done
            ;;
    esac
}

before="$(list_vm_processes | awk '{print $1}' | sort)"

printf 'route=%s\n' "$ROUTE"
cache=(--oci-cache)
if [ "$ROUTE" = "network-on" ]; then
    # No host cache, so the run pulls its own image and needs the network for
    # the whole run. Say what that costs rather than letting it look equivalent.
    cache=()
    if [ "${#allow[@]}" -eq 0 ]; then
        allow=(--net)
        printf 'egress=all\n'
        printf 'note=network-on with no --allow-host gives the untrusted workload unrestricted egress for the whole run. Name the hosts it needs with --allow-host to narrow it.\n'
    else
        printf 'egress=granted %s\n' "${allow[*]}"
        printf 'note=the run also needs to reach the registry to pull its image, so the policy must include the registry hosts or the run will not start.\n'
    fi
    printf 'note=this is the weaker sandbox. The offline route reaches no network at all; this one is open for as long as the workload runs.\n'
elif [ "${#allow[@]}" -gt 0 ]; then
    printf 'egress=granted %s\n' "${allow[*]}"
    printf 'note=--allow-host implies --net. The workload can now reach the named hosts, and a denial looks like a DNS failure rather than a policy denial.\n'
else
    printf 'egress=none\n'
fi

logfile="$STATE_DIR/sandbox.lastrun.log"
"$SMOLVM" machine run --mem 2048 ${cache[@]+"${cache[@]}"} --image "$IMAGE" \
    --volume "$REPO:/workspace:ro" \
    --volume "$OUT:/out" \
    ${allow[@]+"${allow[@]}"} \
    -- "$@" > "$logfile" 2>&1 &
cli_pid=$!

# Record the VM before waiting on it. If the caller kills this script, the pid
# in that file is the only route back to the machine.
# 90 s: long enough to see the VM appear on a host that is pulling an image,
# and bounded so a workload that finishes instantly does not stall the script.
recorded=""
waited=0
while [ "$waited" -lt 90 ]; do
    while read -r pid cfg; do
        [ -n "$pid" ] || continue
        case "$(printf '%s\n' "$before" | grep -c "^$pid$")" in
            0) printf '%s %s\n' "$pid" "$cfg" >> "$PIDFILE"; recorded="$pid" ;;
        esac
    done <<EOF
$(list_vm_processes)
EOF
    [ -n "$recorded" ] && break
    kill -0 "$cli_pid" 2>/dev/null || break
    sleep 1
    waited=$((waited + 1))
done

if [ -n "$recorded" ]; then
    printf 'vm_pid=%s\n' "$recorded"
    printf 'vm_pid_recorded_in=%s\n' "$PIDFILE"
else
    printf 'vm_pid=not_observed\n'
    printf 'note=the VM was not seen before the run ended, which is normal for a command that finishes in under a second. Nothing to cancel.\n'
fi

wait "$cli_pid"
rc=$?
sed 's/^/  /' "$logfile"

# On the offline route the cache-hit line is the assertion that the bake worked
# and that this run reached no registry. Without it the run pulled, which means
# it had network, which means it was not the sandbox you asked for.
if [ "$ROUTE" = "offline" ]; then
    if grep -q 'host cache hit' "$logfile"; then
        printf 'used_host_cache=yes\n'
    else
        printf 'used_host_cache=no\n'
        printf 'note=no host cache hit on the offline route. Run bake.sh first: an ordinary earlier pull does not make a later run offline-capable, because the runtime still resolves the tag through the registry.\n'
    fi
else
    printf 'used_host_cache=n_a_on_this_route\n'
fi

printf 'cli_exit=%s\n' "$rc"
printf 'next: scripts/verify.sh, then scripts/cleanup.sh\n'
exit "$rc"
```

### `scripts/verify.sh`

```bash
#!/usr/bin/env bash
# Assert the sandbox held: from inside the guest, and from the host afterwards.
#
# usage: verify.sh [--repo <dir>] [--out <dir>] [--expect-file <name>]
#                  [--expect <value>] [--image <img>] [--route offline|network-on]
#
# Two halves, and both are needed. The inside half proves the workload could not
# write the repo and could not reach the network; the host half proves the
# artifact came out and the repo is unchanged. A run that "succeeded" tells you
# neither.

set -uo pipefail

REPO="./repo"
OUT="./out"
EXPECT_FILE="result.txt"
EXPECT=""
IMAGE="python:3.12-alpine"
ROUTE="offline"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)        REPO="$2"; shift ;;
        --out)         OUT="$2"; shift ;;
        --expect-file) EXPECT_FILE="$2"; shift ;;
        --expect)      EXPECT="$2"; shift ;;
        --image)       IMAGE="$2"; shift ;;
        --route)       ROUTE="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

printf 'route=%s\n' "$ROUTE"
REPO="$(cd "$REPO" && pwd)"
OUT="$(cd "$OUT" && pwd)"

# The probe must run in the same shape as the real run, or it proves nothing
# about that run. On the network-on route the workload has egress by
# construction, so the network assertion changes rather than disappearing.
case "$ROUTE" in
    offline)    cache=(--oci-cache); net=();       expect_net=blocked ;;
    network-on) cache=();            net=(--net);  expect_net=REACHED ;;
    *) printf 'unknown route: %s (offline or network-on)\n' "$ROUTE" >&2; exit 2 ;;
esac

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf '%s=ok (%s)\n' "$1" "$2"
    else
        printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"
        fail=1
    fi
}

# --- from inside the guest, in the same shape a real run uses ----------------
inside="$("$SMOLVM" machine run --mem 2048 ${cache[@]+"${cache[@]}"} ${net[@]+"${net[@]}"} --image "$IMAGE" \
    --volume "$REPO:/workspace:ro" \
    --volume "$OUT:/out" \
    -- sh -c '
        touch /workspace/SANDBOX_PROBE 2>/dev/null && echo "workspace=WRITABLE" || echo "workspace=readonly"
        touch /out/SANDBOX_PROBE      2>/dev/null && echo "out=writable"       || echo "out=READONLY"
        wget -q -T3 -O- http://example.com >/dev/null 2>&1 && echo "net=REACHED" || echo "net=blocked"
    ' 2>&1 | tr -d '\r')"
printf '%s\n' "$inside" | sed 's/^/  /'

check inside_workspace "$(printf '%s' "$inside" | sed -n 's/^workspace=//p')" readonly
check inside_out       "$(printf '%s' "$inside" | sed -n 's/^out=//p')"       writable
check inside_network   "$(printf '%s' "$inside" | sed -n 's/^net=//p')"       "$expect_net"
if [ "$ROUTE" = "network-on" ]; then
    printf 'note=on this route the workload reaching the network is the expected result, not a failure. It is the price of the route, and the reason offline is the default.\n'
fi

# --- from the host afterwards ------------------------------------------------
if [ -n "$EXPECT" ]; then
    check artifact "$(cat "$OUT/$EXPECT_FILE" 2>/dev/null | tr -d '\r\n')" "$EXPECT"
elif [ -s "$OUT/$EXPECT_FILE" ]; then
    printf 'artifact=present (%s)\n' "$OUT/$EXPECT_FILE"
else
    printf 'artifact=FAIL missing or empty: %s\n' "$OUT/$EXPECT_FILE"
    fail=1
fi

# The probe above tried to write the repo. If the read-only mount leaked, the
# evidence is sitting in the repo now.
if [ -e "$REPO/SANDBOX_PROBE" ]; then
    printf 'repo_unchanged=FAIL the read-only mount leaked: %s/SANDBOX_PROBE exists\n' "$REPO"
    fail=1
else
    printf 'repo_unchanged=ok\n'
fi
rm -f "$OUT/SANDBOX_PROBE"

if [ "$fail" -eq 0 ]; then printf 'result=sandbox_held\n'; else printf 'result=FAILED\n'; fi
exit "$fail"
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Cancel or clean up a sandbox run, then prove nothing is left running.
#
# usage: cleanup.sh [--cancel] [--purge]
#   --cancel   kill the VMs run.sh recorded. THIS IS THE SANDBOX'S CANCEL.
#              Ctrl-C is not: it returns the shell to you and leaves the VM
#              running, invisible to `machine list`, until the untrusted
#              workload finishes on its own (smol-machines/smolvm#1193).
#   --purge    remove the recorded-pid file once nothing is left
#
# With no flags it waits, asserts the machine list is empty, and reports any VM
# process still alive under this HOME's state.

set -uo pipefail

PACKET="sandbox"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
PIDFILE="$STATE_DIR/$PACKET.vmpids"

cancel=0
purge=0
while [ $# -gt 0 ]; do
    case "$1" in
        --cancel) cancel=1 ;;
        --purge)  purge=1 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      VMS_DIR="${SMOLVM_DATA_DIR:-$HOME/.cache/smolvm}/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"

# List this HOME's smolvm VM processes, as "pid marker".
#
# Two process shapes exist and a reaper has to catch both. The plain
# `machine run` path EXECS a child whose argv[1] is `_boot-vm` and whose argv[2]
# is its boot-config path. The pack-run path, which is `--oci-cache` or any
# `init`, FORKS without execing, so the child inherits the parent's argv and
# carries no boot-config at all. Matching `_boot-vm` alone is therefore blind to
# exactly the path whose child survives an interrupt
# (smol-machines/smolvm#1193): measured on v1.14.6, it reported "none" while two
# orphaned VMs held 234 MB each.
#
# On Linux both shapes rename themselves to `libkrun VM`, the one marker that
# covers both and that no shell can hold. macOS exposes no rename, so there the
# executable path scopes the search to this HOME and the parent chain separates
# a VM from the CLI that started it.
#
# `pgrep -f _boot-vm` is not an alternative: it matches any shell whose text
# contains that string, including this script.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                [ "$(cat "$p/comm" 2>/dev/null)" = "libkrun VM" ] || continue
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                # Forked shape: nothing in argv identifies it, so scope by the
                # binary it is running.
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep cannot return ppid and the full
            # command together, and pgrep -f matches this script's own text.
            own=" $(ps -axo pid=,command= 2>/dev/null | grep -F "$SMOLVM_PREFIX/smolvm-bin" | awk '{print $1}' | tr '\n' ' ') "
            ps -axo pid=,ppid=,command= 2>/dev/null | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # Forked shape: its parent is the CLI that started it, or init
                # once that CLI is gone.
                if [ "$ppid" = 1 ]; then
                    printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX"
                else
                    case "$own" in *" $ppid "*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;; esac
                fi
            done
            ;;
    esac
}

# 1. Cancel: kill exactly the VMs run.sh recorded, and only those.
if [ "$cancel" -eq 1 ]; then
    if [ -s "$PIDFILE" ]; then
        while read -r pid cfg; do
            [ -n "$pid" ] || continue
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null && printf 'cancelled=%s config=%s\n' "$pid" "$cfg"
            else
                printf 'already_gone=%s\n' "$pid"
            fi
        done < "$PIDFILE"
    else
        printf 'cancelled=none_recorded\n'
    fi
fi

# 2. An ephemeral machine's entry retires after the run returns, not with it, so
# an immediate assertion fails on a healthy host. This is the single most likely
# false failure in a scripted sandbox.
sleep 20

# 3. Assert values.
listing="$("$SMOLVM" machine list 2>&1)"
if printf '%s' "$listing" | grep -q 'No machines found'; then
    printf 'machines=clean\n'
else
    printf 'machines=remaining\n'
    printf '%s\n' "$listing" | sed 's/^/  /'
    # These were not created by this packet, so nothing here will remove them.
    # Say what does, rather than leaving the reader to guess: delete prompts and
    # defaults to No without --force, and a branched machine also needs --cascade.
    printf 'note=this packet did not create these, so it will not delete them. By name:\n'
    printf '  smolvm machine stop --name <NAME> && smolvm machine delete --name <NAME> --force\n'
    printf '  add --cascade for a machine that was branched from another\n'
fi

# `_shared` is the image store bake.sh writes into. It is the cache, not
# residue, so counting it as a leak gives a false positive on every host that
# has ever baked.
if [ -d "$VMS_DIR" ]; then
    left="$(find "$VMS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared 2>/dev/null | wc -l | tr -d ' ')"
else
    left=0
fi
printf 'vm_dirs=%s\n' "$left"
if [ "$left" -gt 0 ]; then
    printf 'note=leftover VM directories are not necessarily a leak: smolvm serve start prints "Reclaimed N dangling VM data dir(es)" on startup and clears them.\n'
fi

# What a bake leaves behind is cache, not residue, and deleting it costs you the
# offline route. Report both places it can live: `_shared` under the VM state,
# and the pack cache, which is where a v1.14.2 bake actually landed on macOS.
case "$(uname -s)" in
    Darwin) PACK_CACHE="$HOME/Library/Caches/smolvm-pack" ;;
    *)      PACK_CACHE="$HOME/.cache/smolvm-pack" ;;
esac
if [ -d "$VMS_DIR/_shared" ]; then
    printf 'image_cache_shared=%s\n' "$(du -sk "$VMS_DIR/_shared" 2>/dev/null | awk '{printf "%dMB", $1/1024}')"
else
    printf 'image_cache_shared=absent\n'
fi
if [ -d "$PACK_CACHE" ]; then
    printf 'image_cache_pack=%s\n' "$(du -sk "$PACK_CACHE" 2>/dev/null | awk '{printf "%dMB", $1/1024}')"
else
    printf 'image_cache_pack=absent\n'
fi
printf 'note=both caches are kept on purpose. Removing them costs you the offline route and the next bake pays for it again.\n'

# 4. Verify: after a cancel, this is the assertion that the cancel worked.
found=0
while read -r pid cfg; do
    [ -n "$pid" ] || continue
    found=1
    printf 'vm_process=%s config=%s\n' "$pid" "$cfg"
done <<EOF
$(list_vm_processes)
EOF

if [ "$found" -eq 0 ]; then
    printf 'vm_processes=none\n'
    [ "$purge" -eq 1 ] && rm -f "$PIDFILE"
    printf 'result=clean\n'
    exit 0
fi

printf 'result=vms_still_running\n'
printf 'rerun with --cancel, after checking none of the above belongs to another session.\n'
exit 1
```

## Sandbox traps

### Ctrl-C does not stop the machine, and which route that applies to

**On the offline route this is the whole reason the packet has a cancel script.**
`machine run` with `--oci-cache` or `--init` takes the pack-run boot path, which on Unix forks a
session leader that never execs, so the VM child is detached with no parent-death arming. Interrupt
the CLI and the VM keeps running, `machine list` reports `No machines found`, no VM cache directory
exists, and there is no CLI route to what is still running. It exits only when the untrusted
workload does, which for code that hangs or loops is unbounded. This is
[smol-machines/smolvm#1193](https://github.com/smol-machines/smolvm/issues/1193).

**On the plain path it does not happen**, and that is worth knowing rather than assuming the worst
everywhere. Measured on Ubuntu 24.04 aarch64 on 2026-09-08: a `machine run` with no `--oci-cache`,
one mount and a `sleep 600` workload, sent `SIGINT` on the CLI itself, left `machine list` empty
and **no VM process at all**. The plain path spawns an exec'd `_boot-vm` that dies with the CLI.

So:

| route | Ctrl-C on the CLI | cancel with |
|---|---|---|
| offline (`--oci-cache`) | VM survives, invisible to `machine list` | `scripts/cleanup.sh --cancel` |
| network-on (no `--oci-cache`) | VM dies with the CLI (verified on Linux) | either |

On v1.18.2 the network-on route was measured again with the **wrapper** killed and the CLI left
alone: the run stayed in `machine list` as `running (eph)` on macOS arm64 and on Linux aarch64, and
`scripts/cleanup.sh --cancel` killed the recorded pid on both.

**Do not rely on the second row to cancel a sandbox.** `run.sh` records the VM's pid on both
routes because the difference is a boot-path detail that can change between releases, and because
interrupting the *wrapper* rather than the CLI leaves the CLI and its VM running on either route,
which was observed on both hosts here.

### Assert no machines left only after a wait

A successful `machine run` returns **before** its ephemeral entry retires. Asserting an empty
machine list immediately fails on a healthy host, and it is the single most likely false failure in
a scripted sandbox. `scripts/cleanup.sh` waits before asserting.

### A network-off run that dies on the manifest means the bake was skipped

```
Error: fetching manifest docker.io/library/python:3.12-alpine: ... network is unreachable
Hint: networking is disabled. Add --net to enable image pulls
```

**An ordinary earlier pull does not make a later run offline-capable**: the runtime still resolves
the tag through the registry. Bake the image with `scripts/bake.sh` instead.

The CLI's own hint points at re-opening the network, which is the opposite of what a sandbox wants.
Adding `--net` here is how an offline sandbox quietly becomes a networked one.

### A blocked host looks like a DNS bug, not a policy denial

With `--allow-host example.com`, reaching `pypi.org` fails as `wget: bad address 'pypi.org'`.
Nothing says "denied by policy". Do not spend time debugging the guest's resolver.

### The bake helper ignores `--mem`

The bake runs in a helper machine named `init-bake-<hash>-<pid>` which takes the **default** memory,
8192 MiB, whatever `--mem` you passed to the outer command. Confirmed on Ubuntu 24.04 aarch64 on
2026-09-08 by reading `machine ls --json` while a bake was in flight.

**On a host that cannot boot a VM that large, the bake can never succeed and the error names
neither the helper nor its memory:**

```
Error: config operation failed: init-layer bake:
  `smolvm machine start --name init-bake-f60a20a837dc1a34-68696` failed (exit status: 1):
  Error: agent operation failed: start machine: agent operation failed: wait for ready:
  agent did not become ready within 30 seconds
```

That is exactly the message a loaded host produces, so it invites the wrong diagnosis.
`scripts/bake.sh` runs a 2048 MiB control boot on failure and tells you which of the two it is.

`SMOLVM_AGENT_READY_TIMEOUT_SECS` does not help: the string is in the binary, but the failure is in
the inner `machine start`, which uses the hard-coded 30 s limit. Verified by setting it to 180 and
watching the bake fail at 30 s anyway.

### A guest that runs a VPN loses its gateway and resolver

A virtio-net guest's link is `100.96.0.0/30` by default: the guest is `.2`, and the gateway and
the resolver are both `.1`. `--allow-host` and `--allow-cidr` select virtio-net, so every sandbox
run that grants egress gets that link. A plain `--net` run uses TSI and has no such link, which
was observed and not tested against a VPN. Tailscale and other carrier NAT VPNs claim `100.64.0.0/10`, which contains it, and route
it into their own device.

Measured on v1.18.2 on macOS arm64 and Linux aarch64, 2026-09-24, by adding in the guest what
Tailscale adds: `ip rule add to 100.64.0.0/10 lookup 52 prio 5270` and a table 52 route for
`100.64.0.0/10` into a dummy device.

| link | `ip route get 100.96.0.1` | lookup | fetch |
|---|---|---|---|
| default, `--allow-host example.com` | `dev ts0` | `bad address 'example.com'` | failed |
| `--guest-subnet 10.200.0.0/30`, same routes | not used | resolved | fetched |

With the flag the guest is `10.200.0.2/30` and the gateway and resolver are `10.200.0.1`. Three
things to know about it: **it implies `--net`**, so it does not belong on the offline route; it
requires virtio-net, and `--net-backend tsi` with it is refused with `--guest-subnet requires the
virtio-net backend`; and a range inside `100.64.0.0/10` is accepted without a warning, which
brings the clash back.

### `machine egress-events` cannot inspect an ephemeral run

It takes `--name` and defaults to a machine called `default`, so it applies to named machines. An
ephemeral run's machine is gone before you can name it, so egress denials from a `machine run` are
not retrievable this way.

### Counting orphans: why `pgrep -f`, `readlink` and `_boot-vm` alone all fail

Three reapers that look right. Each misses a different thing, and the third is the one that
matters here.

`pgrep -f _boot-vm` matches any process whose command line contains that string, including the
script doing the counting, so it reports orphans that do not exist.

`readlink /proc/<pid>/exe` is unreliable in the other direction. For the **exec'd** VM child it
returns `Permission denied` to the user who started it, so a reaper built on it reports nothing.
On v1.14.6 it is readable for the **forked** child, which makes it useful for scoping but not for
finding.

**Matching `argv[1] == "_boot-vm"` is exact, and still blind to the route this packet uses by
default.** There are two VM process shapes:

| route | child | argv[1] | carries its boot config |
|---|---|---|---|
| plain `machine run` | exec'd | `_boot-vm` | yes, in argv[2] |
| pack-run (`--oci-cache`, or any `init`) | **forked, never exec'd** | inherited, so `machine` | **no** |

The forked child inherits the parent's whole command line, so nothing in its argv says it is a VM.
Measured on v1.14.6 on Ubuntu 24.04 aarch64: with two orphaned pack-run VMs alive at 234 MB each,
`cleanup.sh` reported `vm_processes=none` and `result=clean`, and `run.sh` had recorded
`vm_pid=not_observed`. **The reaper was blind to exactly the path that survives an interrupt**,
which is the pack-run path, and sighted only on the path that does not.

**What works.** On Linux both shapes rename themselves to `libkrun VM`, which no shell can hold,
so `scripts/cleanup.sh` matches `/proc/<pid>/comm` and then scopes by argv[2] when it is there and
by the executable's path when it is not. macOS exposes no rename, so there the search is scoped by
the executable path under this `HOME` and the parent chain separates a VM from the CLI that
started it. Verified against a live orphan on both hosts: the same sequence now reports
`vm_process=... forked-under ...` and `result=vms_still_running`, and `--cancel` clears it.

### What is cache and what is residue

`ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check. Two separate caches exist and neither is
residue:

- `vms/_shared`, the image store the runbooks describe.
- **the pack cache**, `~/Library/Caches/smolvm-pack` on macOS and `~/.cache/smolvm-pack` on Linux.
  On v1.14.2 on macOS a bake of one alpine image landed **here** and produced no `_shared` at all:
  114 MB in the pack cache, `vms/_shared` absent. Observed 2026-09-08.

`scripts/cleanup.sh` reports both and keeps both. Deleting them costs you the offline route, and
the next bake pays for it again.

Leftover VM directories are also not necessarily a leak: `smolvm serve start` prints
`Reclaimed N dangling VM data dir(es)` on startup and clears them.

### There is no way to list what has been baked

`smolvm machine images` requires `--name` and reports one machine's images, so cache state is not
observable. If a run unexpectedly pulls, you cannot inspect the cache to find out why. The
`used_host_cache` line from `scripts/run.sh` is the only signal you get, which is why it is asserted
rather than printed.

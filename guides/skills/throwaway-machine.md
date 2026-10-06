---
title: "Throwaway machine: run untrusted code with no network"
---

# Throwaway machine: run untrusted code with no network

Runs untrusted code in a throwaway smolvm microVM against a repo it must not modify, with no network unless explicitly granted, and collects artifacts from a writable output directory. Use when executing an agent's generated script, a pull request's test suite, or any code that should not be trusted with the host; when a workload needs egress granted one host at a time; or when a run has to be cancelled, because Ctrl-C on the wrapper script leaves the VM running, and on releases before v1.20.2 so does Ctrl-C on the CLI. Do not use it for a development environment that is re-entered across sessions, for running a Docker daemon inside a machine, or for installing smolvm itself, which is the install packet.

Verified on **smolvm v1.23.0** on macOS arm64, 2026-10-04, by the offline route, the network-on route
and the cancel; on Linux aarch64 by the offline route and the cancel on v1.20.2, 2026-09-29, and the
network-on route on v1.18.2, 2026-09-24. Done means the command's output landed in your writable directory,
the repo is unchanged, the workload could not reach the network, and nothing is left running.
The Linux runs used the scripts of their date; this version's preflight, run and cleanup scripts
ran on Linux aarch64 on v1.22.2 on 2026-10-03.

**The cancel is `scripts/cleanup.sh --cancel`, never Ctrl-C**: on `run.sh` Ctrl-C leaves the CLI
and its VM running on v1.20.2 too, as "Cancelling" below measures.

Two issues shaped this packet and **v1.20.2 fixed both on macOS and Linux**; older releases still
have them:

- **[#1193](https://github.com/smol-machines/smolvm/issues/1193)**, fixed in v1.20.2: before it,
  a cached run's VM outlives an interrupted CLI, invisible to `machine list`.
- **[#1192](https://github.com/smol-machines/smolvm/issues/1192)**, fixed in v1.20.2: before it, a
  cached run with any mount never boots on macOS; `references/macos.md` gives the older releases a
  route.

## Workflow

**If you have no script to isolate, make one.** A file that reads a path under `/workspace`, tries
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

`device_budget_ok=no` means the boot will fail with `no more IRQs are available`. On x86_64
through v1.22.2 the guest has eleven IRQs: **four `-v` mounts boot and five do not, and publishing
any port, or granting egress, adds one device**. arm64 guests have 128, and the preflight prints
`device_budget_ok=not_limiting` there. v1.23.0 ships a libkrun whose x86_64 guests have IRQs 5 to 23
(#1521); its ceiling was not measured, and the preflight applies the budget through v1.22.2 only.
Combine directories under one mount rather than discovering this at boot.

`offline_shape=unavailable` means this host cannot run the shape below: macOS before v1.20.2
(#1192), or Windows. The preflight cannot see whether the 8192 MiB bake helper fits; `bake.sh`
finds that out in step 2 and says so.

**2. Bake the image. This is the only step in which a machine has a network.**

```bash
scripts/bake.sh python:3.12-alpine
```

Network on, nothing untrusted mounted, done before the untrusted code is anywhere near the machine.
Afterwards the runs' machines need no network at all, which is materially stronger isolation than
granting egress and hoping. The host CLI still asks the registry for the image's manifest on every
`--oci-cache` run, to authorize the pull and to notice a tag that moved, so the host needs to reach
the registry; the workload does not.

**3. Run the untrusted command.**

```bash
scripts/run.sh --repo ./repo --out ./out -- sh -c 'python3 /workspace/calc.py > /out/result.txt'
```

The repo is mounted read-only at `/workspace`, or at the path `--repo-path` names, the output
directory writable at `/out`, and the run has no network. It prints `used_host_cache=yes`, which
is the assertion that the bake worked and that this run's machine pulled nothing: without it the
guest pulled, which means it had network, which means it was not the isolation you asked for.

It also prints `vm_pid=` and records it. **That pid is the only route back to the machine** if the
run has to be stopped.

**A script that is not in the repo** goes into the output directory before the run, and the
command calls it from there, as `sh /out/check.sh`. The output directory is the one path the run
can write, so nothing else on the host is exposed, and the repo stays unchanged.

To grant egress, name hosts one at a time:

```bash
scripts/run.sh --allow-host example.com --repo ./repo --out ./out -- <command>
```

**4. Verify. Both halves, because either alone passes when the isolation is broken.**

```bash
scripts/verify.sh --expect-file result.txt --expect 42
```

```
inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (blocked)
artifact=ok (42)
repo_unchanged=ok
result=isolation_held
```

The inside half proves the workload could not write the repo and could not reach the network; the
host half proves the artifact came out and the repo is unchanged. A run that merely exited zero
tells you neither.

`verify.sh` probes the shape without a grant. After a run with `--allow-host`, its
`inside_network` line does not describe that run's egress.

`--expect` takes one value and compares it with the whole file, newlines removed. For output of
several lines, have the command write the one value to check into a file of its own and name that
with `--expect-file`, or leave `--expect` off and the step checks only that the file is there and
not empty. The repo check looks for the step's own probe file; it does not compare the repo's
other files.

**5. Clean up, or cancel.**

```bash
scripts/cleanup.sh --purge            # after a run finished
scripts/cleanup.sh --cancel --purge   # to stop a run that is still going
```

`--cancel` kills exactly the VMs `run.sh` recorded and then verifies that nothing is left. It waits
up to 20 seconds, polling, before asserting an empty machine list, and says so, because the ephemeral entry retires
after the run returns and an immediate assertion fails on a healthy host.

## Cancelling, and why Ctrl-C is not it

On v1.20.2, Ctrl-C or `SIGKILL` on the CLI itself ends the VM within a second on both routes, on
macOS arm64 and Linux aarch64. **Interrupting `run.sh` is not a cancel**: the CLI it backgrounds
ignores `SIGINT`, so Ctrl-C on the script left the CLI and its VM running on the offline route on both
hosts, and killing the script alone left them on either route. For code that hangs or loops that is
unbounded exposure.

Before v1.20.2 the offline route is worse: interrupting the CLI itself leaves the VM running with no
CLI route to it, roughly 230 MB held per survivor (#1193). `references/traps.md` has the
measurements for each release and route. Use `--cancel`.

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
- **`references/macos.md`** if you are on macOS with a release before v1.20.2. The offline shape
  does not work there; that page gives a route that does and says what it costs.
- **`references/windows.md`** if you are on Windows. The bake never completes there, so the offline
  shape is unavailable for a different reason, and the reaper has to be broader.

## Security defaults, and why they are the defaults

- **No network is the default because it is the only guarantee that does not depend on the
  workload's cooperation.** An egress policy is a filter on what untrusted code asks for; no network
  is a property of the machine. The bake exists so that the offline run is possible at all.
- **`--allow-host` grants a name and its subdomains, and the run still has a network stack.**
  `--allow-host-pattern` grants the exact name only. Prefer either to `--net`, but treat it as a
  narrower opening rather than as no opening. A denial under it looks like a DNS
  failure, so a workload can fail confusingly rather than obviously.
- **The repo is `:ro` because a read-only mount is enforced by the guest kernel**, not by the
  workload's good behaviour. `verify.sh` tries to write it and asserts the write failed, then checks
  from the host that nothing landed.
- **The output directory is the only writable path out of the machine.** Keep it a directory you
  created for this run, not a source tree, and read what lands in it before trusting it.
- **Cleanup kills only the VMs this packet recorded.** A shared host can carry another session's
  machines, and one was live throughout the runs behind this packet; the reaper is scoped by the
  boot config's path and left it alone. A cleanup that kills every smolvm process is fine on your
  laptop and destructive on a build agent.
- **Nothing here escalates privilege**, edits smolvm configuration, or touches `~/.smolvm`. The
  scripts are wrappers over the public CLI.

## Platform arms

- **Linux aarch64**: **the offline route and the cancel path on both routes were run here on
  v1.20.2**, 2026-09-29; the network-on route end to end on v1.18.2, and once on v1.22.2.
- **Linux x86_64**: the offline route was verified on v1.14.2 on an NVIDIA A10 cloud host, not
  re-run since.
- **macOS arm64**: **the offline route, the network-on route and the cancel path on both were run
  here on v1.23.0**, 2026-10-04. Before v1.20.2 the offline shape is unavailable (#1192, reproduced
  3 of 3 on v1.18.2), and `references/macos.md` gives the routes run on v1.18.2.
- **Windows x86_64**: the offline shape is unavailable for a different reason, the bake never
  completes. `references/windows.md`, **re-run on 2026-10-03 against v1.22.2** on Windows 11 Home
  build 10.0.26200 UBR 9457: the mount, the artifact directory and the network-off refusal
  confirmed, the bake still did not complete inside a five minute cap in any of four shapes, and a
  plain foreground run interrupted by Ctrl-C or a kill left its VM running.

## Eval prompts, and what they produced

**1. "Run this untrusted script against my repo without letting it modify the repo or reach the
network, and get the output back."**

The offline route on macOS arm64, with the network off for the whole run; this is v1.20.2's output,
and v1.22.2 and v1.23.0 gave the same values:

```
route=offline
egress=none
used_host_cache=yes
inside_workspace=ok (readonly)
inside_out=ok (writable)
inside_network=ok (blocked)
artifact=ok (42)
repo_unchanged=ok
result=isolation_held
```

On macOS before v1.20.2, where #1192 blocks that route, the network-on route gives the same values
with `inside_network=ok (REACHED)`, which is the reason it is the second choice: the network was
open for the whole run.

**2. "The isolated job is hung. Stop it."**

With a `sleep 600` workload and the wrapper interrupted, the VM was still listed as running, and
`scripts/cleanup.sh --cancel --purge` ended it:

```
cancelled=76773 config=/home/<user>/skp/.cache/smolvm/vms/77196d36f7bb8555/boot-config.json
machines=clean
vm_processes=none
result=clean
```

That is Lima on v1.14.2, on the network-on route. On the offline route the VM is a forked child, and
on v1.22.2 and v1.23.0 on macOS the same cancel printed `cancelled=<pid> config=forked-under
<HOME>/.smolvm`.

**3. "Can I run untrusted code on this host?"**

On macOS arm64 on v1.23.0 the preflight says `offline_shape=available` and `result=ready`. Before
v1.20.2 it says `offline_shape=unavailable`, `offline_shape_blocker=smol-machines/smolvm#1192` and
`result=blocked`, and `bake.sh` refuses with `result=unsupported_on_macos` rather than baking
something unusable.

## Re-verified on v1.23.0

Run 2026-10-04 PT against v1.23.0 from the published release, checksum checked, under a fresh
isolated `HOME` on macOS 27.0.1 arm64, once. On Lima `linux-kvm` (Ubuntu 24.04 aarch64) the
checks named below ran once, so the Linux stamp stays on its earlier release.

**macOS: every step on both routes.** The preflight said `result=ready`, `offline_shape=available`
and `device_budget_ok=not_limiting`, `bake.sh` `baked in 5s` and `result=baked`, the offline run
`used_host_cache=yes`, and `verify.sh` gave `inside_workspace=ok (readonly)`, `inside_out=ok
(writable)`, `inside_network=ok (blocked)`, `artifact=ok (42)`, `repo_unchanged=ok` and
`result=isolation_held`. A run granted `--allow-host example.com` reached it, and the network-on
route gave `inside_network=ok (REACHED)` with the rest unchanged. `cleanup.sh --cancel --purge`
reported `cancelled=<pid> config=forked-under <HOME>/.smolvm` and `result=clean`. The persistent
machine with no network in `README.md` booted `python:3.12-alpine` with the repo read-only.

Linux aarch64: the same persistent machine with no network started in 12 s, the guest's `touch`
on `/workspace` gave `Read-only file system`, `wget` gave `bad address 'example.com'`, and `42`
reached the output directory. The offline route ran end to end: `baked in 72s`,
`used_host_cache=yes`, `inside_network=ok (blocked)`, `artifact=ok (42)`, `repo_unchanged=ok`
and `result=isolation_held`.

## Re-verified on v1.22.2

Run 2026-10-03 PT against v1.22.2 from the published release, checksum checked, under an isolated
`HOME` on macOS 27.0.1 arm64, twice, the second time from a fresh `HOME`. On Lima `linux-kvm`
(Ubuntu 24.04 aarch64) on 2026-10-03 guests above 2048 MiB timed out, so the Linux lines below are
a single run and the Linux stamp stays on its earlier release.

**macOS: every step on both routes.** The preflight said `result=ready` and `offline_shape=available`,
`bake.sh` `result=baked`, the offline run `used_host_cache=yes`, and `verify.sh` gave
`inside_workspace=ok (readonly)`, `inside_out=ok (writable)`, `inside_network=ok (blocked)`,
`artifact=ok (42)`, `repo_unchanged=ok` and `result=isolation_held`. A run granted
`--allow-host example.com` reached it, and the network-on route gave `inside_network=ok (REACHED)`
with the rest unchanged. `cleanup.sh --cancel --purge` reported `cancelled=<pid>` and
`result=clean`. Ctrl-C and `SIGKILL` on the CLI of a cached run with a mount ended the VM within a
second; Ctrl-C to `run.sh`'s process group left the CLI and its VM alive on the offline route and
not on the network-on route, as on v1.20.2. Once in five bakes, the first, `bake.sh` printed
`hdiutil create failed - Resource busy` and still `result=baked`; the run that followed used the
cache.

**Linux aarch64, single run.** The network-on route held with `inside_network=ok (REACHED)` and
`artifact=ok (42)`. The offline route did not run: the bake's helper takes 8192 MiB, `bake.sh`
said so, and its control boot at 2048 passed.

## Re-verified on v1.20.2

Run 2026-09-29 PT against v1.20.2 from the published release, checksum checked, under an isolated
`HOME`, on macOS 27.0.1 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64).

**macOS: #1192 is fixed.** The command from the issue, `machine run --net -v <dir>:/tmp --oci-cache
--image alpine:latest -- date`, passed 3 of 3, every row of the table in `references/macos.md`
passed 3 of 3, and the offline route ran end to end with the values shown in eval 1.

**Linux aarch64: the offline route ran**, the last time it has on Linux: `bake.sh` reported
`baked in 39s` and `result=baked`, then `used_host_cache=yes`, `inside_network=ok (blocked)`,
`artifact=ok (42)`, `repo_unchanged=ok` and `result=isolation_held`.

**#1193 is fixed, and the wrapper still orphans.** On both hosts a `sleep 600` run's VM was gone
within a second of Ctrl-C or `SIGKILL` on the CLI, on both routes, with `machine list` empty. Ctrl-C
to `run.sh`'s process group left the VM alive on the offline route on both hosts and on the
network-on route on Linux, and killing `run.sh` alone left it alive on both routes on both hosts;
`cleanup.sh --cancel --purge` reported `cancelled=<pid>` and `result=clean` every time.

## What was not run

- **The offline route on Linux on v1.18.2 and v1.22.2.** The Lima `linux-kvm` host could not boot
  the bake helper's 8192 MiB in time on those releases; it ran on v1.20.2 and v1.23.0. The branch
  of `bake.sh` that reports a helper too large for the host ran on v1.23.0 only against a stub
  that failed the bake, not on a host that could not boot the helper.
- **A GPU workload.** Nothing here was run against a GPU on either release.
- **The macOS second-choice route** in `references/macos.md` since v1.16.1. An agent following
  this packet ran it on macOS arm64 on v1.16.1, 2026-09-15, with an archive built by `crane`
  0.22.1; it has not been re-run since, and the `docker save` form on that page was not run.
- **Windows, the cancel scripts.** `scripts/*.sh` do not run there; `references/windows.md` has the
  measurements a port would need.
- **S3 and `:staged` mounts**, and driving the packet from a CI runner.

## Related packets

- `install` for the boot this assumes and the KVM group check.
- `teardown` for the wider cleanup, and for what a leak check must exclude.
- `dev-env` when state should survive between runs, which is the opposite of this packet.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can run the offline shape, and whether the
# machine you are planning fits the guest's device budget.
#
# usage: preflight.sh [--mounts N] [--ports N]
#   --mounts N  how many -v mounts your run will pass (default 2: repo plus out)
#   --ports N   how many -p publishes it will pass (default 0); any number is one device,
#               and so is any --allow-host or --allow-cidr: pass --ports 1 for those
#
# Read-only: starts no VM, bakes nothing, writes no smolvm state.
# Output is one key=value per line. The last line is result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.23.0"

# v1.20.2 fixed both issues this packet was built around (#1467): a cached run
# with a mount boots on macOS (#1192), and a cached run's VM ends with its CLI
# (#1193). Older releases still have both.
FIXED_IN="1.20.2"
at_least() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]; }

# x86_64 guests through v1.22.2 have eleven IRQs (libkrun IRQ_BASE 5 to
# IRQ_MAX 15): four -v mounts boot and five fail with "no more IRQs are
# available". Any -p, --allow-host or --allow-cidr adds one virtio-net device,
# however many ports. Measured on Windows Hypervisor Platform. v1.23.0 ships
# libkrun with IRQ_MAX 23 (#1521) and its ceiling was not measured, so the check
# applies to x86_64 through v1.22.2 only. arm64 guests have 128 IRQs.
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
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; isolation is exactly where a silently changed flag matters, so check each step's output against the binary before trusting it"
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
        # no network. Before v1.20.2 that combination never boots on macOS.
        if [ -n "${version:-}" ] && [ "$version" != "unknown" ] && at_least "$version" "$FIXED_IN"; then
            emit offline_shape available
        else
            emit offline_shape unavailable
            emit offline_shape_blocker "smol-machines/smolvm#1192, fixed in v$FIXED_IN"
            blocked=1
            note "before v$FIXED_IN, on macOS --oci-cache with any -v mount times out the boot, deterministically, so the offline shape this packet is built on cannot run here. Upgrade, or use references/macos.md, which gives a route that works on older releases and says what it costs you."
            for b in docker crane podman nerdctl; do
                if command -v "$b" >/dev/null 2>&1; then emit image_archive_tool "$b"; break; fi
            done
        fi
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
        note "this script covers macOS and Linux. On Windows the --oci-cache bake did not complete on v1.22.2, so the offline shape is unavailable there too; see references/windows.md."
        ;;
esac

# The devices your planned run needs, against the budget. Any number of ports
# shares one network device.
net_devices=0
[ "$ports" -gt 0 ] && net_devices=1
emit planned_mounts "$mounts"
emit planned_ports "$ports"
emit devices_requested "$((mounts + net_devices))"
if [ "$arch" = "x86_64" ] && [ -n "${version:-}" ] && [ "$version" != "unknown" ] && ! at_least "$version" "1.22.3"; then
    emit device_budget "$DEVICE_BUDGET"
    if [ "$((mounts + net_devices))" -le "$DEVICE_BUDGET" ]; then
        emit device_budget_ok yes
    else
        emit device_budget_ok no
        blocked=1
        note "on x86_64 through v1.22.2 more than four devices beyond the base set fail with 'no more IRQs are available'; a published port or an --allow-host grant is one. Combine directories under one mount."
    fi
else
    emit device_budget_ok not_limiting
fi

# Ctrl-C does not stop a run started by run.sh on any release: it backgrounds
# the CLI, and a background command in a script ignores SIGINT. Before v1.20.2
# an interrupted CLI also leaves a cached run's VM behind. Say so before
# anything is started, not after.
emit cancel_route "scripts/cleanup.sh --cancel"
if [ -n "${version:-}" ] && [ "$version" != "unknown" ] && at_least "$version" "$FIXED_IN"; then
    emit interrupt_orphans_vm wrapper_only
else
    emit interrupt_orphans_vm yes
    emit interrupt_blocker "smol-machines/smolvm#1193, fixed in v$FIXED_IN"
fi

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/bake.sh`

```bash
#!/usr/bin/env bash
# Bake an image into the host cache. This is the only step in which a machine
# has a network, and it runs with nothing untrusted mounted.
#
# usage: bake.sh [<image>]      (default python:3.12-alpine)
#
# Do this before the untrusted code is anywhere near the machine. Afterwards the
# runs' machines need no network at all, which is materially stronger isolation
# than granting egress and hoping the workload behaves. The host CLI still asks
# the registry for the image's manifest on every run.

set -uo pipefail

IMAGE="${1:-python:3.12-alpine}"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

# Before v1.20.2, on macOS --oci-cache plus any -v mount never boots (#1192,
# fixed by #1467), so a bake buys nothing there. v1.20.2 and later bake here.
version="$("$SMOLVM" --version 2>/dev/null | awk '{print $NF}')"
fixed="$(printf '%s\n%s\n' "${version:-0}" 1.20.2 | sort -V | head -1)"
if [ "$(uname -s)" = "Darwin" ] && [ "$fixed" != "1.20.2" ]; then
    printf 'result=unsupported_on_macos\n'
    printf 'A baked image is only useful to a run that also mounts something, and on macOS\n'
    printf '%s\n' '--oci-cache plus any -v mount times out the boot (smol-machines/smolvm#1192).'
    printf 'Fixed in v1.20.2; this binary is %s. Upgrade, or read references/macos.md.\n' "${version:-unknown}"
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
        printf '  the memory it takes. From v1.23.0 a persistent machine created with no network\n'
        printf '  boots the image with no bake (README.md, "The network is off unless you ask\n'
        printf '  for it"). Otherwise use the network-on route (scripts/run.sh --route\n'
        printf '  network-on), and read references/macos.md, which explains what that route\n'
        printf '  costs you. It is the same trade on any host that cannot bake.\n'
    else
        printf '  control_boot_2048=failed\n'
        printf '  Nothing boots here at all. This is not a bake problem: run the install\n'
        printf '  packet preflight, which checks KVM access and the macOS socket path length.\n'
    fi
else
    printf 'The bake is the only step with a networked machine. If it failed on the registry,\n'
    printf 'fix that here rather than adding --net to the workload run, which is what the CLI\n'
    printf 'hint suggests and is the opposite of what an isolated run wants.\n'
fi
exit 1
```

### `scripts/run.sh`

```bash
#!/usr/bin/env bash
# Run an untrusted command against a repo it must not modify, with no network,
# and collect its artifacts.
#
# usage: run.sh [--repo <dir>] [--repo-path <path>] [--out <dir>] [--image <img>]
#               [--allow-host <h>]... -- <command...>
#   --repo <dir>        mounted read-only at --repo-path (default ./repo)
#   --repo-path <path>  where the repo appears in the guest (default /workspace)
#   --out  <dir>        mounted writable at /out        (default ./out)
#   --image <img>       must already be baked; see bake.sh (default python:3.12-alpine)
#   --allow-host <h>    grant egress to one host. Repeatable. Weakens the isolation
#                       and the script says so; --allow-host implies --net.
#   --route <r>         offline (default) or network-on.
#                       offline    bake once, then run with no network at all.
#                       network-on no --oci-cache, the run pulls its own image and
#                       therefore has egress for the whole run. Use it only where
#                       offline does not work: macOS before v1.20.2, where
#                       --oci-cache with any mount never boots
#                       (smol-machines/smolvm#1192), and any host that cannot give
#                       the bake helper its 8192 MiB.
#
# The VM's pid is recorded before the workload finishes, because Ctrl-C on this
# script does not stop the machine. The CLI runs in the background below, and a
# background command in a script ignores SIGINT, so the CLI and its VM keep
# running. Before v1.20.2 an interrupted CLI also leaves a cached run's VM
# behind, invisible to `machine list` (smol-machines/smolvm#1193). Cancel with
# `scripts/cleanup.sh --cancel`, never with Ctrl-C. Image seeding is off for the
# run, so the first VM process is the workload's.

set -uo pipefail

REPO="./repo"
REPO_PATH="/workspace"
OUT="./out"
IMAGE="python:3.12-alpine"
ROUTE="offline"
allow=()

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO="$2"; shift ;;
        --repo-path)  REPO_PATH="$2"; shift ;;
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
    printf 'no command given; everything after -- is run inside the machine\n' >&2
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
PIDFILE="$STATE_DIR/throwaway-machine.vmpids"

# With SMOLVM_DATA_DIR set, smolvm runs with HOME there on Linux, so its cache
# is under .cache in it.
case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            VMS_DIR="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"
if [ -n "${SMOLVM:-}" ]; then
    case "$(readlink "$SMOLVM" 2>/dev/null || printf '%s' "$SMOLVM")" in
        "$SMOLVM_PREFIX"/*) ;;
        *) printf 'note=%s is not under %s, so the process scan cannot see its forked VMs (all of its VMs on macOS); set SMOLVM_PREFIX to its directory\n' "$SMOLVM" "$SMOLVM_PREFIX" ;;
    esac
fi

# List this HOME's VM processes as "pid marker". The plain run path execs a
# `_boot-vm` child that carries its boot config; the pack-run path forks one that
# carries none. Linux names both `libkrun VM`, or `VM:<hostname>` when HOSTNAME
# is exported; on macOS the executable path and the parent chain scope the
# search. The teardown packet's traps have the why.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                case "$(cat "$p/comm" 2>/dev/null)" in "libkrun VM"|VM:*) ;; *) continue ;; esac
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep -f would match this script.
            procs="$(ps -axo pid=,ppid=,command= 2>/dev/null)"
            printf '%s\n' "$procs" | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # An orphan counts only if it is a run; a fork has its parent's command line.
                if [ "$ppid" = 1 ]; then
                    case "$rest" in
                        *" machine run "*|*" vm run "*|*" pack run "*)
                            printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                    esac
                else
                    parent="$(printf '%s\n' "$procs" | while read -r q qp qrest; do [ "$q" = "$ppid" ] && { printf '%s' "$qrest"; break; }; done)"
                    [ "$parent" = "$rest" ] && printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX"
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
    printf 'note=this is the weaker isolation. The offline route gives the workload no network at all; this one is open for as long as the workload runs.\n'
elif [ "${#allow[@]}" -gt 0 ]; then
    printf 'egress=granted %s\n' "${allow[*]}"
    printf 'note=--allow-host implies --net. The workload can now reach the named hosts, and a denial looks like a DNS failure rather than a policy denial.\n'
else
    printf 'egress=none\n'
fi

logfile="$STATE_DIR/throwaway-machine.lastrun.log"
SMOLVM_IMAGE_SEEDS=0 "$SMOLVM" machine run --mem 2048 ${cache[@]+"${cache[@]}"} --image "$IMAGE" \
    --volume "$REPO:$REPO_PATH:ro" \
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
# Keep only recorded pids that are still VM processes, so --cancel never reaches a recycled one.
if [ -s "$PIDFILE" ]; then
    while read -r pid cfg; do
        [ -n "$pid" ] && grep -qx -- "$pid" <<<"$before" && printf '%s %s\n' "$pid" "$cfg"
    done < "$PIDFILE" > "$PIDFILE.tmp"
    mv "$PIDFILE.tmp" "$PIDFILE"
fi
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
# and that this run's machine pulled nothing. Without it the guest pulled, which
# means it had network, which means it was not the isolation you asked for.
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
printf 'next: scripts/verify.sh, then scripts/cleanup.sh --purge\n'
exit "$rc"
```

### `scripts/verify.sh`

```bash
#!/usr/bin/env bash
# Assert the isolation held: from inside the guest, and from the host afterwards.
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
        touch /workspace/ISOLATION_PROBE 2>/dev/null && echo "workspace=WRITABLE" || echo "workspace=readonly"
        touch /out/ISOLATION_PROBE      2>/dev/null && echo "out=writable"       || echo "out=READONLY"
        if ! command -v wget >/dev/null 2>&1; then echo "net=no_probe_tool"
        elif wget -q -T3 -O- http://example.com >/dev/null 2>&1; then echo "net=REACHED"
        else echo "net=blocked"; fi
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
if [ -e "$REPO/ISOLATION_PROBE" ]; then
    printf 'repo_unchanged=FAIL the read-only mount leaked: %s/ISOLATION_PROBE exists\n' "$REPO"
    fail=1
else
    printf 'repo_unchanged=ok\n'
fi
rm -f "$OUT/ISOLATION_PROBE"

if [ "$fail" -eq 0 ]; then printf 'result=isolation_held\n'; else printf 'result=FAILED\n'; fi
exit "$fail"
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Cancel or clean up a run, then prove nothing is left running.
#
# usage: cleanup.sh [--cancel] [--purge]
#   --cancel   kill the VMs run.sh recorded. THIS IS THE PACKET'S CANCEL.
#              Ctrl-C on run.sh is not: it returns the shell to you and leaves
#              the CLI and its VM running until the untrusted workload finishes
#              on its own. Before v1.20.2 Ctrl-C on the CLI itself leaves a
#              cached run's VM running too, invisible to `machine list`
#              (smol-machines/smolvm#1193).
#   --purge    remove the recorded-pid file once nothing is left
#
# With no flags it waits, asserts the machine list is empty, and reports any VM
# process still alive under this HOME's state.

set -uo pipefail

PACKET="throwaway-machine"

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

# With SMOLVM_DATA_DIR set, smolvm runs with HOME there on Linux, so its cache
# is under .cache in it.
case "$(uname -s)" in
    Darwin) VMS_DIR="$HOME/Library/Caches/smolvm/vms" ;;
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            VMS_DIR="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm/vms" ;;
esac
VMS_DIR="${SMOLVM_VMS_DIR:-$VMS_DIR}"
SMOLVM_PREFIX="${SMOLVM_PREFIX:-$HOME/.smolvm}"
if [ -n "${SMOLVM:-}" ]; then
    case "$(readlink "$SMOLVM" 2>/dev/null || printf '%s' "$SMOLVM")" in
        "$SMOLVM_PREFIX"/*) ;;
        *) printf 'note=%s is not under %s, so the process scan cannot see its forked VMs (all of its VMs on macOS); set SMOLVM_PREFIX to its directory\n' "$SMOLVM" "$SMOLVM_PREFIX" ;;
    esac
fi

# List this HOME's VM processes as "pid marker". The plain run path execs a
# `_boot-vm` child that carries its boot config; the pack-run path forks one that
# carries none. Linux names both `libkrun VM`, or `VM:<hostname>` when HOSTNAME
# is exported; on macOS the executable path and the parent chain scope the
# search. The teardown packet's traps have the why.
list_vm_processes() {
    case "$(uname -s)" in
        Linux)
            for p in /proc/[0-9]*; do
                case "$(cat "$p/comm" 2>/dev/null)" in "libkrun VM"|VM:*) ;; *) continue ;; esac
                pid="${p#/proc/}"
                cfg="$(tr '\0' '\n' < "$p/cmdline" 2>/dev/null | sed -n '3p')"
                case "$cfg" in
                    "$VMS_DIR"/*) printf '%s %s\n' "$pid" "$cfg"; continue ;;
                esac
                case "$(readlink "$p/exe" 2>/dev/null)" in
                    "$SMOLVM_PREFIX"/*) printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                esac
            done
            ;;
        Darwin)
            # shellcheck disable=SC2009  # pgrep -f would match this script.
            procs="$(ps -axo pid=,ppid=,command= 2>/dev/null)"
            printf '%s\n' "$procs" | while read -r pid ppid rest; do
                case "$rest" in "$SMOLVM_PREFIX"/smolvm-bin*) ;; *) continue ;; esac
                case "$rest" in
                    *" _boot-vm "*) printf '%s %s\n' "$pid" "${rest#* _boot-vm }"; continue ;;
                esac
                # An orphan counts only if it is a run; a fork has its parent's command line.
                if [ "$ppid" = 1 ]; then
                    case "$rest" in
                        *" machine run "*|*" vm run "*|*" pack run "*)
                            printf '%s orphaned-under %s\n' "$pid" "$SMOLVM_PREFIX" ;;
                    esac
                else
                    parent="$(printf '%s\n' "$procs" | while read -r q qp qrest; do [ "$q" = "$ppid" ] && { printf '%s' "$qrest"; break; }; done)"
                    [ "$parent" = "$rest" ] && printf '%s forked-under %s\n' "$pid" "$SMOLVM_PREFIX"
                fi
            done
            ;;
    esac
}

# 1. Cancel: kill exactly the VMs run.sh recorded, and only those.
if [ "$cancel" -eq 1 ]; then
    if [ -s "$PIDFILE" ]; then
        # A recorded pid is killed only while it is still a VM process.
        live=" $(list_vm_processes | awk '{print $1}' | tr '\n' ' ') "
        while read -r pid cfg; do
            [ -n "$pid" ] || continue
            case "$live" in
                *" $pid "*) kill -9 "$pid" 2>/dev/null && printf 'cancelled=%s config=%s\n' "$pid" "$cfg" ;;
                *) printf 'already_gone=%s\n' "$pid" ;;
            esac
        done < "$PIDFILE"
    else
        printf 'cancelled=none_recorded\n'
    fi
fi

# 2. An ephemeral machine's entry retires after the run returns, not with it, so
# an immediate assertion fails on a healthy host. This is the single most likely
# false failure in a scripted run.
printf 'waiting=up to 20s for ephemeral entries to retire before asserting\n'
waited=0
listing="$("$SMOLVM" machine list 2>&1)"
while ! grep -q 'No machines found' <<<"$listing" && [ "$waited" -lt 20 ]; do
    sleep 1; waited=$((waited + 1))
    listing="$("$SMOLVM" machine list 2>&1)"
done
printf 'waited=%ss\n' "$waited"

# 3. Assert values.
if grep -q 'No machines found' <<<"$listing"; then
    printf 'machines=clean\n'
else
    printf 'machines=remaining\n'
    printf '%s\n' "$listing" | sed 's/^/  /'
    printf 'note=this packet did not create these, so it will not delete them. By name:\n'
    printf '  smolvm machine stop --name <NAME> && smolvm machine delete --name <NAME> --force\n'
    printf '  add --cascade for a machine that was branched from another\n'
fi

# `_shared` is the Linux shared pack store, written by machine create --from and
# checkpoint restores. It is cache, not residue, so counting it as a leak gives
# a false positive.
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
# offline route. Report both places it can live: `init-layers` beside the VM
# state, and the pack cache, which is where a v1.14.2 bake landed on macOS.
case "$(uname -s)" in
    Darwin) PACK_CACHE="$HOME/Library/Caches/smolvm-pack" ;;
    *)      cache_root="${SMOLVM_DATA_DIR:+$SMOLVM_DATA_DIR/.cache}"
            PACK_CACHE="${cache_root:-${XDG_CACHE_HOME:-$HOME/.cache}}/smolvm-pack" ;;
esac
INIT_LAYERS="$(dirname "$VMS_DIR")/init-layers"
if [ -d "$INIT_LAYERS" ]; then
    printf 'image_cache_init_layers=%s\n' "$(du -sk "$INIT_LAYERS" 2>/dev/null | awk '{printf "%dMB", $1/1024}')"
else
    printf 'image_cache_init_layers=absent\n'
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

## Throwaway machine traps

### Ctrl-C does not stop the machine, and which release and route that applies to

**On v1.20.2, interrupting the CLI ends the VM; interrupting `run.sh` does not.** Measured
2026-09-29 on macOS 27.0.1 arm64 and Ubuntu 24.04 aarch64, a `sleep 600` workload, watching the VM
pid itself:

| what was interrupted | macOS arm64 | Linux aarch64 |
|---|---|---|
| the CLI, Ctrl-C, offline or network-on | VM gone within 1 s | VM gone within 1 s |
| the CLI, `SIGKILL`, offline or network-on | VM gone within 1 s | VM gone within 1 s |
| `run.sh`'s process group, Ctrl-C, offline | CLI and VM keep running | CLI and VM keep running |
| `run.sh`'s process group, Ctrl-C, network-on | VM gone | VM keeps running |
| `run.sh` alone, `SIGTERM`, either route | CLI and VM keep running | CLI and VM keep running |

`cleanup.sh --cancel --purge` cleared every survivor with `result=clean`. The wrapper rows are
`run.sh`'s own doing: it starts the CLI with `&`, and a non-interactive shell starts a background
command with `SIGINT` ignored. On macOS the same cached run backgrounded by `bash -c '... & wait'`
kept its CLI and VM after `SIGINT`, and with `SIGINT` reset to the default before the exec both were
gone.

**Before v1.20.2, on the offline route the CLI itself is no better, and this is the reason the
packet has a cancel script.**
`machine run` with `--oci-cache` or `--init` takes the pack-run boot path, which on Unix forks a
session leader that never execs, so the VM child is detached with no parent-death arming. Interrupt
the CLI and the VM keeps running, `machine list` reports `No machines found`, no VM cache directory
exists, and there is no CLI route to what is still running. It exits only when the untrusted
workload does, which for code that hangs or loops is unbounded. This is
[smol-machines/smolvm#1193](https://github.com/smol-machines/smolvm/issues/1193), fixed in v1.20.2
by #1467: the forked child now exits when its CLI does.

**On the plain path it does not happen**, and that is worth knowing rather than assuming the worst
everywhere. Measured on Ubuntu 24.04 aarch64 on 2026-09-08: a `machine run` with no `--oci-cache`,
one mount and a `sleep 600` workload, sent `SIGINT` on the CLI itself, left `machine list` empty
and **no VM process at all**. The plain path spawns an exec'd `_boot-vm` that dies with the CLI.

So, before v1.20.2:

| route | Ctrl-C on the CLI | cancel with |
|---|---|---|
| offline (`--oci-cache`) | VM survives, invisible to `machine list` | `scripts/cleanup.sh --cancel` |
| network-on (no `--oci-cache`) | VM dies with the CLI (verified on Linux) | either |

On v1.18.2 the network-on route was measured again with the **wrapper** killed and the CLI left
alone: the run stayed in `machine list` as `running (eph)` on macOS arm64 and on Linux aarch64, and
`scripts/cleanup.sh --cancel` killed the recorded pid on both.

**Do not rely on an interrupt to cancel a run.** `run.sh` records the VM's pid on both routes
because the difference is a boot-path detail that has changed between releases, and because
interrupting the *wrapper* rather than the CLI leaves the CLI and its VM running, on v1.20.2 as
before.

### Assert no machines left only after a wait

A successful `machine run` returns **before** its ephemeral entry retires. Asserting an empty
machine list immediately fails on a healthy host, and it is the single most likely false failure in
a scripted run. `scripts/cleanup.sh` waits before asserting.

### A network-off run that dies on the manifest means the bake was skipped

```
Error: fetching manifest docker.io/library/python:3.12-alpine: ... network is unreachable
Hint: networking is disabled. Add --net to enable image pulls
```

**An ordinary earlier pull does not make a later run offline-capable**: the runtime still resolves
the tag through the registry. Bake the image with `scripts/bake.sh` instead.

The CLI's own hint points at re-opening the network, which is the opposite of what an isolated run wants.
Adding `--net` here is how an offline run quietly becomes a networked one.

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
the resolver are both `.1`. `--allow-host` and `--allow-cidr` select virtio-net, so every run
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

**What works.** On Linux both shapes rename themselves to `libkrun VM`, or to `VM:<hostname>` when
`HOSTNAME` is exported, which no shell can hold, so `scripts/cleanup.sh` matches either in
`/proc/<pid>/comm` and then scopes by argv[2] when it is there and by the executable's path when it
is not. macOS exposes no rename, so there the search is scoped by
the executable path under this `HOME` and the parent chain separates a VM from the CLI that
started it. Verified against a live orphan on both hosts: the same sequence now reports
`vm_process=... forked-under ...` and `result=vms_still_running`, and `--cancel` clears it.

On v1.20.2 a forked VM exits with its CLI, so an orphan of that shape comes from an older release
or from a CLI that is still running, as after an interrupted `run.sh`. The scan still catches it,
observed 2026-09-29 on both hosts. On macOS it also lists that CLI, reparented to launchd, as
`orphaned-under`; `--cancel` kills only the recorded VM, and the CLI then exits with it.

### What is cache and what is residue

`ls ~/.cache/smolvm/vms/ | wc -l` is not a leak check. A bake fills two separate caches and
neither is residue:

- `init-layers/`, beside `vms/` in the smolvm cache, where a bake writes its layers.
- **the pack cache**, `~/Library/Caches/smolvm-pack` on macOS and `~/.cache/smolvm-pack` on Linux,
  where a cached run extracts them. On v1.14.2 on macOS a bake of one alpine image landed **here**:
  114 MB in the pack cache, `vms/_shared` absent. Observed 2026-09-08.

`scripts/cleanup.sh` reports both and keeps both. Deleting them costs you the offline route, and
the next bake pays for it again. `vms/_shared` is a third store, the shared pack store (Linux,
after `machine create --from` or a checkpoint restore); it is cache too, and the leak count
excludes it.

Leftover VM directories are also not necessarily a leak: `smolvm serve start` prints
`Reclaimed N dangling VM data dir(es)` on startup and clears them.

### There is no way to list what has been baked

`smolvm machine images` requires `--name` and reports one machine's images, so cache state is not
observable. If a run unexpectedly pulls, you cannot inspect the cache to find out why. The
`used_host_cache` line from `scripts/run.sh` is the only signal you get, which is why it is asserted
rather than printed.

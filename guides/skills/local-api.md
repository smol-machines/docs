---
title: "Local API: drive smolvm over HTTP"
---

# Local API: drive smolvm over HTTP

Drives smolvm programmatically over its local HTTP API (smolvm serve) instead of the CLI: create machines, exec and stream commands, move files in and out, and tear them down. Use when building a client, harness, agent tool or MCP backend over smolvm; when a create call is accepted but the machine behaves as if a field was ignored; when a file uploaded over the API has disappeared; when an exec that failed still returned HTTP 200; or when choosing between the Unix socket and loopback TCP. Do not use it as a substitute for the CLI in a shell script, and do not bind the listener beyond loopback: the API has no authentication of any kind.

Verified on **smolvm v1.16.1** on macOS arm64, 2026-09-15, and on **v1.14.6** on Linux aarch64,
2026-09-10. Done means a machine went through
its whole lifecycle over HTTP and `GET /api/v1/machines` is empty again at the end.

Two rules run through everything here, and both are the same shape: **a 200 is not a result.**

1. **A failing guest command still returns HTTP 200.** Assert `exitCode` from the body.
2. **Upload files only after the workload container is running.** An upload before that returns
   200 with the resolved path and byte count for a file that is then unreadable.

## Procedure

**1. Preflight.**

```bash
scripts/preflight.sh
```

It reports `auth=none`, which is not a warning about your setup: the API has no TLS, token or auth
flag of any kind, so **the transport you pick is the access control**.

**2. Start the server.** A Unix socket is the default here, as it is smolvm's.

```bash
scripts/serve-start.sh
scripts/serve-start.sh --listen 127.0.0.1:8899
```

It waits for `"status":"ok"` from `/health` rather than for the process to exist, records the
listen address and pid for cleanup, and reports any `Reclaimed N dangling VM data dir(es)` line so
you do not later read those directories as a leak.

**3. Export the spec before writing a request body.** This is the step that saves the most time.

```bash
smolvm serve openapi -o ./openapi.json
```

The field names are the schema's, not the CLI's flags. `network` not `net`, `memoryMb` not
`memory`, and `cmd` for the workload you would pass after `--`. Unknown fields are accepted with
200 and ignored. `references/api-fields.md` has the full list and what each wrong name costs.

**4. Run the lifecycle.**

```bash
scripts/lifecycle-check.sh
```

Create, start, wait for the workload container to answer with a value, exec, exec a deliberately
failing command and assert its non-zero `exitCode` came back on a 200, stream, round-trip a file,
stop, delete, and assert the machine list is empty:

```
created_state=ok (created)
started_state=ok (running)
workload_ready_after_s=0
workload_ready=ok (yes)
exec_exit_code=ok (0)
exec_stdout=ok
failing_exec_exit_code=ok (3)
stream_lines=ok (3)
stream_exit_event=ok
file_roundtrip=ok (PAYLOAD123)
machines_empty=ok ({"machines":[]})
result=lifecycle_ok
```

**5. Clean up, machines first.**

```bash
scripts/cleanup.sh --purge
```

Order matters: **stopping the server does not stop machines**, it orphans them. The script deletes
recorded machines, then stops the server, then removes the socket.

## The calls, in short

```bash
B=http://127.0.0.1:8899   # or: curl --unix-socket "$SOCK" http://localhost/...

curl $B/health
curl -X POST $B/api/v1/machines -H 'content-type: application/json' \
  -d '{"name":"m","image":"python:3.12-alpine","network":true,"memoryMb":2048,
       "cmd":["sh","-c","while true; do sleep 3600; done"]}'
curl -X POST $B/api/v1/machines/m/start -H 'content-type: application/json' -d '{}'
curl -X POST $B/api/v1/machines/m/exec  -H 'content-type: application/json' \
  -d '{"command":["sh","-c","echo hi"]}'
curl -N -X POST $B/api/v1/machines/m/exec/stream -H 'content-type: application/json' \
  -d '{"command":["sh","-c","for i in 1 2 3; do echo line$i; sleep 1; done"]}'
curl -X PUT "$B/api/v1/machines/m/files/%2Ftmp%2Fabs.txt" --data-binary 'PAYLOAD'
curl        "$B/api/v1/machines/m/files/%2Ftmp%2Fabs.txt"
curl -X POST   $B/api/v1/machines/m/stop -H 'content-type: application/json' -d '{}'
curl -X DELETE $B/api/v1/machines/m
```

Paths in the `files` route are **absolute and URL-encoded**. `exec` returns stdout as text and as
base64; `exec/stream` emits one `event: stdout` per line then a terminal `event: exit`.

## Traps

Full detail in `references/traps.md` and `references/api-fields.md`.

- **Upload after the container is up, never before.** Reproduced on Linux aarch64 on v1.14.6: the
  PUT returned `200 {"path":"/tmp/r1.txt","size":6}` and the file was never readable, first with
  `failed to canonicalize target`, then with `failed to read /tmp/r1.txt in the workload
  container`. Both directions pick a namespace per request, and `/tmp` is a path the container
  mounts over. The same sequence on macOS returned the payload.
  **Re-run on v1.16.1 on 2026-09-15 and it did not reproduce on either host**: a machine created
  without a `cmd`, started, then written to immediately, read `ROUND1` back at once on macOS arm64
  and on Lima aarch64, and again at 20 s on Linux. The rule still costs nothing and the failure was
  silent when it happened, so keep ordering the upload after a successful `exec`.
- **A failing guest command is HTTP 200.**
- **Unknown create fields are accepted and ignored**, while a Smolfile rejects them. A `net` for
  `network` was caught at create here with a clear 400 about the missing network, but a `memory`
  for `memoryMb` gets no diagnostic at all: you silently get the default.
- **Killing the server orphans machines.**
- **The spec's `info.version` is not the binary's.** It says `0.5.2` on v1.14.2 while `/health`
  says `1.14.2`. Take the version from `/health`.
- **The default listen path differs per platform, and `--help` shows only one of them.** The help
  prints `[default: unix:///tmp/smolvm.sock]`, and its own example line says
  `unix:///$XDG_RUNTIME_DIR/smolvm.sock`. Observed on v1.16.1: the socket appeared at
  `/tmp/smolvm.sock` on macOS arm64 and at `/run/user/501/smolvm.sock` on Lima aarch64. Read the
  path the server reports rather than assuming either.

## Security defaults, and why they are the defaults

- **The Unix socket is the default because it is the only access control there is.** `serve start`
  has no TLS, certificate, token or auth flag, and the routes it exposes create machines, exec
  arbitrary commands and read and write files. The socket's file permissions are a real boundary;
  a loopback port is a boundary only in the sense that every process on the host is inside it.
- **Loopback TCP is for when you need a URL**, in a container network namespace or for a client
  that cannot do Unix sockets. Treat the port as equivalent to a shell on the host, and do not
  bind anything but `127.0.0.1`.
- **`scripts/serve-start.sh` puts its socket under the packet's own state directory**, not in a
  world-traversable temporary directory, and removes it at cleanup.
- **Machines are deleted before the server is stopped**, because a server shutdown leaves running
  VMs with nothing managing them and no route back to them from the CLI.

## Platform arms

- **macOS arm64** and **Linux aarch64**: the scripts were run here, over the Unix socket.
- **Linux x86_64**: verified in the material behind this packet, over both transports, not re-run
  here.
- **Windows x86_64**: `references/windows.md`, **re-run on 2026-09-11 against v1.14.6** on
  Windows 11 Home build 10.0.26200.0 UBR 9445, where the whole lifecycle passed over loopback TCP.
  No Unix socket form has ever been attempted there, **400 and 404 still return empty bodies**, and
  two shapes fail before reaching a machine: routes live under `/api/v1/`, and a bodiless POST to
  `start` or `stop` needs `application/json` with an empty JSON body.

## Eval prompts, and what they produced

Run on 2026-09-07 PT against v1.14.2 from the published release, under an isolated `HOME`. Output
is verbatim.

**1. "Write me something that drives a smolvm machine over HTTP end to end and proves it worked."**

`scripts/lifecycle-check.sh`, over a Unix socket. All eleven checks passed on macOS 26.6.2 arm64
and on Lima `linux-kvm` (Ubuntu 24.04 aarch64), the Linux one twice in a row. Output as shown in
step 4 above, including `failing_exec_exit_code=ok (3)`, which is the assertion that catches a
guest failure hiding behind a 200.

**2. "I uploaded a file right after starting the machine and now the API says it does not
exist."**

Reproduced on Linux aarch64 by doing exactly that:

```
PUT: {"path":"/tmp/r1.txt","size":6}
GET now: {"error":"agent operation failed: read file: failed to canonicalize target
          /tmp/r1.txt: No such file or directory (os error 2)","code":"INTERNAL_ERROR"}
GET after 30s: {"error":"agent operation failed: read file: failed to read /tmp/r1.txt in
          the workload container: open /tmp/r1.txt: No such file or directory (os error 2)",
          "code":"INTERNAL_ERROR"}
```

The upload reported success for a file that was never readable. The same sequence on macOS arm64
returned `ROUND1` both immediately and after 30 s, so a run that works proves nothing.

**3. "My create call returned 200 but the machine has the wrong settings."**

Verified on both hosts: a body carrying an unknown field is accepted and the field is dropped.

```
POST {"name":"...","image":"alpine","network":true,"memoryMb":2048,"bogusField":1}
-> 200 {"name":"...","state":"created","network":true,"memoryMb":2048,...}
```

and the runbook's `net`/`memory` shape was caught at create on both hosts, with a message that
names the remedy:

```
400 {"error":"config operation failed: create machine: image 'alpine' must be pulled from a
registry, but this machine has no network, so the pull can never succeed. Add --net ...",
"code":"BAD_REQUEST"}
```

A 404 on either host returns `{"error":"machine 'nope-does-not-exist' not found",
"code":"NOT_FOUND"}`, which is the diagnostic Windows does not give you.

## Re-verified on v1.14.6

Run 2026-09-10 PT against v1.14.6 on macOS 26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04
aarch64), over the Unix socket. **All eleven checks green on both**, including
`failing_exec_exit_code=ok (3)`, the case that proves a guest failure arrives on an HTTP 200.

## What was not run

- **The Unix socket form on Windows.** The 2026-09-11 v1.14.6 re-run there used loopback TCP, as
  every Windows run has.
- **Linux x86_64.**
- **Loopback TCP.** `serve-start.sh` accepts `--listen 127.0.0.1:8899` and the code path is the
  same, but every run here used the Unix socket.
- **Authenticated or TLS deployment.** There is no such thing to test: `serve start` has no flags
  for it.
- **The pool and rollout-executor routes** in the spec. They belong to the branch-pool feature.

## Related packets

- `install` for the boot this assumes, `teardown` for the cleanup script.
- `dev-env` for the same lifecycle through the CLI, and for the workload-container behaviour that
  the `cmd` field addresses here.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can run the local HTTP API. Read-only: starts no VM,
# starts no server, writes no smolvm state.
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.14.6"

emit() { printf '%s=%s\n' "$1" "$2"; }

blocked=0
note() { printf 'note=%s\n' "$1"; }

# --- the binary --------------------------------------------------------------

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    emit smolvm_installed no
    emit smolvm_version ""
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
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version; flags and messages move every release, so check the output against the binary before trusting a step here"
        else
            emit version_status older
            note "this packet was verified on $VERIFIED_VERSION and the binary is $version"
        fi
    fi
else
    emit version_status unknown
fi

# --- platform ----------------------------------------------------------------

kernel="$(uname -s)"
arch="$(uname -m)"
case "$arch" in aarch64|arm64) arch=aarch64 ;; esac

case "$kernel" in
    Darwin)
        emit platform "darwin-$arch"
        emit accel hvf
        emit macos_version "$(sw_vers -productVersion)"
        hv="$(sysctl -n kern.hv_support 2>/dev/null)"
        if [ "$hv" = "1" ]; then emit accel_access ok; else emit accel_access denied; blocked=1; fi
        if [ "$arch" != "aarch64" ]; then
            emit hardware_verified no
            note "Intel Mac is not verified by this packet; the installer accepts it and nothing here was run on one"
        else
            emit hardware_verified yes
        fi
        # A VM's agent socket lives under the cache directory. macOS sockaddr_un
        # holds 104 bytes including the terminator.
        sock="$HOME/Library/Caches/smolvm/vms/0123456789abcdef/agent.sock"
        len=${#sock}
        emit socket_path_bytes "$len"
        if [ "$len" -gt 100 ]; then
            emit socket_path_status too_long
            blocked=1
            note "HOME is too deep: every VM start will fail with krun_start_enter -22, whose text blames disks and device options. Install under a shorter HOME."
        else
            emit socket_path_status ok
        fi
        emit unsupported "vulkan,cuda"
        emit unix_socket_transport yes
        ;;
    Linux)
        emit platform "linux-$arch"
        emit accel kvm
        emit socket_path_status n_a
        if [ ! -e /dev/kvm ]; then
            emit accel_access missing
            blocked=1
            note "/dev/kvm does not exist; this host has no KVM"
        elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            emit accel_access ok
        else
            emit accel_access denied
            blocked=1
            note "your user cannot open /dev/kvm. The installer warns and continues, so a successful install says nothing about whether a VM will start. Fix: sudo usermod -aG kvm \$USER, then run the next command through sg kvm -c '...' rather than logging out."
        fi
        emit unsupported "vulkan"
        emit unix_socket_transport yes
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        emit unix_socket_transport no
        note "this script covers macOS and Linux. On Windows the API works over loopback TCP only, and no unix:// listen form was ever attempted. See references/windows.md, written from a run and not re-run by this packet."
        ;;
esac

# The API has no TLS, token or auth flag of any kind. Anyone who can reach the
# listener can create machines, exec in them and read their files, so which
# transport you choose IS the access control.
emit auth none
if command -v curl >/dev/null 2>&1; then emit curl present; else emit curl absent; blocked=1; fi
if command -v python3 >/dev/null 2>&1; then emit python3 present; else emit python3 absent; blocked=1; fi

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/serve-start.sh`

```bash
#!/usr/bin/env bash
# Start the local HTTP API and wait until it answers, then print how to reach it.
#
# usage: serve-start.sh [--listen <addr>]
#   default: a Unix socket under this packet's state directory.
#
# A Unix socket is the default here for the same reason it is smolvm's: the API
# has no authentication of any kind, so the socket's file permissions are the
# only boundary there is. Over loopback TCP the boundary is the whole machine.

set -uo pipefail

STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
mkdir -p "$STATE_DIR"

LISTEN="unix://$STATE_DIR/local-api.sock"
if [ "${1:-}" = "--listen" ]; then LISTEN="$2"; fi

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
if [ -z "$SMOLVM" ]; then
    printf 'smolvm not found; set SMOLVM to its path\n' >&2
    exit 2
fi

case "$LISTEN" in
    unix://*)
        SOCK="${LISTEN#unix://}"
        rm -f "$SOCK"
        CURLOPTS=(-s --unix-socket "$SOCK")
        BASE="http://localhost"
        ;;
    *)
        CURLOPTS=(-s)
        BASE="http://$LISTEN"
        ;;
esac

"$SMOLVM" serve start --listen "$LISTEN" > "$STATE_DIR/local-api.log" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$STATE_DIR/local-api.pid"
printf '%s\n' "$LISTEN" > "$STATE_DIR/local-api.listen"

# Assert a value from /health, not that the process is alive: the server writes
# its listening line before it can answer, and a dead server leaves a stale pid.
# 60 s: the server answered /health in 1 s on both hosts here. This is the
# margin for a loaded host, not an expected wait.
health=""
waited=0
while [ "$waited" -lt 60 ]; do
    health="$(curl "${CURLOPTS[@]}" "$BASE/health" 2>/dev/null)"
    case "$health" in *'"status":"ok"'*) break ;; esac
    sleep 1
    waited=$((waited + 1))
done

case "$health" in
    *'"status":"ok"'*)
        printf 'listen=%s\n' "$LISTEN"
        printf 'pid=%s\n' "$pid"
        printf 'health=%s\n' "$health"
        printf 'ready_after_s=%s\n' "$waited"
        printf 'result=serving\n'
        ;;
    *)
        printf 'result=failed\n'
        printf 'log:\n'
        sed 's/^/  /' "$STATE_DIR/local-api.log"
        exit 1
        ;;
esac

# `serve start` also clears VM directories a crashed or force-killed run left
# behind, which is worth knowing before reporting those as a leak.
if grep -q 'Reclaimed' "$STATE_DIR/local-api.log" 2>/dev/null; then
    grep 'Reclaimed' "$STATE_DIR/local-api.log" | sed 's/^/note: /'
fi
```

### `scripts/lifecycle-check.sh`

```bash
#!/usr/bin/env bash
# Drive one machine through its whole lifecycle over HTTP and assert every
# result from the response body.
#
# usage: lifecycle-check.sh [<name>]      (default smolskill-api)
#
# Reads the listen address serve-start.sh recorded. Two rules run through the
# whole script:
#
#   1. A failing guest command still returns HTTP 200. Assert exitCode from the
#      body, never the status line.
#   2. Upload files only AFTER the workload container is running. An upload
#      before that returns 200 with the path and byte count, is readable for a
#      moment, and is then gone for good.

set -uo pipefail

NAME="${1:-smolskill-api}"
here="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"

LISTEN="$(cat "$STATE_DIR/local-api.listen" 2>/dev/null)"
if [ -z "$LISTEN" ]; then
    printf 'no server recorded; run serve-start.sh first\n' >&2
    exit 2
fi

case "$LISTEN" in
    unix://*) CURLOPTS=(-s --unix-socket "${LISTEN#unix://}"); BASE="http://localhost" ;;
    *)        CURLOPTS=(-s); BASE="http://$LISTEN" ;;
esac
api() { curl "${CURLOPTS[@]}" "$@"; }

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf '%s=ok (%s)\n' "$1" "$2"
    else
        printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"
        fail=1
    fi
}
jget() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get(sys.argv[1],""))' "$1"; }

# 1. Create. The field names are the schema's, not the CLI's flags: `network`,
# not `net`; `memoryMb`, not `memory`. Unknown fields are accepted with 200 and
# silently ignored, and the machine then fails two calls later with a message
# about the image. Export the spec rather than guessing:
#   smolvm serve openapi -o ./openapi.json
# `cmd` gives the machine a workload that stays up. Without it the image's own
# CMD becomes the persistent workload, and for an interpreter image that exits
# at once: the container is relaunched and an exec can land in the gap, coming
# back as exitCode 1 with an empty stdout AND an empty stderr, which is quieter
# than the CLI's equivalent failure. Seen once in this packet's own run.
created="$(api -X POST "$BASE/api/v1/machines" -H 'content-type: application/json' \
    -d "{\"name\":\"$NAME\",\"image\":\"python:3.12-alpine\",\"network\":true,\"memoryMb\":2048,\"cmd\":[\"sh\",\"-c\",\"while true; do sleep 3600; done\"]}")"
check created_state "$(printf '%s' "$created" | jget state)" created
"$here/cleanup.sh" --record "$NAME"

# 2. Start.
started="$(api -X POST "$BASE/api/v1/machines/$NAME/start" -H 'content-type: application/json' -d '{}')"
check started_state "$(printf '%s' "$started" | jget state)" running

# 3. Wait for the workload container by asserting a value it produced. This is
# the gate the upload below depends on.
# 120 s: six times the slowest workload-container start observed while building
# this packet, on the slower of the two hosts.
ready=no
waited=0
while [ "$waited" -lt 120 ]; do
    out="$(api -X POST "$BASE/api/v1/machines/$NAME/exec" -H 'content-type: application/json' \
        -d '{"command":["sh","-c","echo WORKLOAD_READY"]}' | jget stdout)"
    case "$out" in WORKLOAD_READY*) ready=yes; break ;; esac
    sleep 1
    waited=$((waited + 1))
done
printf 'workload_ready_after_s=%s\n' "$waited"
check workload_ready "$ready" yes

# 4. Exec, asserting exitCode from the body.
execd="$(api -X POST "$BASE/api/v1/machines/$NAME/exec" -H 'content-type: application/json' \
    -d '{"command":["sh","-c","echo API_EXEC_OK; uname -s"]}')"
check exec_exit_code "$(printf '%s' "$execd" | jget exitCode)" 0
case "$(printf '%s' "$execd" | jget stdout)" in
    API_EXEC_OK*) printf 'exec_stdout=ok\n' ;;
    *) printf 'exec_stdout=FAIL actual=%s\n' "$(printf '%s' "$execd" | jget stdout)"; fail=1 ;;
esac

# A command that fails inside the guest is still HTTP 200. Prove the assertion
# that catches it actually catches it.
failing="$(api -X POST "$BASE/api/v1/machines/$NAME/exec" -H 'content-type: application/json' \
    -d '{"command":["sh","-c","exit 3"]}')"
check failing_exec_exit_code "$(printf '%s' "$failing" | jget exitCode)" 3

# 5. Stream. One event per line, then a terminal exit event.
# shellcheck disable=SC2016  # $i is the guest shell's loop variable
stream="$(api -N -X POST "$BASE/api/v1/machines/$NAME/exec/stream" -H 'content-type: application/json' \
    -d '{"command":["sh","-c","for i in 1 2 3; do echo line$i; sleep 1; done"]}')"
check stream_lines "$(printf '%s' "$stream" | grep -c '^data: line')" 3
case "$stream" in *'event: exit'*) printf 'stream_exit_event=ok\n' ;; *) printf 'stream_exit_event=FAIL\n'; fail=1 ;; esac

# 6. Files, now that the container is up. Absolute path, URL-encoded.
api -X PUT "$BASE/api/v1/machines/$NAME/files/%2Ftmp%2Fabs.txt" --data-binary 'PAYLOAD123' >/dev/null
check file_roundtrip "$(api "$BASE/api/v1/machines/$NAME/files/%2Ftmp%2Fabs.txt")" PAYLOAD123

# 7. Stop and delete. Delete machines BEFORE the server goes away: shutting the
# server down does not stop them, it orphans them.
api -X POST "$BASE/api/v1/machines/$NAME/stop" -H 'content-type: application/json' -d '{}' >/dev/null
api -X DELETE "$BASE/api/v1/machines/$NAME" >/dev/null
check machines_empty "$(api "$BASE/api/v1/machines")" '{"machines":[]}'

if [ "$fail" -eq 0 ]; then printf 'result=lifecycle_ok\n'; else printf 'result=FAILED\n'; fi
exit "$fail"
```

### `scripts/cleanup.sh`

```bash
#!/usr/bin/env bash
# Delete the machines this packet's scripts created, then prove the host is clean.
#
# Only machines recorded in the state file are deleted, so a machine you or
# another session created by hand is never touched. Scripts record a name by
# calling: cleanup.sh --record <name>
#
# usage: cleanup.sh [--record <name>] [--reap] [--purge]
#   --record <name>  add a machine name to the state file and exit
#   --reap           kill leftover VM processes (see the warning it prints)
#   --purge          also remove the state file once the list is empty

set -uo pipefail

PACKET="local-api"
PREFIX="smolskill-"

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
STATE_DIR="${SMOLVM_SKILL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smolvm-skills}"
STATE_FILE="$STATE_DIR/$PACKET.machines"

reap=0
purge=0
while [ $# -gt 0 ]; do
    case "$1" in
        --record)
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$2" >> "$STATE_FILE"
            exit 0
            ;;
        --reap)  reap=1 ;;
        --purge) purge=1 ;;
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

# 1. Delete recorded machines. --force is not optional: without it the command
# prompts, defaults to No, and leaves the machine in place while the script
# carries on. --cascade removes branch children, which otherwise block the
# delete.
if [ -s "$STATE_FILE" ]; then
    while read -r name; do
        [ -n "$name" ] || continue
        case "$name" in "$PREFIX"*) ;; *)
            printf 'skipping %s: not created by this packet (no %s prefix)\n' "$name" "$PREFIX"
            continue ;;
        esac
        "$SMOLVM" machine stop   --name "$name" >/dev/null 2>&1
        "$SMOLVM" machine delete --name "$name" --force --cascade 2>&1 | sed 's/^/  /'
    done < "$STATE_FILE"
fi

# 1b. Stop the API server, AFTER the machines are gone. Shutting it down does
# not stop machines: it prints "Shutting down server (VMs continue running)..."
# and leaves them with nothing managing them.
if [ -s "$STATE_DIR/local-api.pid" ]; then
    apipid="$(cat "$STATE_DIR/local-api.pid")"
    if kill "$apipid" 2>/dev/null; then
        printf 'api_server=stopped pid=%s\n' "$apipid"
    else
        printf 'api_server=not_running pid=%s\n' "$apipid"
    fi
    rm -f "$STATE_DIR/local-api.pid"
    listen="$(cat "$STATE_DIR/local-api.listen" 2>/dev/null)"
    case "$listen" in unix://*) rm -f "${listen#unix://}" ;; esac
    rm -f "$STATE_DIR/local-api.listen"
fi

# 2. An ephemeral machine's entry retires after the run returns, not with it.
# Asserting an empty list immediately fails on a healthy host.
sleep 20

# 3. Assert the value, not the exit code.
listing="$("$SMOLVM" machine list 2>&1)"
if printf '%s' "$listing" | grep -q 'No machines found'; then
    printf 'machines=clean\n'
    [ "$purge" -eq 1 ] && rm -f "$STATE_FILE"
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

# 4. Report VM processes an interrupt left behind. Ctrl-C does not stop a
# machine: the VM outlives the CLI and `machine list` cannot see it, so this is
# the only route to it. Only processes whose boot config lives under this HOME's
# smolvm state are listed, so a VM another session started is left alone.
found=0
while read -r pid cfg; do
    [ -n "$pid" ] || continue
    found=1
    printf 'vm_process=%s config=%s\n' "$pid" "$cfg"
    if [ "$reap" -eq 1 ]; then
        kill -9 "$pid" 2>/dev/null && printf '  killed %s\n' "$pid"
    fi
done <<EOF
$(list_vm_processes)
EOF

if [ "$found" -eq 0 ]; then
    printf 'vm_processes=none\n'
elif [ "$reap" -eq 0 ]; then
    printf 'rerun with --reap to kill them\n'
fi
```

## Local API traps

### Upload files only after the workload container is running

**This is the one ordering rule in this packet, and it applies on every platform.**

A file uploaded before the workload container is up is written into the agent's own namespace.
Once the container starts, reads resolve **inside the container**, and for a path the container
mounts over, the earlier file is no longer in the view being read. `/tmp` is exactly such a path:
it is a tmpfs inside the guest, so the container's own `/tmp` masks whatever was seeded underneath.

Both directions pick a namespace per request. `handle_file_write` and
`handle_streaming_file_read` each switch on `nsfile::GuestNs::for_workload()`
(`crates/smolvm-agent/src/main.rs` at v1.14.2), writing and reading inside the workload container
when one is running and in the agent's namespace otherwise. The source's own comment claims the
pre-container write is safe, "seeding it before the container starts is exactly how the file
becomes visible once it does". **That holds for overlay paths and not for paths the container
mounts over.**

Reproduced on Ubuntu 24.04 aarch64 on 2026-09-07, PUT immediately after `POST /start`:

```
PUT  files/tmp%2Fr1.txt   ->  200 {"path":"/tmp/r1.txt","size":6}
GET  files/tmp%2Fr1.txt   ->  500 failed to canonicalize target /tmp/r1.txt: No such file or directory
GET  again after 30 s     ->  500 failed to read /tmp/r1.txt in the workload container: ...
```

The upload reported success, with the resolved path and the byte count, for a file that was never
readable. The two different error texts are the two namespaces: before the container it cannot
canonicalize the path at all, after it the read happens inside the container and misses.

**It is timing dependent, which makes it worse rather than better.** The same sequence on macOS
arm64, and on Linux with a long-lived `cmd` in the create body, returned `ROUND1` both immediately
and after 30 s. A run that happens to work proves nothing about the next one.

**So:** wait for a successful `exec` before uploading anything, which is what
`scripts/lifecycle-check.sh` does, or upload to a path on the overlay such as `/root` rather than
one the container mounts over.

### A failing guest command is still HTTP 200

Check `exitCode` in the body. `scripts/lifecycle-check.sh` deliberately runs `sh -c 'exit 3'` and
asserts `exitCode == 3`, so the assertion that catches this is itself tested.

### Killing the server orphans running machines

On shutdown it prints `Shutting down server (VMs continue running)...`, and that is the only
notice you get, in a line you will miss if stderr is redirected. **Delete machines before killing
the server**, or they survive it with nothing managing them. `scripts/cleanup.sh` does them in
that order.

### `serve start` also reclaims stale VM directories

On startup it printed `Reclaimed 2 dangling VM data dir(es)`, which is what clears the small
leftover directories a crashed or force-killed run leaves in the cache. Worth knowing before
reporting those as a leak.

### The default listen address is derived, not hard-coded

It is a Unix socket under `XDG_RUNTIME_DIR` (`unix:///run/user/<uid>/smolvm.sock`), not a fixed
uid, despite how the help text reads when your uid happens to be 501.

### `serve openapi` writes to stdout by default

Pass `-o`, or you will paste a 150 KB spec into your terminal. On Windows it writes its
confirmation to stderr, which PowerShell renders as an error record even though the file is
written and the exit code is 0.

### There is no authentication of any kind

`serve start` exposes create, exec and file routes with no TLS, token or auth flag. On loopback
that is a single-user boundary; the Unix socket, whose file permissions are the boundary, is the
safer default and is why it is smolvm's default and this packet's.

### Field names, versions and error bodies

Those have their own page: `references/api-fields.md`. The short version is that unknown fields
are accepted with 200 and ignored, `network` and `memoryMb` are not `net` and `memory`, and the
version in the exported spec is not the binary's.

---
title: Machine Lifecycle and CLI Reference
---

# Machine Lifecycle and CLI Reference

The `smolvm` CLI has two local lifecycle modes: ephemeral runs and persistent named machines. Commands remain nested under `smolvm machine`.

There is no `smolvm run` or `smolvm build` command.

## Ephemeral machines

`machine run` creates a VM, runs the guest command, and cleans up the VM when the command exits:

```bash
smolvm machine run --net --image alpine -- echo hello
```

Filesystem changes do not carry into the next run. Use this mode for one-off jobs, tests, and untrusted commands.

Networking is off by default, and an ephemeral run usually does not need it for
the image. The pull runs in a separate builder machine that smolvm starts with
networking on, once per image, leaving a shared seed your machine starts from a
copy of, so `--net` above is for the workload. Two things have to hold: seeding is
not turned off with `SMOLVM_IMAGE_SEEDS=0`, and the host is not Windows. A storage
size below the 20 GiB default gets a seed built at its own size. Seeding is best effort, so
when it does not happen the pull falls back into your own machine, which then
needs `--net`. The pull running in the builder machine has one consequence worth
knowing: an egress allow list on your machine governs the workload and not the
image, so a machine restricted to one hostname still starts from an image on a
registry that list does not name. Add `--seed-digest-ttl SECONDS` to reuse a
digest resolved that recently instead of checking the registry on every run. On the default backend the guest has no visible network interface and `ping` does
not work, even though TCP and UDP do — see [how networking behaves inside a
machine](#how-networking-behaves-inside-a-machine). With seeding off or on Windows, an ephemeral run pulls every time unless you add `--oci-cache`,
which keeps the image on the host for later runs to start from without a pull.
Beyond the pull, enable networking only when the workload needs network access:

```bash
smolvm machine run \
  --net \
  --image alpine \
  --allow-host registry.npmjs.org \
  -- wget -q -O /dev/null https://registry.npmjs.org
```

`--allow-host` limits egress to the named host and its subdomains: `--allow-host github.com` also reaches `api.github.com`. Add multiple flags when the workload needs multiple hosts. `--allow-host-pattern` is the narrower form, an exact name or `*.domain` only: `github.com` does not reach `api.github.com`, and `*.github.com` does not reach `github.com` itself.

What a policy filters depends on which kind you give it. A hostname list filters name resolution
too: a name that is not on it fails to resolve, and `machine egress-events` records the refusal as
a `resolve` row. An address list does not. Under `--allow-cidr` alone, or under
`--outbound-localhost-only`, the guest still resolves any name through the host's resolver and gets
real addresses back; only the connection that follows is refused. So an address list does not keep
a workload from learning where something lives.

## Persistent machines

`machine create` no longer needs networking for an uncached registry image: the host fetches it on
the machine's behalf whenever the machine's own network cannot reach the registry, including a
machine whose allow list does not name it, so `SMOLVM_IMAGE_SEEDS=0` does not stop it, where it
sends an ephemeral run back to pulling in the guest.

A persistent machine separates creation from execution:

```bash
smolvm machine create --name dev --image alpine --net
smolvm machine start --name dev
smolvm machine exec --name dev -- apk add python3
smolvm machine stop --name dev
smolvm machine start --name dev
smolvm machine exec --name dev -- python3 --version
```

Package installs, file writes, and configuration changes made through `machine exec` survive stop/start cycles. `machine stop` preserves disk state. `machine delete` removes the named machine.

`machine delete` asks for confirmation first, and when there is no terminal to ask, as in a script or an agent's shell, it fails with `needs confirmation but stdin is not a terminal; pass --force to delete it`. Pass `--force` to skip the question, or `--cascade` to delete the machines branched from it as well.

## Core lifecycle commands

| Goal | Command |
|---|---|
| Run an ephemeral command | `smolvm machine run --image IMAGE -- COMMAND` |
| Create a persistent machine | `smolvm machine create --name NAME --image IMAGE` |
| Start a machine | `smolvm machine start --name NAME` |
| Execute a command | `smolvm machine exec --name NAME -- COMMAND` |
| Open a persistent shell | `smolvm machine shell --name NAME` |
| Stop without deleting state | `smolvm machine stop --name NAME` |
| Delete a machine | `smolvm machine delete --name NAME --force` |
| Check one machine | `smolvm machine status --name NAME` |
| List machines | `smolvm machine ls` |
| List machine names only | `smolvm machine ls --quiet` |
| Checkpoint a running machine | `smolvm machine checkpoint --name NAME -o PATH` |

If `--name` is omitted, `SMOLVM_MACHINE_NAME` names the machine when it is set; `machine run` does not read it. Without either,
`machine create` generates a name such as `vm-60d4e0ec`, commands that act on an existing machine
fall back to `default`, and `delete`, `pause`, `resume`, `update`, `branch-release`, `data-dir`, `images` and `prune` refuse to run. `machine checkpoint` reads neither and needs `--name`.
A name is at most 128 letters, digits, `-` and `_`, starts with a letter or digit, and has no
trailing or doubled hyphen.

## Selected management commands

### Stream command output

```bash
smolvm machine exec --stream --name dev -- python3 train.py
```

`--timeout` on `machine exec` and `machine run` kills the command after a duration such as `30s`,
`5m` or `1h`, reporting `command timed out after 30000ms`, and exits `124`:

```bash
smolvm machine exec --name dev --timeout 5m -- python3 train.py
```

`machine stop -t SECONDS` gives the workload that long to exit after its stop signal, for this stop
only, instead of the machine's stop timeout; `-t 0` kills it at once.

### Watch a machine's health

`machine monitor` runs a health check against a machine and applies a restart policy, in the
foreground until you stop it, starting the machine first when it is stopped:

```bash
smolvm machine monitor --name web --health-cmd 'wget -q -O /dev/null http://127.0.0.1:8080/' --restart on-failure
```

`--health-cmd` runs inside the machine through `sh -c`. `--interval` and `--health-timeout` default
to the Smolfile's `[health]` values, else 5 seconds each, and `--health-retries`, the failures that
trigger a restart, to the Smolfile's, else 3. `--restart` takes `never`, `always`, `on-failure` or
`unless-stopped` and overrides the Smolfile's `[restart]` policy.

### List machines for a script

`machine ls` prints machine names in full; long names are not truncated. For
scripting, `--quiet` prints one name per line and nothing else, in the same
shape as `docker ps -q`:

```bash
smolvm machine ls --quiet | xargs -I{} smolvm machine stop --name {}
```

`--json` gives the full records when a script needs more than the name, including any labels.
`--label KEY=VALUE` on `machine create` attaches them, and `machine branch --label` labels the
child: a child inherits its source's labels, and a key given on the branch replaces the inherited
value. `machine update --label KEY=VALUE` sets one and `--remove-label KEY` removes one in any
machine state, because labels are host-side metadata.

```bash
smolvm machine create --name agent --image alpine --label team=docs --label tier=a
smolvm machine branch --from agent --name agent-b --label tier=b
```

### Read the workload's output

`machine logs` prints what the machine's workload wrote to stdout and stderr, and it still works
after the machine has stopped:

```bash
smolvm machine logs --name dev --tail 50
smolvm machine logs --name dev --follow
```

### See a machine's CPU and memory

`machine stats` samples a running machine's CPU, memory and pressure stalls; `--json` gives the raw figures:

```text
$ smolvm machine stats --name dev
Machine 'dev': running
  cpu: 0.4% of 400% (4 CPUs)
  memory: 0.10 GiB of 7.77 GiB used (1%), 7.67 GiB available
  cpu pressure: some 0.0% (10s) 0.0% (60s)
  memory pressure: some 0.0% (10s) 0.0% (60s), full 0.0% (10s) 0.0% (60s)
  io pressure: some 0.0% (10s) 0.0% (60s), full 0.0% (10s) 0.0% (60s)
```

The pressure lines are the guest kernel's stall information from `/proc/pressure`: the share of the
last 10 and 60 seconds in which some task, or every task, waited for that resource, which tells a
starved machine from a busy one.

When `smolvm serve` or an embedding SDK reaped a machine's VM, `machine status` also shows
`last exit`, naming an out-of-memory or seccomp kill (`last_exit` in `--json`). A machine started
from the CLI leaves no such record.

### Machine-readable errors

Every command takes `--error-format json`, which reports a failure on stderr as
`{"error":{"code":"NOT_FOUND","message":"..."}}` with a stable `code`, so a script can branch on the
code rather than parse the message.

### The local usage journal

smolvm appends one JSON line per machine lifecycle event, such as create, start, stop, branch or
checkpoint, to a journal on the host: `~/.local/share/smolvm/usage/events.jsonl` on Linux and
`~/Library/Application Support/smolvm/usage/events.jsonl` on macOS. A line records the machine's
shape (sizes, flags, the image's registry host) under a per-install hash of its name, never the name
itself, commands, paths, image names, labels or environment. Sharing is off by default, and smolvm
does not send the journal anywhere. `SMOLVM_USAGE=0` turns recording off for one command, `[usage]
record = false` in `~/.config/smolvm/config.toml` turns it off for good, and `SMOLVM_USAGE_DIR`
moves it. The file rotates past 8 MiB and keeps one old copy.

### Publish a port or a range of ports

`--port` takes a single port, a `HOST:GUEST` pair, or a range on either side:

```bash
smolvm machine run --net -p 8080 --image nginx -- nginx -g "daemon off;"
smolvm machine run --net -p 18080:80 --image nginx -- nginx -g "daemon off;"
smolvm machine run --net -p 3000-3009:3000-3009 --image node:22-alpine -- node server.js
```

Append `/udp` to publish a UDP port instead, for example `-p 27015:27015/udp`.

A published port listens on the host's `127.0.0.1` and `[::1]`, so only this host reaches it unless `SMOLVM_PUBLISH_ADDR` widens it. On macOS a host port below 1024, such as `-p 80:8080`, needs no root: macOS lets a normal user bind one only on every address, so smolvm binds it there and drops every connection that is not from this host. A machine can publish up to 4096 ports.

A bare port or range uses the same numbers on both sides. Ranges map one to one, so the host and guest sides must cover the same number of ports; `3000-3009:4000-4001` is rejected. A range start must not exceed its end, and port 0 is not valid.

Publishing a port selects the virtio-net backend for the machine, because the default outbound-only backend cannot accept inbound connections.

The server inside the machine must listen on `0.0.0.0` (or the machine's own address), not `127.0.0.1`. A published port reaches the machine's network interface, so a server listening only on the machine's localhost cannot be reached from the host: the connection is accepted and then reset, which curl reports as `Connection reset by peer` and Safari as "the server unexpectedly dropped the connection". Many development servers listen on localhost by default, so start them with their bind option, for example `jupyter lab --ip=0.0.0.0` or `python3 -m http.server 8000 --bind 0.0.0.0`.

### Publish the ports a machine starts listening on

`--auto-ports` on `machine run` or `machine create` publishes every TCP port a process in the
machine listens on, at the same port number on the host's `127.0.0.1` and `[::1]`, for as long as
it listens. No `-p` is needed, which suits dev servers and tools that pick their ports at run time:

```bash
smolvm machine create --name dev --image python:3.12-alpine --net --auto-ports
smolvm machine start --name dev
smolvm machine exec --name dev -- sh -c 'python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null 2>&1 &'
curl http://127.0.0.1:8000/
```

The port appears within about a second and closes once nothing listens on it or the machine
stops. Auto ports reach a server bound to the guest's `127.0.0.1` as well as one on `0.0.0.0`.
`machine status` lists each port and says why one was left out, and `machine ls --json` carries
the same as `auto_ports`:

```text
  port 8000 -> 8000: auto
  port 900: listening, not published automatically (below 1024; publish it with -p HOST:900)
  port 8002: listening, not published automatically (excluded)
```

- A host port already in use is skipped rather than moved to another number, and tried again the
  next time the machine's set of listening ports changes.
- Ports below 1024 are not published automatically; publish them with `-p`.
- `--auto-ports-exclude PORT`, repeatable, leaves a port out and implies `--auto-ports`. A guest
  port already published with `-p` stays with that mapping.
- Auto ports apply only when the CLI starts the machine; `smolvm serve` and the SDKs start it
  without them. On a stopped machine, `machine update --auto-ports`, `--no-auto-ports` and
  `--auto-ports-exclude` change the setting for the next start.

### Publish a Unix socket

`machine create` and `machine run` take two socket flags, both repeatable. `--expose-socket` makes a socket the
guest listens on reachable from the host, and `--mount-socket` puts a host socket inside the
guest so a guest process can reach a host service:

```bash
smolvm machine create --name api --image alpine \
  --expose-socket /run/app.sock \
  --mount-socket /run/host-db.sock:/run/db.sock
```

`--expose-socket` takes `GUEST_PATH[:HOST_PATH]`. Without a host path the socket appears at
`<machine-dir>/<basename>`, which `smolvm machine data-dir --name api` prints.
`--mount-socket` takes `HOST_PATH:GUEST_PATH` and needs both.

Two behaviours are worth knowing before you write a client against an exposed socket.

**The host end accepts before the guest is listening.** smolvm creates the host listener when the
machine starts, so a connect succeeds whether or not anything in the guest has bound its end yet.
A client that treats a successful connect as readiness proceeds to send into a socket with no
reader. Retry on the first request and its reply, not on the connect.

**Teardown removes the default path and leaves a pinned one.** The default socket lives inside
the machine's own directory, so deleting the machine takes it with it. A host path you named
yourself sits outside that directory and stays after the machine is gone; remove it yourself
before you reuse the path.

### Run the workload as a chosen user

`--user` takes a name from the image or a numeric `uid[:gid]`, in the same form
as `docker run --user`, and overrides the image's `USER`:

```bash
smolvm machine run --net --user 1000:1000 --image python:3.12-alpine \
  --volume "$PWD:/app" -- python3 /app/main.py
```

It is accepted on `machine run`, `machine create`, and `machine exec`. On
`create` it becomes the machine's configured user, and `exec` defaults to that,
falling back to the image's `USER` when the machine has none. Passing `--user`
to `exec` overrides both for that command.

A mounted host directory does not need it. A non-root workload sees a mounted host directory as
owned by itself and can write to it, and the files it creates belong to the host user, so they
stay editable on the host.

Init commands are the exception. They provision the machine, so they run as root
regardless of `--user` or the image's `USER`.

### Copy files

Use `machine:path` for the VM side:

```bash
smolvm machine cp ./script.py dev:/workspace/script.py
smolvm machine cp ./src dev:/workspace
smolvm machine exec --name dev -- python3 /workspace/script.py
smolvm machine cp dev:/workspace/result.json ./result.json
```

A host directory is uploaded recursively, like `cp -r`: into an existing guest directory under its own name, or as the destination path itself, each file keeping its permission bits unless `--mode` is given. A download copies one file; a guest directory is refused.

`/workspace` persists across `exec` sessions and stop/start cycles. For files larger than the copy limit, mount a directory with `--volume`.

On an upload, `--uid`, `--gid` and `--mode` (octal) set the file's owner and permissions; a download refuses them. With no owner given, the file belongs to the user the workload runs as, which is root for most images.

`machine files` does the same transfers one kind at a time, for a script or a file browser, on a
running machine:

```bash
smolvm machine files --name dev list --json /workspace
smolvm machine files --name dev upload ./config.toml /workspace/config.toml
smolvm machine files --name dev upload-folder ./src /workspace/src
smolvm machine files --name dev download /workspace/result.json ./result.json
smolvm machine files --name dev archive /workspace ./workspace.tar
```

`list` does not follow the directory's symlinks and reports each entry's kind, name and size.
`upload` and `download` move one regular file and replace the destination in one step, so a
reader never sees half a file; a directory on either side is refused. `upload-folder` merges into
the destination directory, keeping files already there, and `archive` writes a directory as a tar
file without following its symlinks.

### Connect over SSH

`machine ssh-config` writes a standard OpenSSH client configuration for a machine and prints its
path and host name as JSON. Any SSH client that reads a config file, `scp`, `sftp` and editors with
a remote SSH mode included, can then use the machine, and connecting starts a stopped machine
first:

```bash
cfg=$(smolvm machine ssh-config --name dev)
ssh -F "$(echo "$cfg" | jq -r .config)" "$(echo "$cfg" | jq -r .host)"
```

The configuration reaches the machine through a smolvm `ProxyCommand` rather than a network port,
so the machine needs no networking. Port forwarding with `ssh -L` works through it. The
host name, such as `dev-f7061f783ec3b91d.smol`, resolves only through that config, and the file
and its keys live in the machine's data directory and are removed with the machine.

### Checkpoint and restore a running machine

`machine checkpoint` captures a running machine, guest RAM and processes included, into one portable `.checkpoint` file; the earlier `.smolcheckpoint` name is still accepted. The machine keeps running.

Capture it while it runs:

```bash
smolvm machine checkpoint --name dev -o ./dev.checkpoint
```

The source is paused only for the copy-on-write snapshot, a fraction of a second, and the command
reports that pause separately from the packaging that continues behind it. A machine does not have
to have been started `--branchable` to be checkpointed, though starting it that way makes the pause
shorter.

Restore it through `machine create`, which accepts a checkpoint wherever it accepts a pack:

```bash
smolvm machine create --name dev-restored --from ./dev.checkpoint
smolvm machine start --name dev-restored
```

The restored machine resumes from the captured instant instead of booting, and it gets an identity
of its own: its hostname is the new machine's name. Add `--keep-identity` to keep the hostname and
machine ID the checkpoint was saved with, which is what rewinding one machine to an earlier save
point wants. Do not run two machines from one checkpoint with it.

`machine checkpoint-requirements --name NAME` prints, as JSON and without pausing the machine, what
a restore of it needs: the architecture, the engine version, the checkpoint format, the device
profile, the CPUs and the memory. It refuses whatever `machine checkpoint` refuses without
`--host-mounts`, so a machine with a host mount is refused too.

Because a live checkpoint carries the topology it was captured with, `--from` on a checkpoint rejects flags that would change it, including `--cpus`, `--mem`, `--storage`, and `--overlay`, naming the option: `cpus cannot be set when restoring a live checkpoint`. Its environment can still be set with `-e`. Use `--staging-dir` on the capture when the default location has too little room for the temporary assets.

From v1.36.0 a checkpoint taken with `--host-mounts` attaches each host mount only where `machine create --from` names it again with `-v HOST:GUEST`, and without it the restore is refused with the `-v` to pass, as [Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots) describes.

A checkpoint carries the machine's `--credential` bindings, never their values. To have a restore
read the values from this host, name every binding again on `machine create --from`, exactly as it
was captured, with the same variable, hosts and options:

```bash
smolvm machine create --name notes-restored --from ./notes.checkpoint \
  --credential notion=NOTION_API_KEY@api.notion.com
```

A binding that differs or is missing is refused at create with `credential bindings on a restore
can only re-authorize the checkpoint's own`, followed by the binding as it was captured. A restore
given no `--credential` is created, but `machine start` refuses it, because it would intercept
HTTPS to the bound hosts without adding a value.

A restore runs with the network its checkpoint was captured with, allow list included. On a
checkpoint captured on `virtio-net` the egress policy can change, because the host enforces it:
`--allow-cidr`, `--block-private` and the egress rules each replace their own part of the captured
policy, and a part not named stays as captured. `--allow-host` replaces the captured hosts and the
captured CIDRs together, because each host is resolved to addresses that become the new CIDR list;
pass `--allow-cidr` again for any range to keep. A checkpoint that allowed only
`example.org`, restored with `--allow-host example.com`, allows only `example.com`; restored with
`--allow-cidr 1.1.1.1/32`, it allows `example.org` and that address; restored with
`--block-private` alone, it keeps its allow list. Networking itself, the backend, the DNS resolver
and options, a named network and the guest subnet stay as captured, and asking to change one is
refused:

```text
networking cannot be set when restoring a live checkpoint: the guest resumes with the devices and resources it was captured with
an egress policy cannot be set when restoring a live checkpoint: the checkpoint was captured on the TSI backend, which cannot enforce one
```

Adding `--store DIR` writes an incremental checkpoint instead of one file. `--output` is still
what names the result, and with `--store` it becomes a self-contained directory on the same
filesystem as `DIR`, sharing unchanged chunks with the generations it keeps so history costs only
the differences:

```bash
smolvm machine checkpoint --name dev --store ./store -o ./store/dev.checkpoint
```

Like a single-file checkpoint, a stored one does not need the machine started `--branchable`.
`machine checkpoint-log PATH` shows the generations a store holds and the command to restore any
of them, `machine create --from PATH --at '~N'` restores the one N generations back (quote it in
zsh), and `machine checkpoint-prune` removes what nothing references. `machine checkpoint-warm
--from PATH` prepares a store so a later restore clones a kept copy rather than rebuilding its
RAM; `--restore-cache-entries` sets how many checkpoints stay ready, three by default, and
`--restore-cache-gib` caps what they may hold together, 16 GiB by default. Both flags are also
accepted on `machine create`.

See [Branches and Checkpoints](/docs/introduction/concepts/forks-and-snapshots) for what a checkpoint preserves and where it can be restored.

### Change a running machine

These change a machine while it runs; the last column says when each takes effect. Everything else is `machine update` on a stopped machine, from its next start.

| Setting | CLI | `smolvm serve` API | On a running machine |
|---|---|---|---|
| Published TCP ports | `machine update -p`, `--remove-port` | `PUT /api/v1/machines/:name/ports` | At once; a UDP port needs a stop |
| Egress allow list | `machine update --allow-host`, `--allow-host-pattern`, `--allow-cidr`, `--allow-udp`, `--outbound-localhost-only`, `--remove-allow-host`, `--remove-allow-cidr`, `--remove-allow-udp` and `--reset-allow-list` | `POST /api/v1/machines/:name/egress` | At once on a machine started with an allow list; lifting the list, or adding one to a machine running without one, needs a stop |
| Host directory mounts | `machine mount add`, `machine mount rm` | `/api/v1/machines/:name/mounts` | At once, until the machine stops |
| CPUs, memory, disks | `machine resize` | `POST /api/v1/machines/:name/resize` | At once; memory and disks only grow |
| Host CPU cap | None | `PUT /api/v1/machines/:name/cpu-limit` | At once, on Linux with a cgroup smolvm controls |
| Credential values | `machine credentials refresh` | `PUT /api/v1/machines/:name/credential-values` | At once |
| Credential bindings | `machine credentials add`, `machine credentials remove` | `PUT /api/v1/machines/:name/credential-bindings` | From its next request, if it started with at least one binding; otherwise from its next start |
| Labels | `machine update --label`, `--remove-label` | None | Any state |

Any other `machine update` setting, such as `--cpus`, is refused on a running machine with `invalid vm state: expected stopped, got Running`.

`machine credentials refresh` rotates the values of a machine's `--credential` bindings. It reads
each binding's variable from the shell that runs it, and the machine uses the new value from its
next request:

```bash
NOTION_API_KEY=secret_new... smolvm machine credentials refresh --name notes
```

Name bindings, as in `machine credentials refresh --name notes notion`, to refresh only those;
with none, every binding is read. A binding whose variable is unset or empty, an unknown binding,
and a machine with no bindings are refused.
On a stopped machine it changes nothing and says so, since the next `machine start` reads the
values from its own environment. A machine created through `smolvm serve` takes its values from
the API route instead, and the command refuses it with that route's path.

From v1.36.0, `machine credentials add` and `remove` change which bindings a machine has:

```bash
GH_TOKEN=ghp_... smolvm machine credentials add --name web --credential gh=GH_TOKEN@api.github.com
smolvm machine credentials remove --name web gh
```

`add` takes the same `--credential` form as `machine create`, needs each variable set in the shell
that runs it, and replaces a binding of the same name. On a running machine that started with at
least one binding it takes that value with no restart: new commands get the placeholder and the
host substitutes it from the next request, and a new host is trusted by the guest at once on a
machine started on v1.36.1 or later. A stopped machine, or a running one that started without
bindings, takes the change at its next start, which reads the value from the environment of
`machine start`. On a running machine that started without bindings, every HTTPS request from a
command started after the change fails its certificate check until that restart, to a host with no
binding too, so stop and start it right away. A host outside the machine's `--allow-host` list, a
variable that is unset, an unknown binding and a missing machine are refused. From v1.36.1
`machine ls --json` and `machine status --json` list each binding's `name`, `env_var` and `hosts`,
never its value.

### Resize a running machine

```bash
smolvm machine resize --name dev --cpus 4 --mem 2048
```

`machine resize` grows a running machine without rebooting it, and the guest sees the change at
once: `nproc` and `/proc/meminfo` report the new figures on the next command. It takes `--cpus`,
`--mem`, `--storage` and `--overlay`, at least one of them. Memory, storage and overlay grow only,
and platform alignment applies to a memory target; CPU shrinking works only on compatible Linux
x86_64 runtimes. To make a smaller machine on any host, stop it and use `machine update`. A memory
grow the host cannot back is refused with `insufficient host or VMM parent memory headroom for
requested growth`, and the machine keeps running at its old size.

### Update a machine

```bash
smolvm machine stop --name dev
smolvm machine update --name dev --cpus 6 --mem 12288
smolvm machine start --name dev
```

`machine update` changes configuration for the next start, so the machine must be stopped first,
and it says so rather than guessing: on a running machine the command fails with `invalid vm state:
expected stopped, got Running`. Labels, the allow list and published TCP ports are the exceptions,
when an update changes only them, and a host directory can be mounted into a running machine with `machine mount add`, below.

On a stopped machine it also takes `--remove-env KEY`, `--remove-volume HOST:GUEST`, `--no-gpu`,
`--no-rosetta` and `--no-egress-interceptor` to take a setting back out, and `--storage` and
`--overlay` to grow the disks of a machine that has started at least once; on one that never
started they fail with `open disk: No such file or directory`.

It also edits the egress policy, which is otherwise fixed at create time. `--allow-host`,
`--allow-host-pattern`, `--allow-cidr`, `--allow-udp` and `--outbound-localhost-only` add to the
policy, and `--remove-allow-host`, `--remove-allow-cidr` and `--remove-allow-udp` take entries back out; `--net` and `--no-net` turn
networking on and off. `--dns-option` and `--clear-dns-options` change the resolver options for the
next start; a checkpoint resumes with the options it was captured with, and `machine create --from`
a checkpoint with a different set is refused. On a stopped machine the new policy applies from the next start, and only
the named destinations answer afterwards:

```bash
smolvm machine update --name dev --allow-host example.com
smolvm machine start --name dev
```

On a running machine that was started with an allow list, an update that only changes the list and
keeps one in force applies at once, from the machine's next connection or DNS lookup, and the
command reports `running; applies now`. A removed name's addresses are refused at once, including
when the new list names no host at all. That covers hosts, patterns, CIDRs, UDP allows,
`--outbound-localhost-only` and `--reset-allow-list` with the entries to keep. A change that would lift the list, or give one to a running
machine that has none, is refused until the machine is stopped. Removing a host leaves allowed the
addresses `machine create` resolved it to; take those out with `--remove-allow-cidr`, or replace
the whole list with `--reset-allow-list` and the entries to keep, which leaves exactly those. `machine
status --json` and `machine ls --json` show the list as `allowed_hosts` and `allowed_cidrs`.

Published TCP ports change the same way: on any running machine, including one on the default
backend or with no networking, `-p` and `--remove-port` apply at once and the command reports `running; applies now`. A removed port stops accepting while
connections it already accepted carry on. A UDP port, or an update that mixes ports with other
settings, still needs the machine stopped.

### Mount a host directory

```bash
smolvm machine run \
  --image python:3.12-alpine \
  --volume "$PWD:/app" \
  -- python3 /app/main.py
```

A mounted host directory is deliberately visible to the guest. Do not mount sensitive host paths into untrusted workloads.

Add `uid=N` and optionally `gid=N` after the guest path to choose the guest user that owns the
mount's files, so they belong to the user the workload runs as without a `chown`. Without it, the
guest sees the host's numeric owner:

```bash
smolvm machine create --name dev --image alpine -v "$PWD/data:/data:uid=1000"
smolvm machine run --image alpine -v "$PWD/data:/data:ro:uid=1000,gid=1001" -- ls -ln /data
```

`gid` defaults to the `uid`. The owner covers every file that records none of its own, which is
every file the host creates or replaces; a file the guest creates keeps the owner it was created
with. The option is set when the machine boots, so `machine mount add` refuses it (add the mount
with `machine update -v` on the stopped machine instead), and a `:staged` mount, `gid=` without
`uid=`, a non-numeric value and `smolvm pack run` refuse it too.

`machine mount add` mounts a host directory into a running machine without a restart, and
`machine mount rm --target GUEST` takes it out again:

```bash
smolvm machine mount add --name dev -v "$PWD/data:/data"
smolvm machine mount add --name dev -v "$PWD/ref:/ref:ro"
smolvm machine mount ls --name dev
smolvm machine mount rm --name dev --target /data
```

The directory appears at once, `:ro` makes it read-only in the guest, and `mount ls --json` lists
what was added. Such a mount lasts until the machine stops; to keep one across restarts, add it
with `machine update -v` while the machine is stopped. A branch of the machine starts with the
same mounts. `mount add` refuses a stopped machine, a `:staged` mount, and a guest path that
already has a mount, whether added this way or from the machine's configuration; `mount rm` only
removes what `mount add` added.

### Mount an S3 bucket

The same flag mounts S3-compatible object storage when the source is an `s3://` URL. The full form is `SOURCE:GUEST_PATH[:ro]`, and the guest path must be absolute:

```bash
smolvm machine run --net \
  --image python:3.12-alpine \
  --env AWS_ACCESS_KEY_ID=... \
  --env AWS_SECRET_ACCESS_KEY=... \
  --volume "s3://my-bucket/prefix:/data:ro" \
  -- python3 -c "import os; print(os.listdir('/data'))"
```

The bucket is mounted by the machine's agent from inside the guest, so the image needs no S3 or FUSE tooling. Credentials are read from the machine's environment, and `AWS_ENDPOINT_URL` points at an S3-compatible service such as R2 or MinIO. A bucket with no credentials is read anonymously.

Remote volumes need egress to reach the bucket, so an ephemeral run without `--net` is rejected rather than started. `machine run` and `machine create` accept an `s3://` source; `machine update` and `pack run` do not.

A bucket mount is not a full POSIX filesystem:

- Symlinks are not supported, and changes to ownership, permissions, executable bits and timestamps are not kept, so a copied Git repository can lose information even when every file's contents match.
- A rename is a server-side copy followed by a delete of the source. It is not atomic, and when the delete fails both names can exist.
- Writes are staged in the machine until a flush or `fsync` uploads them; writes lost with the machine before that are gone.

### Run a hypervisor inside the machine

`--nested` exposes the host's virtualization extensions to the guest so it can run KVM, which is
what lets smolvm, QEMU or another hypervisor run inside the machine:

```bash
smolvm machine run --nested --net --image ubuntu:24.04 -- sh -c "ls -l /dev/kvm"
```

It is off by default, because nesting turns work the guest would do natively into vmexits and a
nested guest runs far slower.

The host has to be able to offer the extensions in the first place, and smolvm checks before the
VM boots rather than failing inside the guest. On Apple silicon that means an M3 or newer and
macOS 15 or later; on Linux it means nested KVM is enabled, through `kvm_intel.nested=1` or
`kvm_amd nested=1`. A host that cannot returns an error naming the check result.

[Android Emulator in a Machine](/docs/guides/android-emulator) runs a guest hypervisor end to end.

Running a Docker daemon in a machine does not need this flag. Containers share the guest kernel,
so [Docker in a Machine](/docs/guides/docker-in-a-machine) works without it.

### Connect machines on a named network

Machines created with the same `--network NAME` reach each other directly by address; machines on
different networks cannot:

```bash
smolvm machine create --name db  --image alpine --network lab
smolvm machine create --name app --image alpine --network lab
smolvm machine start --name db && smolvm machine start --name app
smolvm machine exec --name db -- ip -4 addr show eth0
```

Each member gets a `100.96.N.2` address when it starts, which can change after a stop and start,
so read it rather than hardcoding it. Names do not resolve: `app` reaches `db` by its address
only. Each network leases addresses from its own pool, so two networks can hand out the same one.
`--network` implies `--net`, needs the virtio-net backend, and cannot be combined with
`--guest-subnet`.

### Moving the guest off the default range

A virtio-net guest's link is `100.96.0.0/30` by default: the gateway and resolver take the first
address, the guest the second. That sits inside `100.64.0.0/10`, the carrier NAT range a VPN such
as Tailscale claims for its whole network, so a guest that runs one loses the gateway its own DNS
depends on.

`--guest-subnet` moves the link:

```bash
smolvm machine run --guest-subnet 10.200.0.0/30 --net --image alpine -- ip -4 -o addr show eth0
# 3: eth0    inet 10.200.0.2/30 scope global eth0
```

It implies `--net` and `virtio-net`, so never add it to a machine meant to have no network, and
naming `tsi` beside it is refused with `--guest-subnet requires the virtio-net backend`. It is set
at create time: `machine update` has no equivalent, so changing it means a new machine.

### What moves a machine to virtio-net

These select `virtio-net` when you have not named a backend, because each one needs something
`tsi` cannot provide:

| You passed | Why virtio-net |
|---|---|
| `--port` / `-p` | at create, only virtio-net serves inbound connections; a running `tsi` machine gets its new TCP ports through a host forwarder |
| `--allow-host`, `--allow-cidr`, `--outbound-localhost-only`, `--block-private`, `--deny-cidr`, `--allow-udp` | the egress policy is enforced by the host-side gateway |
| `--credential` | the host substitutes credentials in that gateway |
| `--network` | a named inter-VM network is fabric routing in that gateway |
| `--guest-subnet` | a custom guest link shapes the virtio-net interface |

So adding an egress allow list to a machine changes more than its egress. The machine gains an
`eth0` with a real address, and `ping` starts working, which is the opposite of what the default
backend does above:

```console
$ smolvm machine run --net --image alpine -- ip -4 -o addr show scope global
2: dummy0    inet 203.0.113.1/24 brd 203.0.113.255 scope global dummy0

$ smolvm machine run --net --allow-host example.com --image alpine -- ip -4 -o addr show scope global
3: eth0    inet 100.96.0.2/30 scope global eth0
```

Naming `tsi` explicitly alongside any of them is refused rather than silently ignored, because
`tsi` would not enforce the policy it was given:

```text
ports:  published ports require the virtio-net backend (TSI is outbound-only); remove
        --net-backend tsi or set it to virtio-net
egress: egress policy (--allow-cidr/--allow-host/--outbound-localhost-only/--block-private)
        requires the virtio-net backend; TSI does not enforce it. Remove --net-backend tsi or
        set it to virtio-net
```

## Common resource flags

| Flag | Meaning |
|---|---|
| `--image`, `-I` | OCI image, local image archive, stdin archive (`-`), or unpacked rootfs. A reference may carry a tag and a digest together, `alpine:3.20@sha256:...`, which pins the bytes while keeping the tag readable |
| `--name`, `-n` | Machine name |
| `--net` | Enable networking |
| `--allow-host` | Allow egress to a hostname and its subdomains |
| `--allow-host-pattern` | Allow egress to an exact hostname, or to the subdomains of `*.domain`; any other pattern is refused |
| `--allow-cidr` | Allow egress to a CIDR |
| `--allow-udp` | Allow UDP to a CIDR, optionally on one port or a range, as `CIDR[:PORT[-END]]`; a `--deny-cidr` still wins; implies `--net` |
| `--block-private` | Keep the public internet open and block private, internal and link-local destinations, cloud metadata and the host's loopback; implies `--net` |
| `--allow-private` | Reopen one private CIDR under `--block-private`, which it implies; cloud metadata stays blocked |
| `--allow-host-loopback` | On `machine run` only: let a machine on the default `tsi` backend reach services on the host's own `127.0.0.1` and `::1`, which `tsi` keeps closed. A `virtio-net` machine reaches them by default through `host.smolvm.internal`, as [Isolation, networking and credentials](/docs/introduction/concepts/isolation-networking-credentials#networking) describes with how to close it; cloud metadata stays blocked; implies `--net` |
| `--deny-cidr` | Refuse egress to a CIDR before any allow is checked, so it wins over every allow list; on `machine run` and `machine create`, not `update`; implies `--net` |
| `--dns` | Resolve guest names through this resolver IP instead of the host's own; implies `--net` |
| `--dns-option` | Add a resolver option to the guest's `resolv.conf`, such as `timeout:1`; repeatable, written in order as one `options` line. musl images such as Alpine honor only `ndots`, `timeout` and `attempts` |
| `--credential` | Bind a credential as `NAME=ENV_VAR@HOST[,HOST...][:body][:set-header=HEADER]`: the guest gets a placeholder in `ENV_VAR`; the host substitutes the real value only on HTTPS requests to the listed hosts, which may be wildcards such as `*.example.com`. `:body` also substitutes it in a form-encoded request body, for OAuth tokens, and `:set-header` sets that header to the whole value, in either order. Refused on an ephemeral run of a `.smolmachine`; create a machine from it instead |
| `--cpus` | vCPU count |
| `--mem` | Guest memory in MiB |
| `--shm-size` | Size of `/dev/shm`, such as `512m`, `2g` or `25%`; half the guest memory by default. Also on `machine update` |
| `--volume`, `-v` | Mount a host directory or an S3 bucket: `SOURCE:GUEST_PATH[:ro]`, and for a host directory `[:uid=N[,gid=N]]` to set the guest owner of its files. A guest path alone, such as `-v /var/lib/docker`, is a directory on the machine's own disk that persists across stop and start |
| `--cache-disk` | Mount a shared cache disk as `BASE:/guest/path`. `BASE` is a raw or qcow2 image that stays read-only and can back many machines; this machine writes only to its own layer, which its branches copy. A blank `BASE` gets an ext4 filesystem |
| `--port`, `-p` | Forward `HOST_PORT:GUEST_PORT`, with `/udp` appended for a UDP port |
| `--auto-ports` | Publish every TCP port the guest listens on at the same host port on loopback, while it listens |
| `--auto-ports-exclude` | A guest port auto ports never publish; repeatable, and implies `--auto-ports` |
| `--user`, `-u` | Run the workload as a name or `uid[:gid]` |
| `--max-image-size` | On `machine run` and `machine create`: the largest local image archive accepted, such as `16GiB`, `512M` or a byte count; 8 GiB by default. A larger archive is refused with its size, and `SMOLVM_MAX_IMAGE_BYTES` sets the same limit |
| `--oci-platform` | On `machine run`, `machine create` and `pack create`: the platform to pull from a multi-platform image, such as `linux/amd64`; a platform the image does not have is refused |
| `--allow-system-mounts` | On `machine run`, `machine create`, `machine update` and `pack run`: allow read-only host `/etc` and `/var/log` mounts below `/host`, which are refused otherwise. It exposes sensitive host data to the guest, so never use it for untrusted workloads |
| `--disk` | Attach a host disk image or block device as `/dev/vdc`, `/dev/vdd` and so on, in order; `:ro` makes it read-only. smolvm never formats or mounts it, and a missing path is refused |
| `--workdir`, `-w` | The workload's working directory; also on `machine update` |
| `--interactive`, `-i` | Keep stdin open |
| `--tty`, `-t` | Allocate a TTY |
| `--smolfile`, `-s` | Read configuration from a Smolfile |
| `--block-io` | Host block I/O engine, `sync` or `async` |
| `--disk-durability` | `full` (the default): a guest `fsync` waits for the host's disk. `deferred`: guest writes reach it on the host's schedule, much faster for fsync-heavy work such as database commits, but a host crash can lose recent writes. Also on `machine update`, for the next start |
| `--stop-signal` | On `machine create`: the signal the workload gets when the machine stops, so it can save its state and exit; a name such as `SIGINT` or a number, `SIGTERM` by default |
| `--stop-timeout` | On `machine create`: seconds the workload gets to exit after that signal before it is killed, 10 by default and at most 300 |
| `--stop-on-exit` | On `machine create`: stop the machine once its workload exits, whatever the status, flushing storage first |
| `--seed-digest-ttl` | Reuse an image digest resolved at most this many seconds ago when seeding |
| `--guest-subnet` | IPv4 subnet for the guest link, such as `10.200.0.0/30` |
| `--net-backend` | Networking implementation: `tsi` (default), `virtio-net`, or `host`, which shares the host's own addresses and ports |

`--block-io` takes `sync`, which services one request at a time on the virtio block worker, or `async`, which submits queued raw-disk reads through a restricted Linux io_uring. `async` is worth reaching for when a workload is disk heavy on a Linux host. It is a Linux-only engine, and asking for it anywhere else does not quietly fall back: the machine refuses to start with `async block I/O is currently supported on Linux hosts only; use --block-io sync`. `machine run`, `machine create` and `smolvm pack run` all accept the flag.

Defaults are 4 vCPUs, half the host's RAM as guest memory (at least 1024 MiB and at most 8192 MiB), 20 GiB of storage, and a 10 GiB overlay. A machine keeps the memory it was created with, and a pack's default stays 8192 MiB. Memory is elastic: the host commits and reclaims memory according to guest use.

## How networking behaves inside a machine

Networking is off until you pass `--net`. What you get then depends on the backend, and the
default one behaves in a way that surprises people the first time they look inside a machine.

The default backend, `tsi`, carries the guest's TCP and UDP connections directly rather than
emulating a network card. Outbound connections work and DNS works. Published ports do not: a
machine that publishes one is moved to `virtio-net` instead, which is the next section. But on
`tsi` there is no virtual interface for the guest to show you:

```console
$ smolvm machine exec --name web -- ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
2: dummy0: <BROADCAST,UP,LOWER_UP> mtu 1500 ...
```

`lo` and `dummy0` are the whole list. There is no `eth0`, the guest holds no IP address of its
own, and `ip route` shows only a placeholder route. None of that means networking is broken.

**`ping` does not work on this backend, and its failure is misleading.** ICMP is not TCP or UDP,
so `tsi` does not carry it:

```console
$ smolvm machine exec --name web -- ping -c1 8.8.8.8
ping: sendto: Network unreachable
```

The machine reached the internet perfectly well a moment later:

```console
$ smolvm machine exec --name web -- wget -qO- https://example.com
<!doctype html><html lang="en">...
```

So check connectivity with something that speaks TCP — `wget`, `curl`, or your own client — and
treat a missing interface and a failing `ping` as expected rather than as symptoms.

### When you need a real interface

Pass `--net-backend virtio-net` and the guest gets an ordinary network card, its own address, and
ICMP:

```console
$ smolvm machine create --name web --image alpine --net --net-backend virtio-net
$ smolvm machine start --name web
$ smolvm machine exec --name web -- ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: dummy0: <BROADCAST,NOARP> ...
3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
$ smolvm machine exec --name web -- ping -c1 8.8.8.8
1 packets transmitted, 1 packets received, 0% packet loss
```

Choose `virtio-net` when the workload inspects its own interfaces, needs ICMP, or runs software
that expects a routable address — a VPN client, a container runtime, or a network test suite.
Otherwise the default is the one to keep: it needs no interface configuration in the guest and
carries the traffic most workloads actually make.

### Sharing the host's network

`--net-backend host`, with `--net`, gives the guest the host's own network: a server in the
guest listens on the host's port directly, with no `-p`, and the guest reaches services on the
host's loopback as `127.0.0.1`. There is no boundary between the two on the network, so keep it
for trusted local work.

```bash
smolvm machine create --name hostnet --image alpine --net --net-backend host
```

A port the guest listens on is bound on every host interface, not only loopback. The backend
refuses what it cannot keep: published ports (`host networking binds host
ports directly and cannot publish port mappings`), an egress policy such as `--allow-host` or
`--block-private`, a named network or `--guest-subnet`, `--auto-ports`, `--credential` bindings,
a machine created through `smolvm serve`, a host that sets `SMOLVM_PUBLISH_ADDR` or
`SMOLVM_EGRESS_FLOOR=strict`, and `machine checkpoint`.

### Connection limits

Each guest TCP connection or UDP flow holds one socket in the machine's host process, on both
backends, so the host's per-process open-file limit caps how many a guest can have open at once.
smolvm raises the soft limit to the hard limit when a machine starts. macOS caps a process at
`kern.maxfilesperproc` files, which only root can raise, so a machine on a Mac with 8 GB, where
`kern.maxfilesperproc` is 10240, holds about 9,900 connections at once;
`sysctl kern.maxfilesperproc` gives the host's limit. Past the limit a connect fails in the guest with `EMFILE` on `tsi`, and on
`virtio-net` the connection is reset and the machine log names the limit. `virtio-net` also caps a
machine at 65,536 open TCP connections, which `SMOLVM_TCP_RELAY_CAPACITY` changes.

Outbound connections leave from the host's own local ports, which every machine on the host shares,
and a closed connection keeps its port for the TCP TIME-WAIT. A guest that opens and closes
connections faster than the host can recycle ports sees `EADDRNOTAVAIL`.

Run `smolvm machine COMMAND --help` against your installed version for the complete flag set.

---
title: "Credentials: an API key the machine uses and never holds"
---

# Credentials: an API key the machine uses and never holds

Gives a workload in a smolvm machine an API key or token it can use but never read, by binding the credential to named HTTPS hosts so the guest holds only a placeholder and the host substitutes the value on the way out, then proves on the host that the value never entered the machine. Use when an agent or untrusted code inside a machine has to call an API with your key; when deciding between a credential binding and --secret-env; when a request from a credentialed machine comes back 403 or 502 from smolvm itself; or when you need evidence that a key stayed out of a sandbox. Do not use it for a value the program must read and parse, such as a database URL, which is --secret-env, or for git and ssh keys, which is SSH agent forwarding.

Verified on **smolvm v1.18.2** on macOS arm64 and Linux aarch64, 2026-09-24, for everything that
is decided on the host; **the substitution arriving at a real API was not observed in this run**,
for the reason under "What was not run". Done means the guest's variable is a placeholder, the value
is nowhere in the guest, the machine's record or smolvm's database, TLS to the bound host goes
through the machine's own CA, and a placeholder anywhere but a request header is refused before it
leaves the host.

`README.md` is how the feature works: bindings, where the value comes from, what the guest sees,
what happens to each request, and the limits. This file is how to set it up and prove it.

## Procedure

```
- [ ] 1. preflight.sh             the flag, the network backend, the host variable
- [ ] 2. create-credentialed.sh   a machine bound to one host
- [ ] 3. verify-containment.sh    the value stays out; the interceptor is on the path
- [ ] 4. your own request         the first call that sends the value
- [ ] 5. cleanup.sh
```

**1. Preflight.** Read-only, and it never prints the value or its length.

```bash
export API_TOKEN=...          # however your secrets manager hands it over
scripts/preflight.sh --var API_TOKEN --host api.example.com
```

```
has_credential_flag=yes
default_backend=virtio-net
tsi_stream_intercept=yes
host_var_set=yes
host_form=ok
memory_required_mib=1024
result=ready
```

`tsi_stream_intercept` is read from the symbols of the bundled libkrun: a binding selects virtio-net
by default, and `--net-backend tsi` carries a credential only when libkrun exports
`krun_set_stream_intercept`, which both v1.18.2 release libraries do. `host_form=rejected` means the
host is not an exact lowercase DNS name; `create` would refuse it anyway, with a clearer message.

**2. Create the machine.** The value is read from the environment of this command's `machine
start`, and that is the value the machine uses until its next start.

```bash
scripts/create-credentialed.sh --var API_TOKEN --host api.example.com
```

```
workload_ready_after_s=1
guest_sees=placeholder
binding=api-token host=api.example.com
result=up
```

The command it runs is `smolvm machine create ... --credential api-token=API_TOKEN@api.example.com`
and then `machine start`. `--credential` implies `--net`. In a Smolfile the same binding is a
`[[network.credentials]]` table, in `README.md`.

**3. Prove the value stayed out.** Nothing this sends carries the placeholder where it would be
substituted, so the value goes nowhere during the check.

```bash
scripts/verify-containment.sh --var API_TOKEN --host api.example.com --other-host example.org
```

```
guest_variable=ok (placeholder)
value_in_guest=ok (0)
value_in_record=ok (0)
interception=ok (on)
passthrough=ok (real)
query_refused=ok (403)
refusal_text=smolvm credentials: placeholders are substituted in request headers only
result=contained
```

`value_in_guest` searches every process environment and the writable trees inside the guest;
`value_in_record` searches the machine's directory and smolvm's database on the host;
`interception` reads the issuer of the bound host's certificate as the guest sees it, which is
`smolvm <machine> credential CA`, while `--other-host` keeps its real issuer.

**4. Use it.** The workload sends the placeholder in a header, exactly where the real key would go:

```bash
smolvm machine exec --name smolskill-cred -- sh -c \
  'curl -sS -H "Authorization: Bearer $API_TOKEN" https://api.example.com/v1/me'
```

That is the first request that carries the value, and it goes only to the host you bound. Judge it
by the API's answer, the way you would without smolvm.

**5. Clean up.**

```bash
scripts/cleanup.sh --purge
```

## Traps

Full detail in `references/traps.md`.

- **The value is the one the machine started with.** Unsetting or changing the host variable for
  a later `machine exec` changed nothing: the interceptor runs in the process `machine start`
  launched. Start with the variable unset and every substituted request answers
  `smolvm credentials: credential unavailable` with a `502`. Rotate an environment value with a
  restart, or use a file reference, which `README.md` says is read per request.
- **Never put the real value on an `exec` command line.** smolvm writes exec commands into the
  machine's console log on the host, so a check that interpolated the value into its own `grep`
  planted it in `agent-console.log` and failed itself. `verify-containment.sh` splits the value
  and rejoins it inside the guest for that reason.
- **A 403 from smolvm is a refusal, not the API.** The body says which rule: a placeholder in the
  path, query or body; in a routing or framing header such as `Cookie`; more than one in a request;
  or one the machine did not mint. A `405` means the binding does not allow this host or method.
- **On v1.18.2 a machine created from a pack ignores `--credential`**, silently: no placeholder and
  no CA in the guest. Create it from an image, as the script does; the fix is upstream after the
  release.
- **Port 80 is not intercepted.** Plaintext HTTP is relayed untouched, so a placeholder there
  travels as the literal string and the API sees garbage.
- **The machine's CA is the only one the guest trusts for the bound host.** curl, Python, Node,
  Deno and Git pick it up from the variables smolvm sets; a client with its own trust store needs
  `/run/smol/credentials/ca.pem` added.

## Security defaults, and why they are the defaults

- **A binding is narrower than a secret.** `--secret-env` puts the plaintext in the workload's
  environment, where any code in the guest can read and send it anywhere the network allows. A
  binding lets the workload use the key only in a header, only toward the hosts named.
- **Bind to the exact host and nothing wider.** Hosts are exact names with no wildcards, and when
  the machine also has `--allow-host`, every credential host has to sit inside that list; a create
  that breaks either rule is refused.
- **Substitution is not data-loss prevention.** An API that echoes your key back in a response
  body hands it to the guest. Bind keys only to APIs you trust with them.
- **The scripts never print the value**, its length or its halves, and the preflight reports only
  whether the variable is set.
- **Cleanup deletes only machines the scripts recorded** under the `smolskill-` prefix.

## Platform arms

`references/platforms.md`. Both hosts here gave the same results on v1.18.2, on the default
virtio-net backend and on `--net-backend tsi`. Linux x86_64 and Windows were not run.

## Eval prompts, and what they produced

Run 2026-09-24 PT against v1.18.2 from the published release, under an isolated `HOME`, on macOS
26.6.2 arm64 and Lima `linux-kvm` (Ubuntu 24.04 aarch64), with a random throwaway value and
`example.com` as the bound host.

**1. "Let the agent in this sandbox call the API with my token without the sandbox ever having the
token."**

`preflight.sh`, `create-credentialed.sh` and `verify-containment.sh` in order, both hosts:
`result=ready`, `guest_sees=placeholder`, then `result=contained` with all six checks as shown
above. The guest's variable read `SMOL_PLACEHOLDER_DEMO_E0226293E472287B661DFAB687C5DE0C` on macOS.

**2. "Every request from my machine to the API now comes back 502 from smolvm."**

The machine was started without the variable in its environment. Reproduced on both hosts by
stopping a working machine and starting it again with the variable unset:

```
smolvm credentials: credential unavailable [502]
```

and by contrast, unsetting it only for `machine exec` on a machine started with it did not produce
the 502. Start the machine with the variable set.

**3. "Prove the key cannot be sent anywhere but the API I named."**

`verify-containment.sh` shows the bound host's certificate is the machine's own CA and another
host's is its real one, and these refusals were measured on both hosts with the placeholder, none
of which forwarded anything:

```
?k=<placeholder> in the query            -> 403 placeholders are substituted in request headers only
-d k=<placeholder> in the body           -> 403 placeholders are substituted in request headers only
two headers carrying the placeholder      -> 403 a request may carry one placeholder
a forged SMOL_PLACEHOLDER_DEMO_...        -> 403 unknown placeholder
Cookie: a=<placeholder>                   -> 403 placeholders are not substituted in routing or framing headers
```

Create-time rules, both hosts: `*.example.com` and an IP address are refused with `must be an exact
lowercase DNS name`, and a credential host outside the machine's `--allow-host` with `is not
reachable under the machine's network allow_hosts`.

## What was not run

- **The value arriving at a real API.** Observing it needs an HTTPS service that reports the header
  it received, and sending even a throwaway token to a third-party echo service was stopped by this
  run's own safety controls. Everything on the host side of that request was observed; the far
  side is the one step not seen. One request did reach `example.com` with a dummy value substituted,
  by mistake, in the check that led to the first trap above; `example.com` ignores the header.
- **File references and rotation in place**, which `README.md` describes; nothing here changed a
  value under a running machine except by the variable.
- **Credentials over the HTTP API**, branches and checkpoints carrying bindings, and portable
  restores on another host.
- **Linux x86_64 and Windows.**

## Related packets

- `sandbox` for the machine this usually protects, and `--allow-host`, which a binding must fit.
- `local-api` for the `credentials` field on a create body.
- `teardown` for the wider cleanup.

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Report whether this host can give a machine a credential it can use but not
# read: the flag, the network backend the interceptor needs, and whether the host
# variable that holds the value is set. Read-only: starts no VM, writes no smolvm
# state, and never prints the value.
#
# usage: preflight.sh --var <HOST_ENV_VAR> --host <api.example.com>
#
# Output is one key=value per line so a caller can parse it. The last line is
# always result=ready or result=blocked.

set -uo pipefail

VERIFIED_VERSION="1.18.2"

emit() { printf '%s=%s\n' "$1" "$2"; }

blocked=0
note() { printf 'note=%s\n' "$1"; }

VAR=""
HOST=""
while [ $# -gt 0 ]; do
    case "$1" in
        --var)  VAR="$2"; shift ;;
        --host) HOST="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

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
        ;;
    *)
        emit platform "unsupported-$kernel"
        emit accel unknown
        emit accel_access unknown
        blocked=1
        note "this script covers macOS and Linux; Windows was not run for this packet."
        ;;
esac

# --- the feature ---------------------------------------------------------------

if [ -n "$SMOLVM" ]; then
    createhelp="$("$SMOLVM" machine create --help 2>&1)"
    if grep -q -- '--credential <NAME=ENV_VAR@HOST>' <<<"$createhelp"; then
        emit has_credential_flag yes
    else
        emit has_credential_flag no
        blocked=1
        note "this smolvm has no --credential; credential substitution arrived in v1.18.0"
    fi
fi

# The interceptor sits on the machine's network path. A credential binding
# selects the virtio-net backend by default, which needs nothing more. TSI works
# only when libkrun exports krun_set_stream_intercept; otherwise a machine asked
# for --net-backend tsi fails at start. Read the bundled library's symbols
# rather than starting a VM to find out.
emit default_backend virtio-net
libdir="${SMOLVM_LIB_DIR:-$HOME/.smolvm/lib}"
lib="$(ls "$libdir"/libkrun.dylib "$libdir"/libkrun.so 2>/dev/null | head -1)"
if [ -z "$lib" ]; then
    emit tsi_stream_intercept unknown
    note "no libkrun found under $libdir; set SMOLVM_LIB_DIR to check whether --net-backend tsi can carry a credential"
elif command -v nm >/dev/null 2>&1; then
    case "$kernel" in Darwin) syms="$(nm -gU "$lib" 2>/dev/null)" ;; *) syms="$(nm -D --defined-only "$lib" 2>/dev/null)" ;; esac
    if grep -q 'krun_set_stream_intercept' <<<"$syms"; then emit tsi_stream_intercept yes; else
        emit tsi_stream_intercept no
        note "this libkrun cannot intercept TSI streams: leave the backend at its default, virtio-net, or a start with --net-backend tsi fails"
    fi
else
    emit tsi_stream_intercept unknown
fi

# The value itself: set or not, never shown. Its length is not shown either.
if [ -n "$VAR" ]; then
    if [ -n "$(printenv "$VAR" 2>/dev/null)" ]; then emit host_var_set yes; else
        emit host_var_set no
        blocked=1
        note "$VAR is not set in this environment. The value is read from the environment of the machine start, so set it there; a machine started without it answers every substituted request with 502 credential unavailable."
    fi
fi
if [ -n "$HOST" ]; then
    case "$HOST" in
        *[!a-z0-9.-]*|*..*|.*|*.|[0-9]*[0-9]) emit host_form rejected; blocked=1
            note "a credential host must be an exact lowercase DNS name: no wildcard, scheme, port or IP address" ;;
        *) emit host_form ok ;;
    esac
fi

emit memory_required_mib 1024

if [ "$blocked" -eq 0 ]; then emit result ready; else emit result blocked; fi
```

### `scripts/create-credentialed.sh`

```bash
#!/usr/bin/env bash
# Create and start a machine whose workload can use a credential it never holds.
#
# usage: create-credentialed.sh --var <HOST_ENV_VAR> --host <api.example.com>
#                               [--name <smolskill-...>] [--binding <name>] [--image <img>]
#   --var      the host environment variable holding the value; the guest gets a
#              placeholder under the same name
#   --host     the one host the value may be sent to; repeat the binding by hand
#              for more (NAME=VAR@host1,host2)
#
# The value is read from THIS process's environment when the machine starts, and
# the interceptor keeps using that one: unsetting or changing the variable later
# changes nothing until the next start. Set it in the environment of this script.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
VAR=""
HOST=""
NAME="smolskill-cred"
BINDING=""
IMAGE="alpine"
while [ $# -gt 0 ]; do
    case "$1" in
        --var)     VAR="$2"; shift ;;
        --host)    HOST="$2"; shift ;;
        --name)    NAME="$2"; shift ;;
        --binding) BINDING="$2"; shift ;;
        --image)   IMAGE="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$VAR" ] || [ -z "$HOST" ]; then
    printf 'usage: create-credentialed.sh --var <HOST_ENV_VAR> --host <api.example.com> [--name <n>]\n' >&2
    exit 2
fi
case "$NAME" in smolskill-*) ;; *) printf 'name must start with smolskill- so cleanup.sh will delete it\n' >&2; exit 2 ;; esac
[ -n "$BINDING" ] || BINDING="$(printf '%s' "$VAR" | tr 'A-Z_' 'a-z-')"
if [ -z "$(printenv "$VAR" 2>/dev/null)" ]; then
    printf 'result=FAILED %s is not set here, so every substituted request would answer 502 credential unavailable\n' "$VAR"
    exit 1
fi

SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
[ -n "$SMOLVM" ] || { printf 'smolvm not found; set SMOLVM to its path\n' >&2; exit 2; }

# A long-lived workload, so exec has a container to run in.
"$SMOLVM" machine create --name "$NAME" --mem 1024 --image "$IMAGE" \
    --credential "$BINDING=$VAR@$HOST" -- sh -c 'while true; do sleep 3600; done' 2>&1 | sed 's/^/  /'
listing="$("$SMOLVM" machine list 2>/dev/null)"
if ! printf '%s\n' "$listing" | grep -q "^$NAME "; then
    printf 'result=FAILED the machine was not created; the lines above say why\n'
    exit 1
fi
"$here/cleanup.sh" --record "$NAME"
"$SMOLVM" machine start --name "$NAME" 2>&1 | sed 's/^/  /'

for i in $(seq 1 60); do
    seen="$("$SMOLVM" machine exec --name "$NAME" -- sh -c "printenv $VAR" 2>/dev/null)"
    case "$seen" in
        SMOL_PLACEHOLDER_*)
            printf 'workload_ready_after_s=%s\n' "$i"
            printf 'guest_sees=placeholder\n'
            printf 'binding=%s host=%s\n' "$BINDING" "$HOST"
            printf 'result=up\n'
            exit 0 ;;
        "") ;;
        *)
            printf 'guest_sees=NOT_A_PLACEHOLDER\n'
            printf 'result=FAILED the guest variable is not a placeholder; stop and do not use this machine\n'
            exit 1 ;;
    esac
    sleep 1
done
printf 'result=FAILED the workload never answered\n'
exit 1
```

### `scripts/verify-containment.sh`

```bash
#!/usr/bin/env bash
# Prove, on this host, that a credentialed machine never holds the value. Every
# check here is decided before anything leaves the host: no request this script
# makes carries the placeholder where it would be substituted, so the value is
# never sent anywhere. Seeing the value arrive at the API is your own first real
# call, which this script does not make.
#
# usage: verify-containment.sh --var <HOST_ENV_VAR> --host <api.example.com>
#                              [--name <n>] [--other-host <host>]
#   --other-host  a host no binding names, to show its TLS is passed through
#
# The value is never put on a command line: a command passed to machine exec is
# written to the machine's console log on the host, so interpolating the value
# into one would plant it there and fail this very check. It is split in two and
# rejoined inside the guest.

set -uo pipefail

VAR=""
HOST=""
NAME="smolskill-cred"
OTHER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --var)        VAR="$2"; shift ;;
        --host)       HOST="$2"; shift ;;
        --name)       NAME="$2"; shift ;;
        --other-host) OTHER="$2"; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$VAR" ] || [ -z "$HOST" ]; then
    printf 'usage: verify-containment.sh --var <HOST_ENV_VAR> --host <api.example.com> [--name <n>]\n' >&2
    exit 2
fi
SMOLVM="${SMOLVM:-$(command -v smolvm 2>/dev/null)}"
[ -n "$SMOLVM" ] || { printf 'smolvm not found; set SMOLVM to its path\n' >&2; exit 2; }
value="$(printenv "$VAR" 2>/dev/null)"
[ -n "$value" ] || { printf 'result=FAILED %s is not set here, so there is nothing to look for\n' "$VAR"; exit 2; }
half=$(( ${#value} / 2 ))
a="${value:0:$half}"
b="${value:$half}"

fail=0
check() {
    if [ "$2" = "$3" ]; then printf '%s=ok (%s)\n' "$1" "$2"; else printf '%s=FAIL expected=%s actual=%s\n' "$1" "$3" "$2"; fail=1; fi
}
X() { "$SMOLVM" machine exec --name "$NAME" -- "$@" 2>/dev/null; }

X sh -c 'command -v openssl >/dev/null && command -v curl >/dev/null || apk add -q openssl curl >/dev/null 2>&1' >/dev/null

# 1. The guest's variable is a placeholder.
seen="$(X sh -c "printenv $VAR")"
case "$seen" in SMOL_PLACEHOLDER_*) check guest_variable placeholder placeholder ;; *) check guest_variable other placeholder ;; esac

# 2. The value is nowhere in the guest: every environment, and the writable trees.
hits="$(X sh -c 'P="$1$2"; grep -rlF "$P" /proc/[0-9]*/environ /run /etc /root /tmp /var /home 2>/dev/null | grep -v "^/proc/$$/" | wc -l | tr -d " "' _ "$a" "$b")"
check value_in_guest "${hits:-unknown}" 0

# 3. Nor in the machine's directory or smolvm's database on the host.
dir="$("$SMOLVM" machine data-dir --name "$NAME" 2>/dev/null)"
case "$(uname -s)" in Darwin) db="$HOME/Library/Application Support/smolvm" ;; *) db="${SMOLVM_DATA_DIR:-$HOME/.local/share/smolvm}" ;; esac
rec="$( { grep -rlF "$value" "$dir" "$db" 2>/dev/null || true; } | wc -l | tr -d ' ')"
check value_in_record "$rec" 0

# 4. TLS to the bound host is terminated by the machine's own CA: the interceptor
#    is on the path. No request is sent.
issuer="$(X sh -c "echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -issuer")"
case "$issuer" in *"smolvm $NAME credential CA"*) check interception on on ;; *) check interception "off (${issuer:-no answer})" on ;; esac

# 5. A host no binding names keeps its real certificate.
if [ -n "$OTHER" ]; then
    other_issuer="$(X sh -c "echo | openssl s_client -connect $OTHER:443 -servername $OTHER 2>/dev/null | openssl x509 -noout -issuer")"
    case "$other_issuer" in *"credential CA"*) check passthrough intercepted real ;; "") check passthrough no_answer real ;; *) check passthrough real real ;; esac
fi

# 6. The guard: a placeholder in the query string is refused here with a 403 and
#    never forwarded, so nothing leaves the host.
refusal="$(X sh -c "curl -s -w ' [%{http_code}]' \"https://$HOST/?probe=\$$VAR\"")"
case "$refusal" in *"[403]"*) check query_refused 403 403 ;; *) check query_refused "${refusal:-no answer}" 403 ;; esac
printf 'refusal_text=%s\n' "${refusal% \[*}"

if [ "$fail" -eq 0 ]; then printf 'result=contained\n'; else printf 'result=FAILED\n'; exit 1; fi
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

PACKET="credentials"
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

## Credential substitution traps

Each entry was measured on v1.18.2 on 2026-09-24 on macOS arm64 and Linux aarch64, with a random
throwaway value, unless it says otherwise.

### The value is the one `machine start` saw

The interceptor runs in the host process that `machine start` launched, and resolves a value from
the host environment out of that process. So:

- A machine started with the variable set kept substituting after the variable was unset for a
  `machine exec`: the request went out with the start-time value and the API answered `200`
  (macOS only; not repeated on Linux, since it sends the value).
- The same machine stopped and started with the variable unset answered every substituted request
  with `smolvm credentials: credential unavailable` and a `502`, and forwarded nothing.

`README.md` says an environment value is read at `machine start` and `machine exec` time; what was
observed is start time. Rotate a value from the environment by restarting the machine, and use a
file reference for a value that has to rotate under a running machine.

### A check that interpolates the value plants it

`machine exec` commands are written to the machine's console log on the host, `agent-console.log`
in its data directory. A containment check that ran
`smolvm machine exec -- sh -c "grep -r \"$VALUE\" /proc/*/environ ..."` put the value into that log
and then found it in the machine's record. Split the value on the host and rejoin it inside the
guest, as `scripts/verify-containment.sh` does, or pass a hash, and never paste a real key into an
`exec` command for any reason.

### A 403 or 502 with a `smolvm credentials:` body is smolvm, not the API

Measured refusals, each decided on the host before anything was forwarded:

| request from the guest | answer |
|---|---|
| placeholder in the query string | `403 smolvm credentials: placeholders are substituted in request headers only` |
| placeholder in a form body | the same |
| the placeholder in two headers | `403 smolvm credentials: a request may carry one placeholder` |
| a made-up `SMOL_PLACEHOLDER_DEMO_...` | `403 smolvm credentials: unknown placeholder` |
| placeholder in `Cookie` | `403 smolvm credentials: placeholders are not substituted in routing or framing headers` |
| any substituted request, machine started without the value | `502 smolvm credentials: credential unavailable` |

`README.md` also lists a `405` for a binding that does not allow the host or method; not measured
here. A request to the bound host with no placeholder was forwarded and answered normally.

### The create-time rules

```
credential "t" host "*.example.com" must be an exact lowercase DNS name (no wildcard, scheme, port or IP)
credential "t" host "93.184.215.14" must be an exact lowercase DNS name (no wildcard, scheme, port or IP)
credential "t" host "example.com" is not reachable under the machine's network allow_hosts
```

The last is a machine with `--allow-host example.org` and a credential for `example.com`: a
credential never widens what the machine may reach.

### Port 80 and other ports are not intercepted

A plain `http://` request to the bound host went straight through and was answered `200`. A
placeholder sent that way would reach the server as the literal string. Only port 443 is
intercepted.

### Which network backend carries it

A machine with a binding came up on virtio-net, `eth0 100.96.0.2/30`, with no backend named. With
`--net-backend tsi` it came up on TSI, `dummy0 203.0.113.1/24`, and the bound host's certificate was
still issued by the machine's credential CA and a placeholder in a query still got the `403`: TSI
carries the interceptor when libkrun exports `krun_set_stream_intercept`, which both v1.18.2
release libraries do, and `scripts/preflight.sh` reads that symbol. A guest that runs a VPN on the
virtio-net link needs `--guest-subnet`, which the `sandbox` packet's traps cover.

### What the guest has, and what it does not

Inside the guest: the variable holds `SMOL_PLACEHOLDER_<NAME>_<32 hex>`; `/run/smol/credentials/`
holds only `ca.pem`; `SSL_CERT_FILE` and `CURL_CA_BUNDLE` point at `/run/smolvm/ca-bundle.pem` and
`NODE_EXTRA_CA_CERTS` at `ca.pem`. The value was in no process environment and no file under `/run`,
`/etc`, `/root`, `/tmp`, `/var` or `/home`, and not in the machine's directory or smolvm's database
on the host. A checkpoint of a credentialed machine, extracted on macOS, did not contain it either; its
contents are compressed, so the stronger evidence is that the guest never held the value to begin
with.

### `--credential` on a machine created from a pack is dropped on v1.18.2

`smolvm machine create --name <n> --from app.smolmachine --credential demo=VAR@example.com`
succeeded, and after `machine start` the guest's `VAR` was empty and `/run/smol/credentials` did
not exist: no placeholder, no CA, no binding. Measured on macOS arm64. The fix landed upstream after
the release (#1400, which also makes `--credential` on a restore from a `.smolcheckpoint` an
explicit error, since a checkpoint keeps the bindings it was captured with). On v1.18.2 create the
credentialed machine from an image, which is what `scripts/create-credentialed.sh` does.

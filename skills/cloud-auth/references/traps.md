# Traps, with the observation behind each

Every item was reproduced on smol v1.14.3 against smolfleet API 0.1.0 on 2026-09-10 unless the
item says otherwise.

## `smol auth status` exits 0 when you are not logged in

It prints `Not logged in.` and a remediation hint, and returns 0. `smol cloud ls` exits 1 in the
same state. So a preflight shaped `smol auth status && run_the_job` walks straight into an
unauthenticated run.

```
smol auth status >/dev/null 2>&1; echo $?    # 0, logged out
smol cloud ls    >/dev/null 2>&1; echo $?    # 1, same state
```

**Gate on the text, or on `smol cloud ls`.** `verify-auth.sh` asserts the string `Logged in`
rather than the exit code, which is the general rule for this product: assert the value, never
the status.

Note the shape of the mistake, because it recurs. Capturing the exit code through a pipe
(`smol auth status | head -3; echo $?`) reports the exit code of `head`, which is 0 whatever the
CLI did. Redirect to a file and read `$?` from the command itself.

## `smol config show` lists keys that are not set, by name

```
cloud.endpoint = (not set)
cloud.api_key  = (not set)
```

A script that greps the output for `cloud.api_key` matches the label and concludes a credential
exists on a host that has none. `preflight.sh` greps for the line and then excludes `(not set)`.

## The environment variable is `SMOL_CLOUD_TOKEN`, not `SMOL_API_KEY`

The CLI does not read `SMOL_API_KEY`. With it set and nothing else configured, every cloud verb
fails as if no credential were present:

```
smol cloud ls
Error: list machines: not authenticated (401 Unauthorized). Run `smol auth login` to re-authenticate.
```

which names a command that does not fix it. See the next item.

## `smol auth login` is not the account login its own hint advertises

`smol auth status` says `Log in with your account: smol auth login`, and
`smol auth login --help` describes itself as *"Log in to a registry"*, taking only `--registry`,
`--token`, `--token-stdin` and `--no-browser`. For a cloud API credential the routes are
`SMOL_CLOUD_TOKEN` or `smol config set cloud.api_key`. No command output says that the cloud
credential and the registry credential are separate things, which is what the `Access` and
`Registry` lines of `auth status` imply.

## A persisted CLI key does not reach `curl`

`smol config set cloud.api_key` writes `~/.config/smolvm/config.toml` (mode 600, and note the
directory is `smolvm`, shared with the local engine). Nothing reads that file except the CLI, so
a procedure that mixes CLI and HTTP steps needs `SMOL_CLOUD_TOKEN` as well. `preflight.sh`
reports `account_readable=via_cli` in that state and says so rather than reporting a bad key.

## The API 401s every path, including ones that do not exist

`GET /v1/nope` unauthenticated returns 401, not 404, with an empty body. So the route surface
cannot be probed without a credential, and a 401 never distinguishes "wrong key" from "no such
route". This is correct behaviour and worth knowing before concluding a route is missing.

## `/health` is the only unauthenticated route, and it is the best preflight available

```
curl -fsS https://api.smolmachines.com/health
{"clusterId":"...","version":"0.1.0","apiVersion":2,
 "capabilities":["machine.branch","machine.branch_batch","machine.branch_source_continues",
                 "machine.lineage","machine.portable_checkpoint"],
 "nodesTotal":4,"nodesReady":4,"groupsTotal":0,"poolsTotal":0,"uptimeSecs":92947}
```

Every other path probed returns 401 with an empty body, including `/v1/health`, `/openapi.json`
and `/`. Because `/health` answers without a credential, it is what lets a preflight say "the API
is reachable and your key is wrong" instead of "something returned 401".

Two cautions on reading it. **An advertised capability is not a working one**: the list above is
what the cluster reports, not what has been exercised. And `uptimeSecs` is the cluster's, so a
low value means a recent deployment, which is a reason to re-verify rather than trust a stamp.

## The generated OpenAPI is on the website host, not the API host

`https://smolmachines.com/openapi.json` returns 200 with 44 paths and reports
`smolfleet API 0.1.0`. `https://api.smolmachines.com/openapi.json` returns 401. A reader who has
just been told the base URL is `api.smolmachines.com` will try it there and conclude the spec is
gone.

## Scopes are visible and worth reading first

```
Access     machine:create, machine:read, machine:exec, machine:delete, machine:files
```

The account behind this packet has no volume, usage or admin scope. A task that needs one of
those fails at the call, not at authentication, so the scope list is the cheapest early warning.

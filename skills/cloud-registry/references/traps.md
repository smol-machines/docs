# Traps, with the observation behind each

Reproduced on smol v1.14.3 against `registry.smolmachines.com` on 2026-09-10 unless an item says
otherwise.

## A pushed artifact cannot be removed with any shipped tool

`smol pack` has create, push, pull, inspect. `smol registry` has ls, catalog, tags, login,
logout. Neither deletes. The OCI manifest delete is refused:

```
DELETE https://registry.smolmachines.com/v2/tenants/<tenant>/<name>/manifests/sha256:...
{"code":"UNSUPPORTED","message":"the operation is unsupported"}
http=401
```

The status says "authenticate" and the body says "this operation does not exist", so a client
doing the correct thing for a 401 and retrying with fresh credentials will never succeed.

The push command's own closing line is *"Registered in your catalog"*: it creates durable state
in the account and offers no way to undo it, while every other resource in this product family
has a delete. **Plan the name, and reuse one tag across runs.**

## The registry verbs disagree about whether you are logged in

With only `SMOL_CLOUD_TOKEN` set, in the same shell, same second:

| Command | Result |
|---|---|
| `smol pack push` | **succeeds** |
| `smol registry tags` | **succeeds**, exit 0 |
| `smol registry ls` | `No registries configured. Log in with: smol registry login`, exit 0 |
| `smol registry catalog` | registry `401 UNAUTHORIZED`, exit 1 |

`ls` lists *stored credentials* and the push uses the ambient token, so this behaves as built,
but the wording tells you to perform a login you demonstrably do not need. **Do not conclude from
`registry ls` that a push will fail.**

## Measure exit codes without a pipe, and mind your shell

`smol registry catalog | head` reports `head`'s status, which is 0 while the command underneath
failed. Measured directly, `catalog` exits 1 and `tags` exits 0.

A second way to get this wrong, hit twice while writing this packet: **zsh does not word-split an
unquoted parameter and bash does.** `v="registry ls"; smol $v` runs `smol "registry ls"` in zsh,
one argument, and reports a usage error whose exit code has nothing to do with the registry. The
scripts here have a `bash` shebang for that reason.

## `smol pack inspect` takes a registry reference, not a local file

Passing a local `.smolmachine` path gets it treated as a reference and produces a bare registry
`401 UNAUTHORIZED`, which reads like a credential problem rather than a usage error. Compare
`smol registry tags` on a missing repository, which correctly says `Error: blob not found: ...`.

## `smol pack inspect` refuses an artifact whose architecture is not the host's

From an arm64 Mac against the amd64 artifact:

```
invalid manifest: no linux/arm64 build available for this machine;
the registry has: linux/amd64
```

So you cannot read the metadata of an artifact you cannot run, even though deploying that same
reference works, because the cloud is amd64. On a Mac, push and deploy are available and inspect
is not.

## Tags come in two families

```
smol registry tags registry.smolmachines.com/library/alpine
3.20
3.20-linux-amd64
latest
latest-linux-amd64
```

A plain tag is a multi-arch index; `-<os>-<arch>` is a concrete build. The suffix is the only
visible architecture signal, and the catalog endpoint that might have told you more is
unavailable to a normal key.

## A bare reference means different things to the CLI and the API

`smol cloud deploy alpine:3.20` resolves under your tenant namespace and 404s. The API's
`{"type":"image","reference":"alpine:3.20"}` resolves to `library/`. Same string, two resolvers.

## The `smolmachine` source needs an explicit arch

```json
{"source":{"type":"smolmachine","reference":"tenants/<tenant>/name:tag","arch":"amd64"}}
```

Cloud guests are `amd64`. The client may not be, so the artifact's architecture cannot be
inferred from the host that is making the call.

## Capture the manifest digest at push time

```
Manifest: sha256:758bc14a6e65d4437a387d2cd2eced960c852966aa6361f6553fdd9a6a4e3026
```

A tag can be moved; a digest cannot. Since nothing in the CLI can delete or list by digest
afterwards, the push output is the one moment this handle is offered.

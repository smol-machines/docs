---
name: "cloud-registry"
description: "Pulls a smolmachine artifact from the smol registry, pushes one into the account's own namespace, and runs a cloud machine from the artifact that was pushed. Use when a task needs a prebuilt artifact rather than an OCI image; when deciding which tag or digest to deploy; when a registry command reports it is not logged in while another one works; or before a first push, because a push cannot be undone. Do not use it to create the artifact from a machine, and do not expect it to remove one, because no shipped tool can delete a pushed artifact."
---

# Pushing and running a registry artifact

Verified on **smol v1.14.3** against `registry.smolmachines.com` and smolfleet API 0.1.0, macOS
26.6.2 arm64 client, on 2026-09-10. One pass cost **29 micros (USD 0.00003)** for 2
uptime-seconds. Done means a machine is executing code that came out of the registry write
performed earlier in the same run, proven by reading a value from inside it.

**A push cannot be undone.** No verb in `smol pack` or `smol registry` deletes, and the OCI
manifest delete is refused. Read "What cannot be undone" before pushing anything.

## Procedure

**1. Preflight.** Read-only.

```bash
scripts/preflight.sh
```

It names your tenant namespace, reports the host architecture, and measures the registry verbs
that disagree with each other.

**2. Pull an artifact.** Reads on the `library` namespace need no credential.

```bash
scripts/pull.sh
scripts/pull.sh registry.smolmachines.com/library/alpine:3.20-linux-amd64 ./artifact.smolmachine
```

Tags come in two families: a plain tag such as `3.20` is a multi-arch index, and
`-<os>-<arch>` tags are the concrete builds. The suffix is the only visible architecture signal.

**3. Push into your own namespace.** No `smol registry login` is needed; the cloud API key
authenticates the write.

```bash
scripts/push.sh "registry.smolmachines.com/tenants/<tenant>/smolskill-pack:v1" \
  ./artifact.smolmachine --i-understand-this-cannot-be-undone
```

The script refuses without that flag, because the operation has no inverse. It prints the
**manifest digest**, which is the only immutable handle to what you pushed and the only thing the
console can act on later. One push creates two tags, `v1` and `v1-linux-amd64`.

**4. Run a machine from what you pushed.** This is the step the packet exists for.

```bash
scripts/verify-registry.sh "tenants/<tenant>/smolskill-pack:v1"
```

```
runs_from_artifact=ok (3.20.10)
guest_arch=ok (x86_64)
result=registry_ok
```

The version is read out of the guest's own `/etc/alpine-release`. That is the assertion: it
proves the machine is running the artifact that was pushed rather than a coincidentally named
image.

**5. Clean up.**

```bash
scripts/cleanup.sh --reap
```

The machine deletes normally and returns its settled bill. The artifact does not delete at all.

## What cannot be undone

`smol pack` has create, push, pull and inspect. `smol registry` has ls, catalog, tags, login and
logout. **Neither can delete.** The OCI manifest delete returns
`{"code":"UNSUPPORTED","message":"the operation is unsupported"}` under an HTTP 401.

So a push creates durable, billable storage in the account with no supported way to remove it.
Two consequences for anything built on this packet:

- **Plan the name before the first push, and reuse one tag across runs.** Minting a new tag each
  run accumulates artifacts nobody can remove. Pushing the same content to the same tag changes
  nothing, which is how this packet was verified without adding to the account.
- **The console's registry page is the only candidate remover**, and it was not exercised here.

## Which reference resolves where

| Written as | Through | Resolves to |
|---|---|---|
| `alpine:3.20` | `smol cloud deploy` | your tenant namespace, and 404s |
| `alpine:3.20` | the API's `{"type":"image"}` source | `library/alpine` |
| `library/alpine:3.20-linux-amd64` | either | the official artifact |
| `tenants/<tenant>/name:tag` | the API's `{"type":"smolmachine"}` source | your own artifact |

The `smolmachine` source needs an explicit `"arch"`, because the cloud serves `amd64` and the
client may not be that.

## Security defaults, and why they are the defaults

- **`push.sh` refuses without an explicit confirmation flag.** An irreversible, account-visible
  write should not happen because a script was run with the wrong argument.
- **The manifest digest is captured and printed**, because a tag can be moved and a digest cannot,
  and it is the only handle the console can use.
- **Nothing here logs in to the registry.** The ambient cloud key is enough for push and tags, so
  no second credential is stored on disk.
- **Cleanup deletes only machines this packet recorded.** It cannot and does not touch artifacts.

## Platform arms

- **macOS arm64 client**: verified. Note `smol pack inspect` refuses an `amd64` artifact on an
  `arm64` host, so on a Mac you can push and deploy what you cannot inspect.
- **Linux and Windows clients**: **not run.**

## What was not run

- **Deleting an artifact**, by any route. There is none in the shipped tooling, and the console
  was not exercised.
- **`smol pack create`**, which builds an artifact from an image or a machine snapshot. This
  packet pulls one that already exists.
- **`smol pack inspect`** against a matching-architecture artifact. On this host it refuses.
- **The catalog endpoint.** `smol registry catalog` returns a registry 401 with a normal key.

## Related packets

- `cloud-auth` for the credential and the `Registry` line that names your namespace.
- `cloud-machine` for the lifecycle, the create body and the leak check this reuses.

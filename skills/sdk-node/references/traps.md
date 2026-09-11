# Traps, with the observation behind each

Reproduced on smolmachines 1.14.3 with Node v25.9.0 on macOS arm64, 2026-09-10.

## `console.log(machine)` prints your API key

`apiKey` is a plain enumerable property on the transport, so every generic serialiser walks into
it. Both vectors confirmed:

```javascript
JSON.stringify(machine).includes('smk_')                  // true
(await import('node:util')).inspect(machine, {depth: 6})  // contains smk_
```

`console.log` uses `util.inspect`, so a single debug line in a Node service puts the tenant key in
the logs. Structured loggers and error reporters do the same thing, and an exception carrying a
machine object can carry the key into a third-party service.

The conventional fixes are one line each: a `toJSON()` on the transport, or defining `apiKey` as
non-enumerable. Neither ships in the SDK today. **Python does not have this problem.**

## `await machine.exec(...)` resolves for a command that failed

```javascript
const bad = await machine.exec(['sh','-c','echo boom >&2; exit 42']);
bad.success    // false
bad.exitCode   // 42
```

Nothing throws. A `try/catch` around `exec` catches transport errors only, so a program that
relies on exceptions treats every guest failure as success. Use `assertSuccess()`, which throws
`ExecutionError`, or read `success`.

## `readFile` returns a Buffer while `exec().stdout` is a string

```javascript
await machine.readFile('/workspace/rt.txt')   // <Buffer 52 4f 55 ...>
(await machine.exec([...])).stdout            // 'SDK_OK\n'
```

Two types from the same object. `.toString()` on the Buffer, and remember it is not text until you
say so.

## `command` must be an array

A string is accepted by the config with no validation and the workload never runs. The API rejects
the same value with a 422, so the SDK is the more permissive of the two and the failure moves from
the create call to somewhere much later. With a declared port it appears after the readiness
timeout as a message naming readiness, not the command.

## `endpoint().headers` carries the key

As in the Python SDK. Do not log an endpoint or put one in an error message.

## The package name and the import name match, unlike Python

`npm install smolmachines` then `import { Machine } from 'smolmachines'`. The Python SDK installs
as `smolmachines` and imports as `smol`, which is worth knowing if you are porting between them.

## Node needs no certificate step

The Python SDK fails every call on a fresh python.org interpreter with
`CERTIFICATE_VERIFY_FAILED` because it uses `urllib` and depends on no `certifi`. Node ships its
own trust store, so the same code works immediately. The preflight checks rather than assuming,
so a `tls_to_api=FAILED` here means the network or the API, not a missing trust store.

## Porting a config between the SDKs drops fields silently

The Node SDK uses camelCase (`memoryMb`) and the Python SDK snake_case (`memory_mb`). Unknown
fields in a create request are accepted and ignored by the API, so a config ported with the wrong
casing returns a successful create and a machine with defaults, and nothing reports it.

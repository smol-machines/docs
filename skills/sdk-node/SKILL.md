---
name: "sdk-node"
description: "Drives smol cloud machines from Node with the smolmachines package, from install through create, exec, files and delete. Use when a Node program or agent tool needs to run code in a machine; when an await on exec did not throw for a command that failed; when a machine object needs to be logged or serialised safely; or when deciding between the SDK and raw HTTP. Do not use it for the Python SDK or for raw HTTP, which have their own packets, and do not use it to install the CLI or mint a key."
---

# Driving smol cloud from Node

Verified on **smolmachines 1.14.3** from npm (no runtime dependencies), **Node v25.9.0**, against
**smolfleet API 0.1.0**, macOS 26.6.2 arm64, on 2026-09-10. Done means a machine was created, ran
a command, round-tripped a file, and was deleted, with every assertion made on a value.

**The one trap that is specific to this SDK: `console.log(machine)` prints your API key.**
`apiKey` is a plain enumerable property, so `JSON.stringify` and `util.inspect` both expose it.
Both were confirmed here. Python does not do this.

## Procedure

**1. Install and preflight.**

```bash
npm install smolmachines
scripts/preflight.sh
```

```
node=v25.9.0
package_smolmachines=resolvable
sdk_version=1.14.3
tls_to_api=ok
credential=env
result=ready
```

Unlike the Python SDK, the package name and the import name match, and Node ships its own trust
store, so there is no certificate step.

**2. Run the lifecycle.**

```bash
SMOL_CLOUD_TOKEN=... node scripts/verify-sdk.mjs
```

```
machine_id=mach-...
exec_stdout=ok ("SDK_OK\n")
failed_exec_resolves=ok (false)
failed_exec_exit_code=ok (42)
assertSuccess_throws=ok (true)
readFile_returns_buffer=ok (true)
file_roundtrip=ok ("ROUNDTRIP")
stringify_leaks_the_key=ok (true)
inspect_leaks_the_key=ok (true)
deleted=yes
result=sdk_ok
```

The two `leaks_the_key` checks assert the exposure so that anything built on this packet knows it
is there. The script asserts it and never prints it.

## The shape that works

```javascript
import { Machine } from 'smolmachines';

const conn = { target: 'cloud', apiKey: process.env.SMOL_CLOUD_TOKEN };
let machine = null;
try {
  machine = await Machine.create({
    name: 'my-job',
    image: 'library/alpine:3.20',
    command: ['sh', '-c', 'while true; do sleep 3600; done'],
    resources: { cpus: 1, memoryMb: 256, network: true },
  }, conn);
  const result = await machine.exec(['sh', '-c', 'echo hello']);
  result.assertSuccess();
  console.log(result.stdout);
} finally {
  if (machine) await machine.delete();
}
```

`command` must be an **array**. A string is accepted by the config with no validation and the
workload never runs.

## Reading a result

`await machine.exec(...)` **resolves** for a command that failed. A `try/catch` around it catches
transport errors only.

| To ask | Use |
|---|---|
| Did it succeed | `result.success` |
| What did it exit with | `result.exitCode` |
| Throw if it failed | `result.assertSuccess()`, throws `ExecutionError` |
| Output | `result.stdout`, `result.stderr`, both strings |
| File contents | `await machine.readFile(path)`, returns a **Buffer** |

`execStream()` works against cloud machines, although the reference page says local only.

## Logging a machine safely

Never pass a `Machine` to `console.log`, `JSON.stringify`, a structured logger, or an error
reporter. Log the fields you need:

```javascript
console.log({ id: machine.id, state: await machine.state() });
```

If a machine object must be serialised, give it a `toJSON()` or define `apiKey` as
non-enumerable on the transport first. Both are one line and neither ships in the SDK today.

## Security defaults, and why they are the defaults

- **The key comes from `process.env`**, never a literal.
- **Nothing logs a machine object.** The two assertions above exist to make the hazard explicit
  rather than to demonstrate it in output.
- **Delete in a `finally`.** The script does, including on assertion failure.
- **`network: true` is outbound access for the whole machine**, on here only because the image
  pull needs it.

## Platform arms

- **macOS arm64, Node v25.9.0**: verified, in a fresh project directory.
- **Linux and Windows**: **not run.**
- **TypeScript**: **not run.** Everything here was executed as JavaScript; the package's type
  definitions were never type-checked.

## What was not run

- **The local target.** Everything here is `target: 'cloud'`.
- **A published port and a request into the guest**, which needs a server in the machine.
- **`execStream()`**, which the Python packet exercises; the Node equivalent was not run.
- **Branch and fork**, which were exercised through the Python SDK while verifying
  `cloud-machine`.
- **TypeScript type-checking**, as above.

## Related packets

- `cloud-auth` for the credential and its scopes.
- `cloud-machine` for the same lifecycle over raw HTTP.
- `sdk-python` for the same task in Python, whose install traps are different and worse.
- `cloud-errors` for what the API returns underneath these calls.

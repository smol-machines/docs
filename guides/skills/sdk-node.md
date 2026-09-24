---
title: "SDK Node: drive cloud machines from Node"
---

# SDK Node: drive cloud machines from Node

Drives smol cloud machines from Node with the smolmachines package, from install through create, exec, files and delete. Use when a Node program or agent tool needs to run code in a machine; when an await on exec did not throw for a command that failed; when a machine object needs to be logged or serialised safely; or when deciding between the SDK and raw HTTP. Do not use it for the Python SDK or for raw HTTP, which have their own packets, and do not use it to install the CLI or mint a key.

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

## Scripts

The files the procedure runs, in the order it runs them. It calls each one by the path in its heading, relative to the directory the procedure is saved in.

### `scripts/preflight.sh`

```bash
#!/usr/bin/env bash
# Read-only. Installs nothing, creates no machine, bills nothing.
set -uo pipefail
API="${SMOL_CLOUD_URL:-https://api.smolmachines.com}"
notes=()
command -v node >/dev/null 2>&1 || { echo "node=missing"; echo "result=blocked"; exit 0; }
echo "node=$(node --version)"

if node -e "require.resolve('smolmachines')" >/dev/null 2>&1; then
  echo "package_smolmachines=resolvable"
  # The package does not export its package.json, so require() of it throws.
  # Resolve the entry point and walk up to the manifest beside it.
  VER=$(node -p "const{createRequire}=require('node:module'),fs=require('node:fs'),path=require('node:path');let d=path.dirname(createRequire(process.cwd()+'/').resolve('smolmachines')),v='unknown';for(let i=0;i<4;i++){const f=path.join(d,'package.json');if(fs.existsSync(f)){v=JSON.parse(fs.readFileSync(f,'utf8')).version;break}d=path.dirname(d)}v" 2>/dev/null || echo unknown)
  echo "sdk_version=${VER:-unknown}"
else
  echo "package_smolmachines=missing"
  notes+=("note=npm install smolmachines in this project; the package and the import name match, unlike Python")
  printf '%s\n' "${notes[@]}"; echo "result=blocked"; exit 0
fi

# Node ships its own trust store, so the certificate trap that stops the Python
# SDK on a fresh interpreter does not apply here. Checked rather than assumed.
if node -e "fetch('$API/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))" >/dev/null 2>&1; then
  echo "tls_to_api=ok"; TLS_OK=yes
else
  echo "tls_to_api=FAILED"; TLS_OK=no
  notes+=("note=Node ships a CA bundle, so this is the network or the API rather than a missing trust store")
fi

[ -n "${SMOL_CLOUD_TOKEN:-}" ] && echo "credential=env" || { echo "credential=none"; notes+=("note=set SMOL_CLOUD_TOKEN"); }
echo "note=never console.log or JSON.stringify a Machine: apiKey is a plain enumerable property"

[ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
if [ "${TLS_OK:-no}" = yes ] && [ -n "${SMOL_CLOUD_TOKEN:-}" ]; then echo "result=ready"; else echo "result=blocked"; fi
```

### `scripts/verify-sdk.mjs`

```javascript
// Drives one cloud machine through the Node SDK and asserts values.
// Creates a billable machine and deletes it in a finally block, including on an
// assertion failure, because a leaked cloud machine bills until someone notices.
import { Machine, ExecutionError } from 'smolmachines';

const fails = [];
const check = (name, expected, actual) => {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) console.log(`${name}=ok (${a})`);
  else { console.log(`${name}=FAIL expected=${e} actual=${a}`); fails.push(name); }
};

const conn = { target: 'cloud', apiKey: process.env.SMOL_CLOUD_TOKEN };
let machine = null;
try {
  machine = await Machine.create({
    name: 'smolskill-node1',
    image: 'library/alpine:3.20',
    command: ['sh', '-c', 'while true; do sleep 3600; done'],
    resources: { cpus: 1, memoryMb: 256, network: true },
  }, conn);
  console.log(`machine_id=${machine.id}`);

  const r = await machine.exec(['sh', '-c', 'echo SDK_OK']);
  r.assertSuccess();
  check('exec_stdout', 'SDK_OK\n', r.stdout);

  // exec RESOLVES for a failed command. A try/catch around it catches transport
  // errors only, so the exit code has to be read from the result.
  const bad = await machine.exec(['sh', '-c', 'echo boom >&2; exit 42']);
  check('failed_exec_resolves', false, bad.success);
  check('failed_exec_exit_code', 42, bad.exitCode);
  let raised = false;
  try { bad.assertSuccess(); } catch (e) { raised = e instanceof ExecutionError; }
  check('assertSuccess_throws', true, raised);

  await machine.writeFile('/workspace/rt.txt', Buffer.from('ROUNDTRIP'));
  const got = await machine.readFile('/workspace/rt.txt');
  check('readFile_returns_buffer', true, Buffer.isBuffer(got));
  check('file_roundtrip', 'ROUNDTRIP', got.toString());

  // The headline Node-only trap: the key is a plain enumerable property, so
  // console.log and JSON.stringify both expose it. Asserted, never printed.
  const serialised = JSON.stringify(machine);
  check('stringify_leaks_the_key', true, serialised.includes('smk_'));
  const inspected = (await import('node:util')).inspect(machine, { depth: 6 });
  check('inspect_leaks_the_key', true, inspected.includes('smk_'));
} finally {
  if (machine) { await machine.delete(); console.log('deleted=yes'); }
}
console.log('result=' + (fails.length ? 'sdk_failed' : 'sdk_ok'));
process.exit(fails.length ? 1 : 0);
```

## Traps, with the observation behind each

Reproduced on smolmachines 1.14.3 with Node v25.9.0 on macOS arm64, 2026-09-10.

### `console.log(machine)` prints your API key

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

### `await machine.exec(...)` resolves for a command that failed

```javascript
const bad = await machine.exec(['sh','-c','echo boom >&2; exit 42']);
bad.success    // false
bad.exitCode   // 42
```

Nothing throws. A `try/catch` around `exec` catches transport errors only, so a program that
relies on exceptions treats every guest failure as success. Use `assertSuccess()`, which throws
`ExecutionError`, or read `success`.

### `readFile` returns a Buffer while `exec().stdout` is a string

```javascript
await machine.readFile('/workspace/rt.txt')   // <Buffer 52 4f 55 ...>
(await machine.exec([...])).stdout            // 'SDK_OK\n'
```

Two types from the same object. `.toString()` on the Buffer, and remember it is not text until you
say so.

### `command` must be an array

A string is accepted by the config with no validation and the workload never runs. The API rejects
the same value with a 422, so the SDK is the more permissive of the two and the failure moves from
the create call to somewhere much later. With a declared port it appears after the readiness
timeout as a message naming readiness, not the command.

### `endpoint().headers` carries the key

As in the Python SDK. Do not log an endpoint or put one in an error message.

### The package name and the import name match, unlike Python

`npm install smolmachines` then `import { Machine } from 'smolmachines'`. The Python SDK installs
as `smolmachines` and imports as `smol`, which is worth knowing if you are porting between them.

### Node needs no certificate step

The Python SDK fails every call on a fresh python.org interpreter with
`CERTIFICATE_VERIFY_FAILED` because it uses `urllib` and depends on no `certifi`. Node ships its
own trust store, so the same code works immediately. The preflight checks rather than assuming,
so a `tls_to_api=FAILED` here means the network or the API, not a missing trust store.

### Porting a config between the SDKs drops fields silently

The Node SDK uses camelCase (`memoryMb`) and the Python SDK snake_case (`memory_mb`). Unknown
fields in a create request are accepted and ignored by the API, so a config ported with the wrong
casing returns a successful create and a machine with defaults, and nothing reports it.

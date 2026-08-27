---
title: SDK Quick Start
---

# SDK Quick Start

The smol SDK provides one `Machine` API for local microVMs and smol cloud. Select the target explicitly so environment credentials cannot change where the machine runs.

## Install

The package is named `smolmachines` on npm and PyPI.

Do not install the older package named `smolvm` for these examples. It is a REST client for `smolvm serve`, not the unified embedded/cloud SDK documented here.

::: code-group

```bash [TypeScript / JavaScript]
# requires Node.js 18 or later
npm install smolmachines
```

```bash [Python]
# requires Python 3.9 or later
pip install smolmachines
```

:::

Python code imports the `smol` module:

```python
from smol import Machine
```

## Create a local machine

The SDK bundles the local engine. `Machine.create()` starts it in the application process; there is no daemon or separate `smolvm` installation.

The prebuilt local engine supports Apple Silicon Macs and modern glibc-based Linux on x86_64 or arm64. See [Use SDK in Local](/docs/sdk/with-local) for exact host requirements; use the cloud target from unsupported hosts.

Python's `Machine` API is synchronous. Using it as a context manager deletes the machine on exit.

::: code-group

```ts [TypeScript]
import { Machine } from "smolmachines";

const machine = await Machine.create(
  {
    resources: {
      cpus: 2,
      memoryMb: 1024,
    },
  },
  { target: "local" },
);

try {
  const result = await machine.run(
    "python:3.12-alpine",
    ["python", "-c", "print(2 ** 10)"],
  );
  result.assertSuccess();
  console.log(result.stdout);
} finally {
  await machine.delete();
}
```

```python [Python]
from smol import ConnectOptions, Machine, MachineConfig, ResourceSpec

config = MachineConfig(
    resources=ResourceSpec(
        cpus=2,
        memory_mb=1024,
    )
)

with Machine.create(config, ConnectOptions(target="local")) as machine:
    result = machine.run(
        "python:3.12-alpine",
        ["python", "-c", "print(2 ** 10)"],
    )
    result.assert_success()
    print(result.stdout)
```

:::

Guest networking is disabled by default. Image pulls happen outside the guest, so enable networking only when the workload itself needs outbound access.

## Complete examples

- [TypeScript local machine](https://github.com/smol-machines/smol/blob/v1.7.1/sdk/node/examples/basic.ts)
- [TypeScript cloud machine](https://github.com/smol-machines/smol/blob/v1.7.1/sdk/node/examples/cloud.ts)
- [Python cloud machine](https://github.com/smol-machines/smol/blob/v1.7.1/sdk/python/examples/cloud.py)

See [Machine API](/docs/sdk/machine-api) for the released methods and configuration types.

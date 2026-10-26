---
title: SDK Quick Start
---

# SDK Quick Start

The smol SDK provides one `Machine` API for local microVMs and smol cloud. Select the target explicitly so environment credentials cannot change where the machine runs.

## Install

The package is named `smolmachines` on npm and PyPI, and the crate is `smolmachines` on
crates.io. This page covers Node and Python, and Go [below](#go); Rust has its own page,
[Rust SDK](/docs/sdk/rust), because its install and its host requirements differ.

Install `smolmachines`. The `smolvm` package on npm is an empty placeholder and `smolvm` on PyPI is a different project; neither is this SDK.

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
      network: true,
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
        network=True,
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

Guest networking is disabled by default. The examples above turn it on because `run(image, command)` pulls inside the guest; a machine created with an `image` in its config does not need it, as [Use SDK in Local](/docs/sdk/with-local#run-an-oci-image) explains.

## Go

The Go module is `github.com/smol-machines/smol/sdk/go` and needs Go 1.25 or newer; local machines on Linux need glibc 2.34 or later. On its first local machine it downloads the runtime released with its own version, about 50 MB, and caches it, so later runs start offline.

```bash
go get github.com/smol-machines/smol/sdk/go
```

```go
import smol "github.com/smol-machines/smol/sdk/go"

m, err := smol.Create(ctx, smol.MachineConfig{
	Resources: smol.ResourceSpec{CPUs: 2, MemoryMB: 1024, Network: smol.Bool(true)},
}, nil)
if err != nil {
	return err
}
defer m.Delete(context.Background())

r, err := m.Run(ctx, "python:3.12-alpine", []string{"python", "-c", "print(2 ** 10)"}, nil)
fmt.Print(r.Stdout)
```

To run the same code on smol cloud, give the config an `Image` and pass `&smol.ConnectOptions{Target: smol.TargetCloud}` as the last argument to `Create`. Set `SMOLMACHINES_NO_DOWNLOAD=1` to fail instead of downloading the runtime on a host that may not reach the network at run time.

## Complete examples

- [TypeScript local machine](https://github.com/smol-machines/smol/blob/v1.32.2/sdk/node/examples/basic.ts)
- [TypeScript cloud machine](https://github.com/smol-machines/smol/blob/v1.32.2/sdk/node/examples/cloud.ts)
- [Python cloud machine](https://github.com/smol-machines/smol/blob/v1.32.2/sdk/python/examples/cloud.py)

See [Machine API](/docs/sdk/machine-api) for the released methods and configuration types.

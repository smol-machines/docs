---
title: Rust SDK
---

# Rust SDK

The Rust SDK runs microVMs from a Rust program, locally or on smol cloud, through the same
`Machine` API the Node and Python SDKs expose. On the local target the crate drives a `smolvm`
engine as a child process, fetching one on its own if the host has none.

## Install

The crate is named `smolmachines`.

```bash
cargo add smolmachines
```

**The local target does not need the CLI installed.** crates.io serves source rather than
binaries, so on the first call that asks for a local machine the crate downloads the engine
release matching its own version and caches it; nothing is downloaded for a cloud machine. Point
`SMOLVM` at a binary to use an installed engine instead, `SMOLMACHINES_CACHE_DIR` to move the
cache, `SMOLMACHINES_ENGINE_VERSION` to pin a different engine, and `SMOLMACHINES_NO_DOWNLOAD=1`
to refuse the fetch, which makes a host with no engine fail rather than reach the network. The
cloud target needs none of this.

For the local target, the supported hosts are macOS on Apple Silicon and Linux x64 or arm64 with
glibc 2.34 or newer, each with a hypervisor: the Hypervisor framework on macOS, KVM on Linux. The
cloud target works anywhere the crate builds.

## Create a local machine

```rust
use smolmachines::Machine;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let machine = Machine::builder("hello")
        .image("alpine:latest")
        .cpus(1)
        .memory_mib(512)
        .network(true)
        .create()?;

    machine.start()?;
    let result = machine.exec(["uname", "-sm"])?;
    println!("{}", result.stdout_utf8().trim());
    machine.delete()?;
    Ok(())
}
```

The builder takes the machine's name, and `create()` returns before the machine is started, so
`start()` is a separate call. `exec` returns a result whose `stdout_utf8()` is the captured output.

Networking is off unless you ask for it, and whether a registry image needs `.network(true)` on
the local target depends on the engine the crate pins, which is the engine of its own version. The
engine this crate currently pins refuses an uncached registry image on a machine with no
networking, and says so at `create` with a message that names the remedies: add networking, publish
a port, set an egress policy, or supply the image locally. Newer engines fetch the image on the
machine's behalf and need none of that. Pass `.network(true)`, or pin a newer engine with
`SMOLMACHINES_ENGINE_VERSION`.

## Choose local or cloud

The default is local. Only an explicit credential moves that, either `api_key` on
`ConnectOptions` or `SMOL_CLOUD_TOKEN` in the environment, so a `smol auth login` session on disk
never silently redirects a program that meant to run locally.

```rust
use smolmachines::{ConnectOptions, Machine};

// Local: the engine runs in this process.
let local = Machine::builder("here").image("alpine:latest").create()?;

// Cloud: the control plane runs it. create_with also starts the machine and
// waits for its agent, so it is ready to work when this returns.
let remote = Machine::builder("there")
    .image("alpine:latest")
    .auto_stop_seconds(300)
    .create_with(&ConnectOptions::cloud())?;
```

`create_with` on the cloud target starts the machine and waits for its agent, so unlike the local
path it does not need a separate `start()`.

## Which SDK to reach for

| You are writing | Package | Page |
|---|---|---|
| Rust | `smolmachines` on crates.io | this page |
| TypeScript or JavaScript | `smolmachines` on npm | [SDK Quick Start](/docs/sdk) |
| Python | `smolmachines` on PyPI | [SDK Quick Start](/docs/sdk) |

All three drive the same engine and the same cloud API. The Node and Python packages embed it
through NAPI and pyo3; the Rust crate drives the engine as a child process and fetches it when the
host has none.

See [Machine API](/docs/sdk/machine-api) for the method surface the three share, and
[Use SDK on Cloud](/docs/sdk/with-cloud) for the cloud target's configuration fields.

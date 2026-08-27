---
title: Supported Platforms
---

# Supported Platforms

smolvm runs Linux guests through the host's native virtualization interface. Host and guest architectures must match.

## Local host matrix

| Host | Guest | Requirement | Notes |
|---|---|---|---|
| macOS on Apple Silicon | arm64 Linux | macOS 11+ and Hypervisor.framework | Supported release path |
| macOS on Intel | x86_64 Linux | Not supported | No release asset is published for darwin-x86_64 |
| Linux x86_64 | x86_64 Linux | KVM and access to `/dev/kvm` | Supported |
| Linux aarch64 | aarch64 Linux | KVM and access to `/dev/kvm` | Supported |
| Native Windows x86_64 | x86_64 Linux | Windows Hypervisor Platform | Supported through `smolvm.exe` |

## Apple Silicon and x86_64 programs

Rosetta 2 integration can run supported x86_64 Linux binaries inside an arm64 guest on Apple Silicon. It does not change the guest architecture or make an x86_64 `.smolmachine` artifact compatible with an arm64 host.

## Windows and WSL

Native Windows uses Windows Hypervisor Platform and is the primary Windows path.

WSL2 can use the Linux/KVM path on Windows 11 when nested virtualization and KVM are available. WSL2 on Windows 10 cannot provide the required nested KVM support. Use native Windows there.

Native Windows currently lacks Vulkan GPU acceleration, VM fork, and snapshots.

## Cloud clients

Using the Cloud API does not require a local hypervisor. A client can create smol cloud machines from any environment that can authenticate and reach the API, subject to the SDK or HTTP client's own platform support.

Cloud guests are Linux. Native Windows host support does not imply Windows guest support in smol cloud.

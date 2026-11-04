---
title: Android Emulator in a Machine
---

# Android Emulator in a Machine

Run Google's Android emulator headless inside a smol machine, driven by `adb` from inside the same machine.

This page is verified on x86_64 Linux hosts with nested KVM, on smolvm v1.33.0, with emulator 37.2.13 and the API 34 x86_64 system image (Android 14). It uses software rendering and no GPU.

## What you need

An x86_64 Linux host with nested KVM, and read and write access to `/dev/kvm`:

```bash
cat /sys/module/kvm_intel/parameters/nested
ls -l /dev/kvm
```

The first command prints `Y` or `1` when nesting is on. On AMD hosts the module is `kvm_amd`.

This cannot run on Macs. Google publishes the emulator for Linux on x64 only, and a machine on a Mac is an arm64 Linux guest, so there is no emulator build for it to run. The same applies to arm64 Linux hosts. Windows hosts have not been tested.

The packages below are Google's, under the Android Software Development Kit License. Installing them means accepting that license yourself.

## Create the machine

```bash
smolvm machine create --name android --nested --net --net-backend virtio-net \
  --cpus 8 --mem 16384 --storage 64 --overlay 32 --image ubuntu:24.04
smolvm machine start --name android
```

`--nested` exposes the host's virtualization extensions, so the guest has its own `/dev/kvm` for the emulator to use. Without it there is no `/dev/kvm`. Keep `--net-backend virtio-net`: on a plain `--net` machine, `adb shell` hung on v1.33.0. The sizes are the ones we ran, not measured minimums.

Check what the machine got:

```bash
smolvm machine exec --name android -- sh -c '
  ls -l /dev/kvm /dev/dma_heap/system
  ls /proc/pressure
  mkdir -p /tmp/binderfs && mount -t binder binder /tmp/binderfs && ls /tmp/binderfs
'
```

The guest kernel carries Binder, binderfs, DMA-BUF heaps with the system heap, and pressure stall information for Android tooling:

```text
crw------- 1 root root 251,   0 Nov  4 05:47 /dev/dma_heap/system
crw-rw-rw- 1 root root  10, 232 Nov  4 05:47 /dev/kvm
cpu
io
memory
binder
binder-control
features
hwbinder
vndbinder
```

## Install the emulator

Inside the machine, install the libraries the emulator loads, then download the three packages and check each one against the SHA-1 in Google's SDK repository listing:

```bash
smolvm machine exec --name android -- sh -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q >/dev/null
  apt-get install -y -q curl unzip ca-certificates libpng16-16t64 libpulse0 libgl1 libnss3 \
    libxcomposite1 libxcursor1 libxi6 libxtst6 libasound2t64 libxkbfile1 libxdamage1 \
    libxrandr2 libdrm2 libgbm1 >/dev/null
  mkdir -p /opt/android/system-images/android-34/default /tmp/sdk
  cd /tmp/sdk
  base=https://dl.google.com/android/repository
  curl -fsSLO "$base/emulator-linux_x64-16740729.zip"
  curl -fsSLO "$base/platform-tools_r37.0.1-linux.zip"
  curl -fsSLO "$base/sys-img/android/x86_64-34_r04.zip"
  sha1sum -c <<SUMS
f41f9e31eb5ca64926603c03265c50bbc0ff4172  emulator-linux_x64-16740729.zip
477254aa5f903c15cf51001717bdf347fb6b53e0  platform-tools_r37.0.1-linux.zip
5f6a249f9bc3b1b4c459b13ce2eb646c9680bed1  x86_64-34_r04.zip
SUMS
  unzip -q emulator-linux_x64-16740729.zip -d /opt/android
  unzip -q platform-tools_r37.0.1-linux.zip -d /opt/android
  unzip -q x86_64-34_r04.zip -d /opt/android/system-images/android-34/default
  /opt/android/emulator/emulator -accel-check
'
```

The last command confirms the emulator can use the guest's KVM:

```text
emulator-linux_x64-16740729.zip: OK
platform-tools_r37.0.1-linux.zip: OK
x86_64-34_r04.zip: OK
accel:
0
KVM (version 12) is installed and usable.
accel
```

## Define the device

Write the device's two files to the machine's ext4 storage disk at `/workspace`. These are all the emulator reads for it, so neither Java nor `sdkmanager` is needed:

```bash
smolvm machine exec --name android -- sh -c '
  mkdir -p /workspace/avd/pixel.avd
  cat > /workspace/avd/pixel.ini <<INI
avd.ini.encoding=UTF-8
path=/workspace/avd/pixel.avd
target=android-34
INI
  cat > /workspace/avd/pixel.avd/config.ini <<INI
image.sysdir.1=system-images/android-34/default/x86_64/
abi.type=x86_64
hw.cpu.arch=x86_64
hw.cpu.ncore=4
hw.ramSize=4096
disk.dataPartition.size=6G
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
INI
'
```

## Boot it

Start the emulator detached, with its log on the storage disk:

```bash
smolvm machine exec --name android -d -- sh -c '
  export ANDROID_HOME=/opt/android ANDROID_SDK_ROOT=/opt/android ANDROID_AVD_HOME=/workspace/avd
  exec /opt/android/emulator/emulator -avd pixel -no-window -no-audio -no-boot-anim -no-metrics \
    -gpu swiftshader_indirect -no-snapshot -show-kernel > /workspace/emulator.log 2>&1 < /dev/null
'
```

`-gpu swiftshader_indirect` renders in software. `-show-kernel` writes Android's kernel log into the emulator's log, which is the first place to look if a boot stalls.

Wait for Android, then read what booted:

```bash
smolvm machine exec --name android -- sh -c '
  adb=/opt/android/platform-tools/adb
  $adb wait-for-device
  until [ "$($adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = 1 ]; do sleep 5; done
  $adb devices
  $adb shell getprop ro.build.version.release
  $adb shell getprop ro.build.version.sdk
  $adb shell getprop ro.product.cpu.abi
'
```

The first boot took about two minutes on a cloud VM with nested KVM, where the host is itself a VM:

```text
List of devices attached
emulator-5554	device

14
34
x86_64
```

## Keep it running

Poll the device over `adb` for five minutes and count the failures:

```bash
smolvm machine exec --name android -- sh -c '
  adb=/opt/android/platform-tools/adb
  fails=0
  for i in $(seq 1 30); do
    [ "$(timeout 10 $adb shell getprop sys.boot_completed | tr -d "\r")" = 1 ] || fails=$((fails+1))
    sleep 10
  done
  echo "polls=30 failures=$fails"
  $adb get-state
'
```

```text
polls=30 failures=0
device
```

The `adb` server here runs inside the machine and talks to the emulator beside it. `adb` to a physical phone over the network is a different path, and this page does not cover it.

## Stop and clean up

The SDK and the device survive `smolvm machine stop` and `smolvm machine start`. Stop the emulator first with the `adb emu kill` below, and after a restart boot it with the same command. The second boot took 103 seconds.

To finish, stop the emulator, then delete the machine and everything on its disks:

```bash
smolvm machine exec --name android -- /opt/android/platform-tools/adb emu kill
smolvm machine delete --name android -f
```

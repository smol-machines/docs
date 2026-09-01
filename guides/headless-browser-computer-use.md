---
title: Headless Browser and Computer Use
---

# Headless Browser and Computer Use

Run Chromium, Playwright, Puppeteer, or another browser inside a microVM when browser code needs a guest kernel and an explicit boundary from the host.

The GPU path on this page is Vulkan through virtio-gpu and Venus. It is separate from CUDA remoting and does not imply cloud GPU availability.

## Run a headless browser without GPU acceleration

Create a persistent browser machine:

```bash
smolvm machine create --name browser --net \
  --image chromedp/headless-shell:latest
smolvm machine start --name browser
```

Take a screenshot:

```bash
smolvm machine exec --name browser -- \
  /headless-shell/headless-shell \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --screenshot=/tmp/out.png \
  --window-size=1280,800 \
  https://example.com

smolvm machine exec --name browser -- base64 /tmp/out.png \
  | base64 -d > out.png
```

`--no-sandbox` disables Chromium's inner sandbox. The browser still runs inside the microVM, but guest compromise can reach everything else granted to that machine.

## Enable Vulkan acceleration

Use the maintained example for Chromium with ANGLE and the Venus Vulkan driver:

```bash
git clone https://github.com/smol-machines/smolvm.git
cd smolvm

smolvm machine create --name browser \
  -s examples/headless-browser/browser.smolfile
smolvm machine start --name browser
```

The Smolfile enables `gpu = true`, installs Chromium and `mesa-vulkan-virtio`, and sets the guest Vulkan ICD. The ICD filename is architecture-specific:

```text
x86_64: /usr/share/vulkan/icd.d/virtio_icd.x86_64.json
aarch64: /usr/share/vulkan/icd.d/virtio_icd.aarch64.json
```

Run Chromium through ANGLE:

```bash
smolvm machine exec --name browser -- \
  chromium --headless=new --no-sandbox --disable-dev-shm-usage \
  --use-gl=angle --use-angle=vulkan \
  --screenshot=/tmp/out.png --window-size=1280,800 \
  https://example.com
```

Verify the guest renderer:

```bash
smolvm machine exec --name browser -- sh -c \
  'vulkaninfo --summary 2>/dev/null | grep deviceName'
```

Vulkan acceleration requires a supported host Vulkan stack. Native Windows does not currently support this path. These commands do not provision a GPU in smol cloud.

## Pre-warm browser workers with fork

Put Chromium in a Smolfile entrypoint so it is running when the golden machine is frozen:

```bash
cat > browser-golden.smolfile <<'EOF'
image = "chromedp/headless-shell:latest"
net = true
workdir = "/headless-shell"
entrypoint = [
  "./headless-shell",
  "--headless=new",
  "--no-zygote",
  "--no-sandbox",
  "--disable-dev-shm-usage",
  "--remote-debugging-port=9222",
  "--user-data-dir=/tmp/cd",
  "about:blank",
]
EOF

smolvm machine create --name browser-golden \
  --smolfile browser-golden.smolfile

smolvm machine start --name browser-golden --forkable
smolvm machine fork --golden browser-golden --name browser-worker-1
```

`--no-zygote` is required for Chromium's process tree to survive the VM fork. Forked workers inherit the running browser, warmed libraries, and guest memory. Live network connections and host-side GPU renderer state do not survive the fork. Freeze the golden while it is idle.

Forks stay on the same host and CPU architecture as the golden. Use a `.smolmachine` pack when you need a portable cold browser environment.

## Run an interactive Linux desktop

A machine can run a real desktop and serve it from the host, so the guest needs
no VNC server, no capture tool, and no compositor-specific screencopy protocol.
Two environment variables turn it on, and both must be set:

```bash
SMOLVM_DISPLAY=1280x800 SMOLVM_VNC=127.0.0.1:5900 \
  smolvm machine run --net --gpu --cpus 4 --mem 6144 \
    --image archlinux:latest -- bash /in/run.sh
```

`SMOLVM_DISPLAY=WIDTHxHEIGHT` adds a virtio-gpu scanout. Without it, `--gpu`
gives the guest rendering only: `/dev/dri/card0` is a render node with no
connector, and a DRM compositor refuses to start because it is not a KMS
device. Each dimension must be between 1 and 16384.

`SMOLVM_VNC` chooses where the display is served. A bare port such as `5900`
binds loopback only. A `host:port` pair binds that address. A bare host uses
port 5900.

Both variables are read by the process that boots the machine, so exporting
them in the shell or prefixing the command both work.

## Open the desktop

The port speaks two protocols, chosen per connection. Point a VNC client at it,
or open the same port in a browser:

```text
http://127.0.0.1:5900/
```

The browser client is served by smolvm itself and upgrades to a WebSocket
carrying the same RFB stream, so nothing needs installing. It is also what lets
a desktop traverse an ingress or an authenticating proxy, which a raw RFB
socket cannot.

::: warning The display port has no authentication
The server implements RFB 3.8 with no authentication. Anyone who can reach the
port can watch the desktop and, when input is attached, control it. A bare port
number binds loopback for that reason. Put an authenticating proxy in front of
it before exposing it beyond the host.
:::

Input is attached when the host's libkrun provides the input feature: smolvm
adds a virtio keyboard and an absolute pointer, and client key and pointer
events are injected into the guest. Without that feature the session still
displays, but it is view-only and events are discarded.

## What the guest has to provide

The host supplies the framebuffer and the input devices. The guest still has to
run something that drives a KMS display, such as Hyprland, sway, or GNOME, and
a container guest needs two gaps bridged before the compositor starts:

- `/dev` is not devtmpfs, so the evdev nodes the kernel registers never appear.
  Create them with `mknod` from `/sys/class/input/event*/dev`.
- libinput only adopts devices classified in the udev database. Write
  `/run/udev/data` entries by hand with `E:ID_INPUT=1` and a device type.

The guest also needs `seatd` on a seat that is not VT-bound, because a workload
container has no VT:

```bash
SEATD_VTBOUND=0 seatd -g wheel &
```

The `examples/desktop` directory in the smolvm repository carries a working
setup script for an Arch guest, including both bridges above.

## Stream the desktop as H.264

Raw RFB sends uncompressed framebuffer updates, which is fine over loopback and
expensive over a network. Set `SMOLVM_VIDEO` alongside the two display
variables to encode the stream instead:

```bash
SMOLVM_DISPLAY=1280x800 SMOLVM_VNC=5900 SMOLVM_VIDEO=1 \
  smolvm machine run --net --gpu --image archlinux:latest -- bash /in/run.sh
```

Encoding runs in an external `ffmpeg` process, so smolvm neither links nor
bundles codec libraries. `SMOLVM_VIDEO_FPS` (default 60) and
`SMOLVM_VIDEO_BITRATE_MBIT` (default 20) tune it, and `SMOLVM_FFMPEG` points at
a specific binary. If the encoder cannot start, the session falls back to Raw
RFB rather than failing.

## Drive the browser

An agent inside the guest can connect to Chromium's DevTools endpoint on `127.0.0.1:9222`. Use Puppeteer, Playwright, or another CDP client for browser control.

If browser control originates outside the VM, publish or proxy only the required endpoint. Chromium's DevTools protocol can read page data, execute JavaScript, and control the browser. Do not expose it unauthenticated to a public network.

## Isolation checklist

- Leave networking off when the task does not need it
- Use `--allow-host` for the sites and APIs the browser must reach
- Mount the smallest possible host directory, preferably read-only
- Treat downloads and screenshots as untrusted output
- Do not inject account credentials into a browser task that can execute untrusted page or agent instructions
- Delete ephemeral workers after each task. Use a clean golden or pack instead of reusing state across trust boundaries

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

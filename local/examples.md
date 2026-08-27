---
title: Local Examples
---

# Local Examples

Run `smolvm COMMAND --help` to check flags against the version installed on your host.

## One-off command

```bash
smolvm machine run --net --image alpine -- sh -c \
  "printf 'isolated\n' && uname -a"
```

The VM and its filesystem changes are removed when the command exits. `--net`
lets the in-guest image pull reach the registry, which an ephemeral run repeats
on every invocation — add `--oci-cache` to bake the pulled image into a
reusable host artifact that later runs rehydrate from without pulling.

## Interactive Alpine shell

```bash
smolvm machine run --net -it --image alpine -- /bin/sh
```

Inside the VM:

```sh
apk add git
git --version
exit
```

## Restrict network egress

```bash
smolvm machine run \
  --net \
  --image alpine \
  --allow-host registry.npmjs.org \
  -- wget -q -O /dev/null https://registry.npmjs.org
```

Networking is off unless `--net` is set. The allow-list limits the enabled network path to the declared host.

## Persistent Python environment

```bash
smolvm machine create \
  --name pydev \
  --image python:3.12-alpine \
  --net
smolvm machine start --name pydev
smolvm machine exec --name pydev -- pip install requests
smolvm machine exec --name pydev -- \
  python3 -c "import requests; print(requests.__version__)"
smolvm machine stop --name pydev
```

Start the same machine later:

```bash
smolvm machine start --name pydev
smolvm machine exec --name pydev -- \
  python3 -c "import requests; print(requests.__version__)"
```

## Run code from a host directory

```bash
smolvm machine run \
  --image python:3.12-alpine \
  --volume "$PWD:/app" \
  -- python3 /app/main.py
```

The guest can read and write the mounted host directory. Do not use sensitive host directories with untrusted code.

## Copy code into a persistent machine

```bash
smolvm machine create --name job --image python:3.12-alpine
smolvm machine start --name job
smolvm machine cp ./job.py job:/workspace/job.py
smolvm machine exec --name job -- python3 /workspace/job.py
smolvm machine cp job:/workspace/result.json ./result.json
smolvm machine stop --name job
```

Use a volume mount instead of `machine cp` for transfers at or above 4 GiB.

## Run a locally built OCI image

```bash
docker build -t myapp .
docker save myapp | smolvm machine run --image - -- ./app
```

Or save the archive first:

```bash
docker save myapp -o myapp.tar
smolvm machine run --image ./myapp.tar -- ./app
```

smolvm boots the image as a VM. It does not build Dockerfiles.

## Pack a preinstalled runtime

```bash
smolvm pack create --image python:3.12-alpine -o ./python312
./python312 run -- python3 --version
```

See [Pack and .smolmachine CLI](/docs/local/pack-and-smolmachine-cli) for stopped-machine packing and persistent machines created from artifacts.

## Stream a long-running command

```bash
smolvm machine start --name pydev
smolvm machine exec --stream --name pydev -- python3 /workspace/train.py
```

`--stream` prints output as it arrives.

## Forward the host SSH agent

```bash
ssh-add -l
smolvm machine run \
  --ssh-agent \
  --net \
  --image alpine \
  -- sh -c "apk add -q openssh-client && ssh-add -l"
```

Private key material stays in the host agent, but the guest can request signatures while the forwarded socket is available. Use this only with workloads you trust.

## Publish a guest port

```bash
smolvm machine run \
  --net \
  --image python:3.12-alpine \
  --port 8000:8000 \
  -- python3 -m http.server 8000
```

The service is reachable through host port 8000 while the ephemeral machine is running.

## Clean up

```bash
smolvm machine stop --name pydev
smolvm machine delete --name pydev
smolvm machine delete --name job
```

Use `machine stop` when you want to keep disk state. Use `machine delete` when you want to remove the named machine.

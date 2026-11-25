---
title: Use Tailscale in a smol machine
---

# Use Tailscale in a smol machine

Join a machine to your [Tailscale](https://tailscale.com) network (your tailnet) as a device of its own. The machine keeps its login across stop and start, its ports stay closed until you open them, and it leaves the tailnet cleanly.

The steps were tested on macOS with smolvm v1.37.1, with Tailscale 1.86.2 on Alpine 3.22 and 1.104.7 on Debian trixie.

## Before you start

- [Install smolvm](/docs/local).
- Make an [auth key](https://tailscale.com/docs/features/access-control/auth-keys) on the Keys page of Tailscale's admin console. Turn on **Ephemeral**, so that Tailscale removes the machine some time after it goes offline, and give the key a [tag](https://tailscale.com/docs/features/tags), so that your access rules decide what the machine may reach. Make it reusable only if several machines will log in with it.

## Create the machine

```bash
smolvm machine create --name ts --image alpine:3.22 --mem 1024 --cpus 2 \
  --guest-subnet 10.200.0.0/30 --block-private \
  --init 'apk add --no-cache tailscale' \
  -- tailscaled --state=/var/lib/tailscale/tailscaled.state
smolvm machine start --name ts
```

- `--guest-subnet` moves the machine's link out of Tailscale's range. On the default link Tailscale drops the replies of the gateway at `100.96.0.1`, so every name stops resolving after the join (`bad address`), with either `--accept-dns` value. It is [set at create time](/docs/local/machine-lifecycle-cli-reference#moving-the-guest-off-the-default-range), and several machines can use the same value.
- `--block-private` keeps the machine off your local network, the host's loopback and [the host's own tailnet](#when-the-host-runs-tailscale), while the public internet and the machine's own Tailscale connection work.
- The command after `--` runs on every `machine start`, so `tailscaled` comes back with the machine. If it is killed inside the machine, it stays down until the next start.

For Debian, save this as `ts.smolfile`:

```toml
image = "debian:trixie-slim"
cpus = 2
memory = 1024
net = true
env = ["TS_DEBUG_FIREWALL_MODE=nftables"]
entrypoint = ["tailscaled", "--state=/var/lib/tailscale/tailscaled.state"]

[network]
block_private = true

[dev]
init = [
  "apt-get update -qq",
  "apt-get install -y -qq ca-certificates curl",
  "curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg",
  "curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list",
  "apt-get update -qq",
  "apt-get install -y -qq tailscale",
]
```

The `env` line clears a `connmark` warning that Debian's iptables causes. The guest subnet has no Smolfile field, so it stays on the command line:

```bash
smolvm machine create --name ts -s ts.smolfile --guest-subnet 10.200.0.0/30
smolvm machine start --name ts
```

## Join the tailnet

Read the key into your shell. Run this line by itself, paste the key and press Enter:

```bash
read -rs TS_AUTHKEY
```

Send it over standard input to a file in the machine's `/run`, which is in memory, then log in and delete the file:

```bash
printf '%s' "$TS_AUTHKEY" | smolvm machine exec -i --name ts -- sh -c 'umask 077; cat > /run/ts.key'
unset TS_AUTHKEY
smolvm machine exec --name ts -- tailscale up --auth-key=file:/run/ts.key --hostname=ts --shields-up --accept-routes=false
smolvm machine exec --name ts -- rm -f /run/ts.key
smolvm machine exec --name ts -- tailscale status
```

The login is now on the machine's disk, and `machine stop` and `start` need no key. The other ways to hand over the key are worse or fail:

- A key given as an argument to `machine exec` is written to the machine's `agent-console.log` on the host.
- `--secret-env` and Smolfile `[secrets]` leave the key in the environment of the machine's processes, and `machine start` fails when the host variable is missing.
- `--credential` does not reach Tailscale's login. `tailscale up` sends the placeholder and fails with `invalid key: unable to validate API key`.

## Reach the machine, and the tailnet from it

`--shields-up` blocks every connection from the tailnet. Open the machine when it has something to serve, here a test page on Alpine:

```bash
smolvm machine exec --name ts -- tailscale set --shields-up=false
smolvm machine exec --name ts -- sh -c 'apk add -q --no-cache busybox-extras; mkdir -p /srv/w; echo hello > /srv/w/index.html; httpd -p 8080 -h /srv/w'
```

On another device in the tailnet that your access rules allow, `curl http://ts:8080/` prints `hello`. No published port is needed. `tailscale set --shields-up=true` closes the machine again.

The other direction works with the shields up. Use a device's tailnet name, and `curl` on Debian:

```bash
smolvm machine exec --name ts -- wget -T 12 -qO- http://OTHER-DEVICE:8080/
```

## Leave the tailnet

```bash
smolvm machine exec --name ts -- tailscale logout
```

Run `tailscale status` on another device. When `ts` is no longer listed, delete the machine:

```bash
smolvm machine stop --name ts
smolvm machine delete --name ts --force
```

A machine deleted first stays listed as offline until Tailscale [removes it](https://tailscale.com/docs/features/ephemeral-nodes), about an hour later in our tests. The one machine we left stopped that long came back logged out, so it needs a new key.

## Copies of a joined machine

Do not run two copies of a joined machine. A [branch or a restored checkpoint](/docs/introduction/concepts/forks-and-snapshots) of it is the same device: the same node key, name and tailnet address. Both say `Running` and online, and after a branch the original keeps answering, so nothing looks wrong. When the original's `tailscaled` stops, the copy answers in its place. `tailscale logout` in the copy removes the original from the tailnet too.

Logging out before you branch does not help. The machine key stays in the state file, so a machine and its branch that both log in again become one device.

To branch safely, branch a machine that has never logged in. Create it as above, start it with `smolvm machine start --name ts --branchable`, and branch it with `smolvm machine branch --from ts --name ts-2`. Then log in on each machine with its own `--hostname`.

To turn a branch of a joined machine into a device of its own, delete its state and restart it. On Alpine:

```bash
smolvm machine exec --name ts-2 -- sh -c 'pkill tailscaled; sleep 1; rm -rf /var/lib/tailscale/*'
smolvm machine stop --name ts-2
smolvm machine start --name ts-2
```

Then log in there with a key and a new `--hostname`. Until its state is gone, the branch is the original.

A checkpoint of a joined machine holds its login, so keep the file as private as the key.

## When the host runs Tailscale

If your computer is on the tailnet, a machine with `--net` that never joined reaches the tailnet too, by address and by name. Its traffic leaves as the host, so the host's access rules apply to it. This holds on both the `tsi` and `virtio-net` backends.

`--block-private` closes it. So does `--guest-subnet 10.200.0.0/30 --deny-cidr 100.64.0.0/10 --deny-cidr fd7a:115c:a1e0::/48`, which leaves your local network open. Deny both ranges: the first is the tailnet's IPv4 addresses, the second its IPv6 addresses, and with only the first denied the IPv6 side stays open. Use one of them on any machine that should not reach your devices. A joined machine keeps its own tailnet connection with either.

On such a host, a plain `--net` machine also inherits the host's `100.100.100.100` resolver and loses every name when it joins. `--guest-subnet` fixes that too.

## Limits

- Linux and Windows hosts and smol cloud were not tested, nor were exit nodes, subnet routes, Serve, Funnel and Tailscale SSH.
- `--allow-host tailscale.com` is not enough. In our one test the join succeeded but another device could not reach the machine, because Tailscale dials its relays by address and a host list does not open those.
- With `--block-private`, the connection we looked at went through Tailscale's relays.

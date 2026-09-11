---
title: Kubernetes in a microVM
---

# Kubernetes in a microVM

smolvm supports two Kubernetes layouts. They solve different problems:

| Layout | Boundary | Use it for |
|---|---|---|
| VM per pod | A containerd shim starts each selected pod as its own smolvm | Hardware isolation between Kubernetes pods |
| Cluster in one machine | k3s or k3d runs entirely inside one smolvm | Disposable local clusters, CI, and reproducible control-plane tests |

## VM per pod

The experimental smolvm containerd-shim-v2 integrates with an existing Kubernetes cluster. Kubernetes remains outside smolvm. Pods that select the smolvm runtime are launched as separate microVMs.

Define a Kubernetes `RuntimeClass` after installing and configuring the shim on each eligible node:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: smolvm
handler: smolvm
```

Select it from a pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: isolated
spec:
  runtimeClassName: smolvm
  containers:
    - name: app
      image: alpine:3.20
      command: ["sh", "-c", "uname -a && sleep 3600"]
```

This mode changes the pod runtime. It does not place the Kubernetes control plane inside a microVM. The shim was introduced in smolvm v1.6.0 and validated with k3s.

### Installing the shim on a node

The Linux release carries the shim and the manifests, so there is nothing to
build. Extract the tarball on each node that should run microVM pods, which
needs KVM, and install from inside it:

```bash
sudo ./kubernetes/install-k8s-runtime.sh --runtime-dir .
sudo systemctl restart containerd
kubectl label node <node> smolvm-runtime=true
```

`--runtime-dir` points at a directory holding the smolvm runtime artifacts,
which is the extracted release itself. Without it the script stops with
`install incomplete` rather than leaving a half-installed node. The script also
prints the containerd configuration to apply, registering the runtime under the
name `smolvm` with `runtime_type = io.containerd.smolvm.v2`.

Then register the class and run the example pod:

```bash
kubectl apply -f kubernetes/runtimeclass.yaml
kubectl apply -f kubernetes/example-pod.yaml
kubectl logs smolvm-hello
```

The pod prints the guest's own kernel, which is what shows it is a real VM. The
shipped `RuntimeClass` also carries a `nodeSelector` for `smolvm-runtime=true`
and a per-pod overhead of 250m CPU and 160Mi memory, so the scheduler accounts
for the VM.

::: warning Two node conditions stop pods from starting
The released shim cannot start a sandbox on containerd 2.3 or later, so the pod
stays pending with a shim error; the node has to be on an earlier containerd.
On a node that enforces AppArmor, the shipped example pod fails with
`AppArmor is not initialized correctly`, because containerd stamps the node's
profile into a spec the guest kernel cannot honour. A pod that opts out of the
host profile runs as expected on such a node:

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/hello: unconfined
```

The microVM remains the isolation boundary either way. Both conditions are
open in smolvm.
:::

Treat this as an integration to evaluate in a test cluster before production.

## Cluster in one machine

This layout puts the control plane, kubelet, container runtime, and workloads inside one smolvm. The guest owns its kernel, cgroup v2 hierarchy, netfilter rules, mounts, and overlayfs.

Start from the maintained Docker-in-VM example:

```bash
git clone https://github.com/smol-machines/smolvm.git
cd smolvm

smolvm machine create --name k8s \
  -s examples/docker-in-vm/docker.smolfile \
  --net-backend virtio-net
smolvm machine start --name k8s
```

Install k3d and kubectl, then start Docker with its data on the ext4 storage disk:

```bash
smolvm machine exec --name k8s -- sh -c '
  apk add --no-cache curl kubectl
  arch=$(uname -m | sed "s/aarch64/arm64/;s/x86_64/amd64/")
  curl -sSL \
    "https://github.com/k3d-io/k3d/releases/latest/download/k3d-linux-${arch}" \
    -o /usr/local/bin/k3d
  chmod +x /usr/local/bin/k3d
  mkdir -p /storage/docker
  dockerd --data-root=/storage/docker --storage-driver=overlay2 \
    >/tmp/dockerd.log 2>&1 &
  for i in $(seq 1 30); do
    docker info >/dev/null 2>&1 && exit 0
    sleep 1
  done
  exit 1
'

smolvm machine exec --name k8s -- k3d cluster create dev --no-lb
smolvm machine exec --name k8s -- kubectl get nodes
```

Pin the k3d version in CI instead of downloading `latest`. Add k3d and kubectl to your own Smolfile when this becomes a repeated workflow.

## Two required runtime details

### `/dev/kmsg`

Kubelet opens `/dev/kmsg` at startup. smolvm includes the kernel log character device, major 1 minor 11, in the container device set. Without it, nested k3s or k3d nodes fail before reaching `Ready`.

The device exposes only the guest kernel's log. Neighboring smolvms have separate kernels.

### Docker storage on ext4

The machine root filesystem is already overlayfs. Docker's `overlay2` cannot use that overlay as its upper backing filesystem. Put Docker data on the ext4 storage disk at `/storage/docker`:

```bash
dockerd --data-root=/storage/docker --storage-driver=overlay2
```

On local machines, binding `/storage/docker` to `/var/lib/docker` also works, but the bind mount must be applied after each machine start. Pointing `dockerd` directly at `/storage/docker` avoids that requirement and works when separate exec calls use separate mount namespaces.

## Isolation and lifecycle

Containers inside the nested cluster can receive the capabilities Kubernetes needs because the hypervisor is the security boundary. Root inside the cluster still receives every mount, port, network route, socket, and credential explicitly passed to the machine.

Use `machine run` for a one-off cluster job. Use a persistent machine when cluster state should survive stop and start. For repeated CI jobs, prepare one cluster, start it as branchable, and branch clean workers from that source state. A branch is tied to the same host and architecture; use a `.smolmachine` pack for a portable cold artifact.

---
title: Run Node.js
---

# Run Node.js

Use the local CLI for scripts and development commands. Use the Node SDK when an application needs to create and control machines.

## Run Node.js from the local CLI

This starts an ephemeral microVM from the official Node image and deletes it when the command exits:

```bash
smolvm machine run --image node:22-alpine -- \
  node -e "console.log(2 ** 10)"
```

Package downloads require networking. Restrict egress to the registry when that is the only destination:

```bash
smolvm machine run --net --allow-host registry.npmjs.org \
  --image node:22-alpine -- \
  npm view typescript version
```

For repeated work, use a persistent machine:

```bash
smolvm machine create --name node-dev --net --image node:22-alpine
smolvm machine start --name node-dev
smolvm machine exec --name node-dev -- npm install -g pnpm
smolvm machine exec --name node-dev -- node --version
smolvm machine stop --name node-dev
```

Installed packages and filesystem changes survive stop and start. Delete the machine when it is no longer needed:

```bash
smolvm machine delete --name node-dev
```

## Run Node.js from the SDK

Install the SDK:

```bash
npm install smolmachines
```

The local transport embeds the smolvm engine in the Node process. It does not require `smolvm serve`.

```typescript
import { Machine } from "smolmachines";

const machine = await Machine.create(
  {
    resources: { cpus: 2, memoryMb: 1024, network: false },
  },
  { target: "local" },
);

try {
  const result = await machine.run(
    "node:22-alpine",
    ["node", "-e", "console.log(2 ** 10)"],
  );
  result.assertSuccess();
  console.log(result.stdout);
} finally {
  await machine.delete();
}
```

For a cloud machine, pass `{ target: "cloud" }` as the second argument to `Machine.create` and set `SMOL_CLOUD_TOKEN`; see [Use SDK on Cloud](/docs/sdk/with-cloud) for lifecycle and readiness details.

## Run a local project

Mount only the directory the guest needs:

```bash
smolvm machine run --image node:22-alpine \
  --volume "$PWD:/app:ro" -- \
  sh -c "cd /app && node index.js"
```

Use a writable mount only when the workload must change host files. A mounted directory is intentionally available to guest code and is outside the machine's disposable filesystem.

## Prebuild the runtime

Create a reusable artifact when image pulls or dependency setup dominate runtime:

```bash
smolvm pack create --image node:22-alpine -o node22
./node22 run -- node --version
```

For project-specific dependencies, define the image, initialization commands, resources, and entrypoint in a Smolfile, then create a pack from that file.

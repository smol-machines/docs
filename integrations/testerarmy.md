---
title: e2e by TesterArmy
---

# e2e by TesterArmy

Run TesterArmy e2e web tests with smol machines as the browser provider.

- **Package:** [`@e2e-dev/smol`](https://www.npmjs.com/package/@e2e-dev/smol), 0.1.x
- **Code:** [`packages/smol`](https://github.com/tester-army/e2e/tree/main/packages/smol) in TesterArmy's e2e repository, written by smol machines
- **Runs on:** the local engine, on the computer that runs the tests
- **Issues:** the provider on [e2e issues](https://github.com/tester-army/e2e/issues), the machines on [smolvm issues](https://github.com/smol-machines/smolvm/issues)

[e2e](https://github.com/tester-army/e2e) is TesterArmy's open-source end-to-end testing framework for web and mobile apps. Its `@e2e-dev/smol` package is a browser provider that runs each web test attempt in a smol machines microVM.

Each worker slot boots one warm Chromium machine. By default every test attempt runs in a copy-on-write branch of that machine, ready in about a second, and the branch is deleted when the attempt ends. A retry starts from the same browser state as the first try.

## When to use it

- **Retries that start clean.** An attempt cannot leave cookies, storage or open pages behind for the next one.
- **Sign in once per worker.** A `prepare` step signs the warm browser in before it is branched, so every attempt starts signed in.
- **Per-attempt app data.** With the app running inside the machine, each attempt gets its own copy of the running app and its files, a local database included.
- **Nothing to sign up for.** The machines run on the test runner with the local engine. No account or API key is needed.

## Requirements

- macOS on Apple Silicon, or Linux with KVM (`/dev/kvm`). See [Supported platforms](/docs/introduction/concepts/supported-platforms).
- Node.js and an e2e project with a web target.

The first boot pulls the Playwright Ubuntu image, so it takes longer than later runs.

## Set up

Install the provider and the smol machines SDK:

```bash
npm install --save-dev @e2e-dev/smol smolmachines
```

Set the web target's browser to `smol()`:

```typescript
import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';
import { smol } from '@e2e-dev/smol';

export default {
  targets: [
    {
      name: 'web',
      engine: web({ browser: smol({ hostPorts: [3000] }) }),
      app: {
        url: 'http://localhost:3000',
        command: { executable: 'npm', args: ['run', 'dev'] },
      },
    },
  ],
  workers: 4,
} satisfies E2EConfig;
```

Inside the machine, `localhost` is the machine itself. `hostPorts` lists ports on your computer that the browser reaches as its own `localhost`, so the app URL stays `http://localhost:3000`.

## Run the app in the machine

The provider's `app` option copies the app into each browser machine, runs its setup and start commands there, and waits for its port:

```typescript
smol({
  app: {
    source: '.',
    setup: 'npm ci && npm run db:seed',
    start: 'npm start',
    port: 3000,
    env: { DATABASE_URL: 'file:/app/dev.db' },
  },
})
```

With `app`, set the target's `app.url` to `http://localhost:<port>`, declare no `app.command`, and keep `port` out of `hostPorts`: the provider rejects a port in both. In the default attempt scope, every attempt's branch holds its own running app and data. The full field list, `prepare` for signing in, and the choice between attempt and worker scope are on the [provider page in the e2e docs](https://e2e.tester.army/docs/integrations/smol).

## What to know

- `hostPorts` is not an allowlist. The machine can reach any loopback port on your computer through `host.smolvm.internal`, and it has open outbound network access. See [Isolation, networking and credentials](/docs/introduction/concepts/isolation-networking-credentials).
- The browser's back/forward cache is off, so going back reloads the page.
- A killed runner, such as a cancelled CI job, can leave worker-scope machines behind, stopped, with names that start with `e2e-`. List them with `smol machine ls --local` and delete each with `smol machine rm --name <name> --yes`, using the [`smol` CLI](https://github.com/smol-machines/smol).

## Links

- [Provider reference in the e2e docs](https://e2e.tester.army/docs/integrations/smol)
- [`@e2e-dev/smol` 0.1.0 release notes](https://github.com/tester-army/e2e/releases/tag/%40e2e-dev%2Fsmol%400.1.0)
- [Forks and snapshots](/docs/introduction/concepts/forks-and-snapshots), the branching the provider builds on

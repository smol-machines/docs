---
title: smol ci
---

# smol ci

smol ci runs your existing GitHub Actions jobs on smol machines. You change one line in a workflow and nothing else:
your steps, test commands, caches and secrets stay as they are.

```yaml
jobs:
  test:
    runs-on: smol        # was: ubuntu-latest
```

## Get started

1. Open [ci in the console](/console/ci) and choose **add GitHub repositories**. GitHub asks which account and
   repositories the smol ci App may see, then brings you back to the console, which links the installation to your
   smol cloud account. Linking needs an owner of the account, since its jobs bill there.
2. In a workflow of a linked repository, change a job's `runs-on` to `smol` and push.

Jobs that keep a GitHub runner label are not affected. To change which repositories smol ci can see, use the App's
settings on GitHub (the console links to them).

## Labels

| label | what it does |
|---|---|
| `smol` | balanced: fans out and stays warm where that clearly pays off (the default) |
| `smol-fast` | as fast as smol ci can make the job: fans out as wide as helps, no cost cap, warm machines ready |
| `smol-cheap` | the lowest cost, and never slower than a GitHub-hosted runner: it fans out only where that costs little more than running serially, and otherwise runs the step serially, warm |
| `smol-arm64` | the balanced default, on arm64 machines |

smol ci picks the machine size, how wide to fan out, and when to keep warm machines ready. The labels only tell it how
to trade time for cost. Older fixed-size labels (`smol-4vcpu` and the like) still work and behave like `smol`.

## Runner environment

A job runs as it would on a GitHub-hosted runner, because it runs under GitHub's own runner agent.

| | |
|---|---|
| OS and architecture | Linux. `smol`, `smol-fast` and `smol-cheap` are x86_64 (`RUNNER_OS=Linux`, `RUNNER_ARCH=X64`, the same as `ubuntu-latest`, so cache keys built from them match); `smol-arm64` is arm64 (`RUNNER_ARCH=ARM64`). |
| Runner agent | GitHub's official Actions runner, registered for each job. GitHub gives the job its `GITHUB_TOKEN`, repository secrets, cache access and, with `permissions: id-token: write`, its OIDC token, as on a hosted runner. |
| Docker | `dockerd` runs on every job machine, with the `buildx` and `docker compose` plugins at the versions GitHub's runner image uses. `services:` containers (a Postgres for tests, say) and `container:` jobs work. |
| Caches | `actions/cache`, the `setup-*` actions' caches and the GitHub Actions build cache are GitHub's own; see [Caches on a warm machine](#caches-on-a-warm-machine). |
| Image | GitHub's `actions-runner` image plus the tools jobs written for `ubuntu-latest` usually expect. It is not the full `ubuntu-latest` image: if a step reports a command that `ubuntu-latest` has as missing, tell us and we add it. |
| Network | Outbound access is open, as on a hosted runner. |

## What happens automatically

- **Warm machines.** After a job succeeds, its finished machine is kept as that job's *golden*. The next run starts from
  a copy of it in about 5 seconds, with your dependencies, toolchains and build output already there. Your build tool's
  normal incremental build does the rest.
- **Sizing.** You don't pick a machine size. smol ci learns from each run what the job uses and sizes the next run to
  match: a job that saturates its machine gets more vCPUs, an idle one fewer.
- **Test fan-out.** When a step runs a test suite smol ci understands (pytest, jest, vitest, node --test, Django, go
  test, cargo, rspec, Maven, Gradle, dotnet, and `&&` chains, `make` and `just` targets that run them), it copies the
  machine at that moment into several machines, splits the tests across them by measured time, and merges the results
  into the step's log and exit code. It only forks when the measured times say forking is faster.
- **Parallel steps.** Later steps that only read your code (lint, separate test commands) can run ahead of time on a
  copy of the machine while an earlier step builds. A step is only used this way after two runs where the copy and the
  real step agreed on the exit code and test counts, and only while it is faster. The step still shows in its own place
  in the GitHub UI, with its own output.
- **Cold runs.** A run with no golden starts from a standing base machine (tools and Docker ready) and restores your
  `actions/cache` entries exactly as a GitHub-hosted runner would.
- **Cache problems are reported.** When a cache step finds nothing on a warm machine, warns, or fails to save, smol ci
  says so in the job summary and in the step's log: a cache that quietly stopped working is the usual reason a warm job
  turns slow.

## Caches on a warm machine

Leave your `actions/cache`, `setup-node`, `setup-python` and `setup-uv` cache steps exactly as they are. On a warm
machine smol ci serves a restore it has downloaded before from the machine's own copy of the archive, and an archive
this machine has already extracted leaves the newer files your last run built in place and restores only what is
missing. A restore that would take 30 to 70 seconds on a GitHub-hosted runner takes a few seconds here, and a new cache
key restores and saves as GitHub would.

Do not skip a cache step on `SMOL_WARM`: the variable says the machine is warm, not that the files your step expects
are where it expects them. Moving a build directory in the workflow strands every golden built before the move, and a
skipped restore then means a cold build with no cache at all.

## Security model

- Goldens are scoped like GitHub's cache. Runs of your default branch write goldens your default branch reads. A pull
  request from a branch of the repository reads the default branch's goldens but writes only goldens of its own: no
  pull request can change the machine your default branch builds on.
- A pull request from a fork reads no golden of the repository's own runs, whatever its branch is called: a golden is a
  whole machine, and what your own jobs leave on it (registry logins, `.npmrc`, cloud credential files) is what GitHub
  withholds from forks.
- Parallel-step proof is scoped the same way.
- Job machines are microVMs; nothing is shared between jobs except the goldens of the same scope.

### Pull requests from forks

On a public repository anyone can fork it and open a pull request, and its workflows then run their code on smol ci, as
they would on GitHub's hosted runners: on machines in your account, billed to you, with outbound network access. GitHub
gives those runs no repository secrets and a read-only token. The pull request can change the workflow files too, so
labels and steps do not limit what it runs.

GitHub decides which of those runs start (Settings, Actions, General, "Approval for running fork pull request workflows
from contributors"). Its default holds only first-time contributors for approval; "Require approval for all external
contributors" holds every pull request from someone without write access until a maintainer approves it, and is the one
to choose if you do not want strangers' code to run on your machines unseen. Private repositories are not affected:
only people with access can open pull requests there.

## Limits

- Linux jobs only (x86_64 and arm64). macOS and Windows jobs stay on GitHub-hosted runners.
- Jobs in a `container:` start from a clean workspace on a warm machine, so they build from scratch like on GitHub.
  Their test steps fork like any other job's when the image has bash at `/usr/bin/bash` (Debian- and Ubuntu-based
  images do; Alpine images without bash run as written).
- On arm64, a machine keeps the vCPUs it starts with: arm64 jobs start at their learned size and do not grow mid-job.
- A golden expires after 24 hours without a run.
- When smol cloud has no room for a job's machine, the job waits in the queue until it does; a test step forks to fewer
  copies, or runs as written when not even two fit.

## What you pay for

The time your job takes, per minute and billed per second, from its first step to its last. Everything smol ci uses to
make it fast is included: the machine sizes it picks, the copies a test step fans out to, warm starts and spare runners.
A job that finishes in a third of the time costs a third as much at the same rate.

- `smol` is billed at the standard rate.
- `smol-fast` is billed at a higher rate for the extra machines it runs.
- `smol-cheap` is billed at a lower rate: slower than `smol`, never slower than a GitHub-hosted runner.

Rates are on the [pricing page](/pricing).

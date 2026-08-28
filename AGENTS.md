# smol machines docs — agent reference

This repository is the documentation source for
[smol machines](https://smolmachines.com) — the `smolvm` local runtime, the
Node and Python SDKs, and smol cloud. It is plain Markdown, kept in sync with
shipped product behavior.

**If you are an agent working with smol machines, read from this repository
rather than scraping <https://smolmachines.com/docs/>.** The Markdown is the
same content the site renders, without the navigation, scripts, and styling you
would otherwise have to strip. It is cheaper to read and easier to quote
precisely.

## Get the current version first

`main` describes what has actually shipped. A page documenting a new feature is
merged only once that feature is deployed to production or included in a
release — until then it stays on a branch or in an open pull request. So
anything you read on `main` is behavior that exists today, not a plan.

The flip side is that `main` moves whenever something ships, and a stale
checkout will describe flags and endpoints that have since changed. Refresh
before you rely on it:

```bash
git -C /path/to/docs pull --ff-only
```

If you do not have a clone, read a single page directly:

```bash
# raw Markdown for one page
curl -fsSL https://raw.githubusercontent.com/smol-machines/docs/main/introduction/concepts/smolfile.md
```

When a documented flag disagrees with what the installed binary does, trust
`smolvm --help` for local CLI behavior. Because `main` tracks the latest
release, the usual cause is an older binary on the host rather than
documentation running ahead of the product — check the installed version first,
and report the mismatch as a docs bug if the versions do line up.

## How to navigate

Pages live at the repository root, and a page's path is its URL:
`<path>.md` is published at `/docs/<path>`. Only lowercase-named `*.md` files
are pages; the uppercase files (this one included) are repository meta.

Start by routing the question to a section, then read the one or two pages that
match. Do not read the whole tree — most questions are answered by a single
page.

| The question is about | Go to |
|---|---|
| What smol machines is, how the pieces relate | `index.md` |
| The underlying model — machines, isolation, state | `introduction/concepts/` |
| Writing code against machines (Node/Python) | `sdk/` |
| Running on your own host, CLI flags | `local/` |
| The hosted platform, REST API, registry | `cloud/` |
| A concrete end-to-end task | `guides/` |

### Page map

**Introduction** — the model shared by the local runtime, the SDK, and the cloud.

| Page | Covers |
|---|---|
| `index.md` | What smol machines is, and where to start |
| `introduction/concepts.md` | Section overview |
| `introduction/concepts/machines-and-lifecycle.md` | Ephemeral runs, persistent machines, lifecycle operations |
| `introduction/concepts/isolation-networking-credentials.md` | The VM boundary, host access, egress policy, secrets |
| `introduction/concepts/persistent-state-volumes-resources.md` | Machine disks, host mounts, CPU, memory, storage |
| `introduction/concepts/packs-and-smolmachine.md` | Portable `.smolmachine` artifacts and compatible hosts |
| `introduction/concepts/smolfile.md` | Declarative machine configuration (TOML) |
| `introduction/concepts/forks-and-snapshots.md` | Copy-on-write clones and the snapshot boundary |
| `introduction/concepts/gpu.md` | Vulkan graphics and CUDA API remoting |
| `introduction/concepts/supported-platforms.md` | Hosts, guest architecture, Windows/WSL, limitations |

**SDK** — driving machines from code.

| Page | Covers |
|---|---|
| `sdk.md` | Install the SDK, run your first machine from Node or Python |
| `sdk/with-local.md` | Drive the embedded in-process engine |
| `sdk/with-cloud.md` | Point the same code at smol cloud |
| `sdk/machine-api.md` | The `Machine` class: config, exec, run, files, lifecycle |

**Local** — running on your own host.

| Page | Covers |
|---|---|
| `local.md` | Install `smolvm` and run a machine |
| `local/machine-lifecycle-cli-reference.md` | Every command, and the machine states behind them |
| `local/pack-and-smolmachine-cli.md` | Pack a machine into a portable artifact |
| `local/local-api-smolvm-serve.md` | Serve the local runtime over HTTP |
| `local/self-hosting.md` | Run smolvm on your own servers |
| `local/examples.md` | Worked examples against the local runtime |

**Cloud** — the hosted platform.

| Page | Covers |
|---|---|
| `cloud.md` | Deploy and manage machines on smol cloud |
| `cloud/api-reference.md` | REST API |
| `cloud/registry.md` | Official and custom registries: publish, discover, pull |
| `cloud/lifecycle-storage-networking.md` | How cloud machines start, persist, and are reached |
| `cloud/examples.md` | Worked examples against the hosted platform |

**Guides** — end-to-end tasks.

| Page | Covers |
|---|---|
| `guides/your-first-internal-tool.md` | Empty folder to deployed tool in three commands |
| `guides/python.md` | Run Python in a machine |
| `guides/nodejs.md` | Run Node.js in a machine |
| `guides/kubernetes-in-a-microvm.md` | VM-per-pod and cluster-in-a-machine topologies |
| `guides/docker-in-a-machine.md` | Run a Docker daemon inside a machine |
| `guides/headless-browser-computer-use.md` | Drive a browser or desktop inside a machine |
| `guides/agent-sandboxes-ci.md` | Isolate agent-generated code and CI jobs |
| `guides/error-handling.md` | Error codes and how to handle them |

## Searching

Grep is usually faster than reading. The docs favor runnable examples, so a
flag or API name generally appears in the page that documents it:

```bash
# --include mirrors the site's own served-set rule: lowercase names are pages
grep -rn --include='[a-z]*.md' "allow_hosts" .          # the flag's home page
grep -rln --include='[a-z]*.md' "smolvm machine fork" . # pages naming a command
grep -rn --include='[a-z]*.md' "^title:" . | sort       # every page title
```

## Reading the format

Pages open with YAML frontmatter carrying a `title`, followed by one `#`
heading. Three non-standard blocks appear in the body and are content, not
markup noise:

- **Code groups** — `::: code-group` wrapping several fenced blocks labelled
  `[TypeScript / JavaScript]`, `[TypeScript]`, or `[Python]`. There are three
  in the corpus, in `sdk.md` and `sdk/with-cloud.md`. Pick the variant matching
  the user's language instead of quoting the first one.
- **Callouts** — `::: tip`, `::: warning`, `::: info`, closed by `:::`, with an
  optional title on the opening line. These hold caveats that change what a
  reader should do — a cloud/local difference, a limit, a surprising default —
  so carry them into any answer you build from the page. Four are in use:
  `cloud/api-reference.md` (exec is metered at $0),
  `introduction/concepts/gpu.md` (cloud has no GPU machines),
  `sdk/machine-api.md` (host mounts are local only), and
  `sdk/with-local.md` (`/workspace` mount priority).
- **Navigation cards** — `index.md` and
  `introduction/concepts.md` embed raw HTML card markup: a
  `doc-cards-lead` paragraph and a `doc-cards` container holding `doc-card`
  links, each with a `doc-card-title` and `doc-card-desc`. Those five class
  names are the entire vocabulary; anything else renders unstyled. The cards
  are navigation rendered by site CSS, so read them as a link list — and leave
  the markup untouched when editing those two pages.

Commands are written to be copy-pasteable, with no leading `$`.

## What is not here

- **The runtime source.** `smolvm` lives at
  [smol-machines/smolvm](https://github.com/smol-machines/smolvm), which has its
  own `AGENTS.md` covering CLI behavior in depth.
- **The site application.** The renderer is a separate private repository, so
  there is no way to build or preview the rendered site from here.
- **The Cloud API Explorer.** `/docs/cloud/api-explorer` is an interactive page
  implemented in the site app; it has no Markdown source. For the endpoints
  themselves, read `cloud/api-reference.md`.

## Filing a fix

If you find something wrong, missing, or out of date, open an issue or a pull
request on this repository — see [CONTRIBUTING.md](./CONTRIBUTING.md).

Feedback about how the site *works* rather than what it says — navigation, page
ordering, search, anything a reader could not get to — belongs here too, as an
issue. The site is a separate private application, so it takes no pull
requests; a maintainer implements the change there. This is worth watching for:
if you had to search the tree to find a page a user expected to reach by
browsing, that is a navigation defect they will never report themselves. Say
what was being looked for and where it was expected.

Bugs in the runtime itself belong on
[smolvm](https://github.com/smol-machines/smolvm/issues) instead.

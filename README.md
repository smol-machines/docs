# smol machines — documentation

Source for the documentation published at
**<https://smolmachines.com/docs/>**.

Everything in this repository is plain Markdown. You do not need to install a
toolchain, run a site, or touch application code to contribute — if you can
write Markdown, you can improve these docs.

Want to help? Start with **[CONTRIBUTING.md](./CONTRIBUTING.md)**.
Pointing an agent at these docs? See **[AGENTS.md](./AGENTS.md)**.

## Layout

```
content/
├── index.md                    # the docs landing page  →  /docs/
├── introduction/
│   ├── concepts.md             # →  /docs/introduction/concepts
│   └── concepts/*.md           # →  /docs/introduction/concepts/<name>
├── sdk.md                      # section landing page   →  /docs/sdk
├── sdk/*.md                    # →  /docs/sdk/<name>
├── cloud.md
├── cloud/*.md
├── local.md
├── local/*.md
└── guides/*.md                 # →  /docs/guides/<name>
```

A file at `content/<path>.md` is served at `/docs/<path>`, and folders nest:
`content/introduction/concepts/gpu.md` becomes
`/docs/introduction/concepts/gpu`. The one special case is `content/index.md`,
which is the `/docs/` landing page.

## Sections

| Folder | Section | Landing page |
|---|---|---|
| `introduction/` | Introduction | `index.md`, served at `/docs/` |
| `sdk/` | SDK | `sdk.md` |
| `cloud/` | Cloud | `cloud.md` |
| `local/` | Local | `local.md` |
| `guides/` | Guides | none — the group is a label only |

## Page format

Each page starts with YAML frontmatter carrying a `title`, followed by a single
top-level heading:

```markdown
---
title: Smolfile
---

# Smolfile

A Smolfile is a TOML file that describes a machine environment.
```

Beyond standard Markdown, two extensions are available — callouts
(`::: tip`, `::: warning`, `::: info`) and tabbed code groups
(`::: code-group`). [CONTRIBUTING.md](./CONTRIBUTING.md) shows both.

## What lands on `main`

`main` describes what has actually shipped. Documentation for a feature is
merged only once that feature is deployed to production or included in a
release; until then it stays on a branch or as an open pull request.

That means `main` never describes a flag, endpoint, or command you cannot use
yet — and that unreleased work is still visible, as open pull requests, if you
want to see what is coming.

## Using these docs with an agent

This repository is meant to be read by coding agents and AI assistants working
with smol machines, not just by people. Point your agent here instead of at the
website: the Markdown is the same content the site renders, without the
navigation, scripts, and styling it would otherwise have to strip out — cheaper
to read, and easier to quote precisely.

It is also the most current description of the product. The docs are synced
with new developments and deployments, and — as described in
[What lands on `main`](#what-lands-on-main) — a page is merged only once the
feature it documents is live. A fresh `git pull` reflects what actually
shipped, not what is planned.

**[AGENTS.md](./AGENTS.md)** is written for that audience: how to refresh
before relying on the content, how to route a question to the right section,
and a page-by-page map of what each file covers.

## Where the site itself lives

The renderer — a [SvelteKit](https://svelte.dev/docs/kit) app using
[mdsvex](https://mdsvex.pngwn.io/) — lives in a separate, private repository
alongside the dashboard and console. Two consequences worth knowing before you
open a pull request:

- There is no local rendered preview from this repository. Review your change
  as Markdown — a maintainer checks that it renders correctly before merging.
- The sidebar navigation is wired in the site app, so a maintainer registers
  new pages. Say where a new page belongs in your PR description and it gets
  handled during review.

Merged changes are mirrored into the site and go live on its next deploy.

## Reporting problems

- **Something wrong, unclear, or missing in the docs** — open an issue here.
- **A bug or feature request for the runtime itself** — open it on
  [smolvm](https://github.com/smol-machines/smolvm/issues) instead.

## License

Documentation in this repository is licensed under the
[Apache License 2.0](./LICENSE), matching
[smolvm](https://github.com/smol-machines/smolvm).

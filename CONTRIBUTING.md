# Contributing to the smol machines docs

Thanks for helping improve the docs. This repository holds the Markdown behind
<https://smolmachines.com/docs/> — nothing else. There is no build to run and
no toolchain to install: every change here is a Markdown change.

Because this repository is Markdown only, **you will not be able to render a
preview of the website when you submit your pull request.** That is expected,
and it is not something you need to solve. Write and review your change as
Markdown; a maintainer checks that it renders correctly on the site before
merging it.

If you are using an AI assistant to help write docs, point it at
[AGENTS.md](./AGENTS.md) — it maps the page tree and explains the format.

## What belongs here

- **Yes** — corrections, clearer explanations, missing detail, new guides,
  reference pages, better examples, broken links, typos.
- **No** — bugs or feature requests for the runtime. Those belong on
  [smolvm](https://github.com/smol-machines/smolvm/issues).

If you are planning something substantial — a new page, or restructuring an
existing one — open an issue first so we can agree on shape and placement
before you write it. Small fixes need no preamble; just send the pull request.

## When your change gets merged

Documentation lands on `main` only once the thing it describes is real:
**a page covering a new feature is merged after that feature is deployed to
production or included in a release.** Until then it stays on a branch or as an
open pull request.

So there are two kinds of contribution, and they move at different speeds:

- **Documenting something already shipped** — a correction, a clearer
  explanation, a new guide for existing behavior. Reviewed and merged on its
  own schedule.
- **Documenting something not yet released** — the pull request is reviewed
  normally, then held open until the feature ships, and merged alongside it.
  If yours falls into this category we will say so on the pull request, so an
  open PR is not a stalled one.

This is what keeps `main` trustworthy: every page on it describes behavior a
reader can actually use today.

## Quick start

You cannot push directly to this repository, so all changes arrive as pull
requests from a fork.

For a typo or a paragraph, the fastest route is GitHub's own editor: open the
page, press **`.`** or click the pencil icon, edit, and choose
*Create a new branch and start a pull request*.

For anything larger:

1. **Fork** this repository and clone your fork.
2. Create a branch: `git checkout -b docs/short-description`.
3. Edit the relevant page (pages live at the repository root).
4. Commit, push to your fork, and open a pull request against `main`.

## How files map to pages

A file at `<path>.md` is served at `/docs/<path>`:

| File | URL |
|---|---|
| `index.md` | `/docs/` |
| `local.md` | `/docs/local` |
| `introduction/concepts/smolfile.md` | `/docs/introduction/concepts/smolfile` |

Page filenames must start with a lowercase letter — the site publishes only
lowercase `*.md` files, which is how the uppercase repository files
(`README.md`, this file, `AGENTS.md`) stay out of the docs.

## Page format

Every page opens with frontmatter containing a `title`, then a single `#`
heading matching it:

```markdown
---
title: Your first internal tool
---

# Your first internal tool

This guide is for the person replacing a spreadsheet with a small web tool.
```

The `title` drives the sidebar, search, and the page's `<title>`. Use one `#`
per page and `##` / `###` for everything below it.

### Callouts

```markdown
::: tip
Networking is off by default; add `--net` when the workload needs it.
:::
```

`tip`, `warning`, and `info` are supported.

### Code groups

Use a code group when the same step differs per language or platform:

````markdown
::: code-group
```bash [TypeScript / JavaScript]
npm install smolmachines
```
```bash [Python]
pip install smolmachines
```
:::
````

## Adding a new page

1. Create `<section>/<your-page>.md` with `title` frontmatter (lowercase
   filename).
2. In your **pull request description**, say which section it belongs in, the
   sidebar label, and a one-line summary of the page.

That last step matters: the navigation tree lives in the site application, not
in this repository, so a maintainer wires the page into the sidebar, search,
and sitemap during review. Without it, the file merges but the page stays
unlisted.

## Images

Reference images from the site root — `![Diagram](/your-image.png)`. Static
assets are served from the site application, so attach new images to the pull
request and a maintainer will place them.

## Style

- Short sentences. Runnable examples over description.
- Show the command, then say what it does — not the other way around.
- Keep CLI examples copy-pasteable: no leading `$`, no shell prompt.
- Prefer the concrete over the abstract. A real command with real flags beats a
  paragraph about what the command could do.
- Write for someone who has not read the surrounding pages.

## Before you open a pull request

You cannot preview the rendered page, and there is no CI here, so a quick
manual pass over the Markdown counts for a lot:

- [ ] Frontmatter present, with a `title`.
- [ ] Exactly one `#` heading, matching the title.
- [ ] Code fences are tagged with a language, and commands actually run as
      written.
- [ ] Links use site paths — `/docs/...` for docs pages, and site-root paths
      like `/pricing` or `/console` for the rest of the website. Never link a
      `.md` filename.
- [ ] New page? The PR description names its section, label, and summary.
- [ ] The change is focused on one topic — it makes review much faster.

## After you open it

A maintainer reviews the copy, builds it against the site to confirm it renders
correctly, and wires up any navigation — so anything that only shows up in the
rendered page gets caught on our side, not yours. If the change documents
unreleased behavior, the pull request is held open until that feature ships,
per [When your change gets merged](#when-your-change-gets-merged). Once merged, the change is mirrored into the site repository and
ships on its next deploy — so there is a short delay between merge and the page
appearing at smolmachines.com.

## Licensing of contributions

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](./LICENSE), the same license as the rest of this
repository. There is no CLA to sign.

## Notes for maintainers

The docs pin the released version in several places — the Machine API
introduction, the SDK quick start's example links, the local quick start's
Windows step, and the local examples introduction. On a release, grep the old
version and bump them together, alongside the curated `llms.txt` index in the
site repository.

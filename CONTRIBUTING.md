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

- **Yes, as a pull request** — corrections, clearer explanations, missing
  detail, new guides, reference pages, better examples, broken links, typos.
- **Yes, as an issue** — anything about how the docs site *works* rather than
  what it says: navigation and page ordering, search, the sidebar, layout,
  readability, mobile, or anything you found hard to get to. The site itself is
  a separate private application, so you cannot send a pull request for it —
  but the feedback lands here and a maintainer implements it there. Say what
  you were trying to find and where you expected it; that is more useful than a
  proposed fix.
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

Use a callout for something a reader must not miss — a default that surprises,
a limit, a difference between local and cloud. Three types:

```markdown
::: tip
Networking is off by default; add `--net` when the workload needs it.
:::

::: warning Hosted cloud does not provide GPU machines
The cloud create API has no GPU resource fields.
:::

::: info
Optional background that is useful but not required reading.
:::
```

An optional title follows the type on the opening line, as in the `warning`
above; with no title the type name is used. Close every callout with `:::`.

- `tip` — a shortcut, a better default, a thing worth knowing.
- `warning` — a constraint or a surprise. Something that will cost the reader
  time if they miss it.
- `info` — context that helps but is not required.

Only these three render. `::: danger` and other types pass through as literal
text. Keep callouts short and rare: a page where everything is a callout has no
emphasis left. Prefer one per section at most, and never open a page with one —
lead with a sentence that says what the page is.

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

The label in brackets names the tab. Keep labels consistent with the ones
already in use: `[TypeScript / JavaScript]`, `[TypeScript]`, `[Python]`.

### Blockquotes

```markdown
> Machines are the unit of isolation: one workload, one kernel.
```

Use a blockquote to set off quoted or definitional text. For a caveat, reach
for a `warning` callout instead — it is the stronger signal and it is styled
for the purpose.

### Tables

Tables are the house device for anything structured, and most reference pages
are built from them. Follow the shapes already in use rather than inventing new
ones:

| Shape | Columns | Example |
|---|---|---|
| API routes | Method, Path, Description | `cloud/api-reference.md` |
| SDK surface | TypeScript, Python, Target, Description | `sdk/machine-api.md` |
| Support matrix | Host, Guest, Mechanism, Status | `introduction/concepts/supported-platforms.md` |
| Codes | Code, Meaning | `guides/error-handling.md` |

Keep cells short. A cell that needs a paragraph belongs in prose under the
table.

### Code fences

Always tag a fence with a language. Ten are highlighted:

```
bash  javascript  typescript  json  toml  python  rust  text  shell  markdown
```

Anything outside that list — `yaml` and `http` included — **renders as
unstyled plain text**. It does not fail the build and it looks fine in your
editor, so it is easy to miss. Use `text` deliberately when no listed language
fits, and open an issue if a language is worth adding.

Keep commands copy-pasteable: no leading `$`, no shell prompt.

### Headings and links

Use `##` and `###` only. The corpus has no `####`; if a page needs one, it
probably wants splitting.

Every heading gets an automatic anchor, so link within a page with
`[Cloud volumes](#cloud-volumes)`. The slug is the heading lowercased, with
everything that is not a letter, number, space or hyphen removed, and spaces
turned into hyphens — so ``### `Machine.create` `` becomes `#machinecreate`,
not `#machine-create`. Link to another page with a site path
(`/docs/sdk/machine-api`), never a `.md` filename.

### What not to use

Pages are plain Markdown so they stay portable. Do not add Svelte components,
imports, or raw HTML — the one exception is the navigation-card markup in
`index.md` and `introduction/concepts.md`, whose five classes (`doc-cards-lead`,
`doc-cards`, `doc-card`, `doc-card-title`, `doc-card-desc`) are the entire
vocabulary. Leave that markup as you find it.

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
per [When your change gets merged](#when-your-change-gets-merged).

Merging is what publishes. The merge tells the website to pull this repository
and deploy, so a page normally changes at smolmachines.com within a few minutes
with nobody touching anything.

A twice-daily job at 00:00 and 12:00 UTC exists behind that as a failsafe, for
the cases where the trigger itself fails. So the delay is minutes when things
are working and at most twelve hours when they are not. **If the page has not
changed after twelve hours, it is worth reporting**, because at that point both
paths have failed rather than one being slow.

The most likely cause of a failed sync is a new page that is not yet registered
in the site's navigation: the sync runs a check that the nav and the Markdown
agree, and an unregistered page fails it rather than shipping a URL that 404s.
That is why the section, sidebar label and one-line summary asked for in your
pull request description matter — they are what a maintainer registers it with.

## Licensing of contributions

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](./LICENSE), the same license as the rest of this
repository. There is no CLA to sign.

## Notes for maintainers

The docs pin the released version in two places — the SDK quick start's three
example links and the local quick start's Windows release link. On a release,
grep the old version and bump them together, alongside the curated `llms.txt`
index in the site repository. Keep prose un-pinned: a version number in a
sentence goes stale silently.

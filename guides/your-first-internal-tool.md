---
title: Your first internal tool
---

# Your first internal tool

This guide is for the person replacing a spreadsheet with a small web tool —
whether you write the code yourself or an AI assistant writes it for you. No
containers, no servers, no CI. Three commands take you from an empty folder to
a deployed tool your teammates can use.

## 1. Scaffold a working app

```bash
smol new tracker
cd tracker
```

This creates a small, working tracker app — a shared list with add and done
buttons — plus two files worth knowing about:

- `app.py` — the whole app, one file on purpose. Edit it freely, or point your
  AI assistant at it and describe the tool you actually need.
- `Smolfile` — how it runs: the base image, CPU and memory, and which port it
  serves on. It lives next to the code, so *how this deploys* is visible and
  reviewable like everything else.

Prefer JavaScript? `smol new tracker --template node`.

## 2. Run it on your machine

```bash
smol file up
```

Open [http://localhost:8000](http://localhost:8000). The app runs inside its
own microVM — an isolated machine with its own filesystem and its own network.
Nothing is installed on your laptop, and deleting the machine removes every
trace of it.

Edit the code, refresh the page. When you're done for the day, `smol file down`.

## 3. Put it online

```bash
smol cloud deploy
```

You get a URL — and here is the part that matters for anyone who has ever
worried about accidentally publishing something internal:

**The deployed app is private by default.** Nobody can open that URL without
signing in, and making it public is a separate, deliberate action that is
recorded in your account's audit trail. The default outcome of deploying is a
tool only you can reach — never an accidentally public one.

To let a teammate in without a smolmachines account, issue a share link from
the console or CLI; it grants access to exactly this one app and can be
revoked at any time.

## When the tool touches sensitive data

Two properties are worth knowing before you point a tool at anything
confidential:

- **You control exactly what it can reach.** A machine can be created with an
  allow-list — for example, only your internal ticket system — and everything
  else is refused at the virtualization layer, beneath the app. Refused
  attempts are recorded, so "what did this tool try to talk to?" has an
  answer.
- **It doesn't have to leave the building.** The same app, unchanged, runs on
  a machine in your office with `smolvm` and is reachable only on your LAN.
  For regulated data, the right deployment is often the one that never gets a
  public address at all — talk to your IT team about which tools belong where.

## Where to go next

- [Run Python](/docs/guides/python) and [Run Node.js](/docs/guides/nodejs) —
  more on the local CLI.
- [Cloud lifecycle, storage, networking](/docs/cloud/lifecycle-storage-networking)
  — what happens to your app's data across restarts.

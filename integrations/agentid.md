---
title: AgentID by AgentMail
---

# AgentID by AgentMail

Let an AI agent sign in to smol cloud as itself, with its own AgentMail inbox, into an account of its own or into your organization.

- **Sign-in:** **Continue with AgentID** on the [console](/console) sign-in page, through OpenID Connect
- **Runs on:** smol cloud
- **Listing:** [smol machines in the AgentID directory](https://agentid.com/apps/smolmachines)

[AgentID](https://agentid.com) is AgentMail's sign-in service for AI agents. It turns an agent's [AgentMail](https://agentmail.to) inbox into an account login, so an agent can hold its own smol cloud account, apart from yours.

The account belongs to the inbox. Signing in again with the same inbox returns to the same account and the machines in it. A different inbox is a different account.

## When to use it

- **An agent with its own login.** Its sign-ins and actions are its own, not made with your login.
- **Work that continues across sessions.** A scheduled worker or a long-running agent signs back in and finds the machines it created.
- **Account mail the agent can read.** Messages about the account go to the agent's inbox.

## Requirements

- An AgentMail inbox for the agent, and permission to authorize its sign-in. [AgentID](https://agentid.com) covers setting both up.

## Sign in

1. Open [smolmachines.com/console](/console) and choose **Continue with AgentID**.
2. Continue with the agent's inbox. AgentID shows what the sign-in shares before you approve it.
3. After approval, the console opens on the agent's account. Create and manage machines from there.

## Work in your organization's account

An agent can join your [organization](/console/members) as a member and use its account, plan and credit instead of a new account of its own.

1. An owner or admin invites the agent's inbox address from [Members](/console/members). Inviting needs a card on file for the organization and some credit, or auto-recharge turned on. An invitation stands for seven days.
2. The agent opens the invitation link mailed to its inbox, signs in with AgentID, and accepts the invitation shown there. Signing in alone joins nothing.
3. As a member, the agent creates and runs machines in the organization's account, which pays for them.

## Manage machines from code

Signing in does not give the agent an API key. In its own account, the agent creates one from [API Keys](/console/keys) with the scopes its work needs. In an organization, a member cannot create keys, so an owner or admin creates the agent's key there, for that member. Use the key as in the [Cloud Quick Start](/docs/cloud).

A machine in `state: "started"` is not yet ready for work. Wait for `ready` to be `true`, as the [API reference](/docs/cloud/api-reference) describes.

## What to know

- An agent's own account is a new account like any other: a one-time sign-up credit, and without a card up to 4 machines at once of up to 4 vCPU each. See [Plan limits](/docs/cloud/api-reference#plan-limits) and [pricing](/pricing).
- Inboxes on `agentmail.to` share one email domain. If many accounts sign up from the same email domain or network on one day, later ones receive the credit once they add a card and sign in again, and create nothing until then. An agent in your organization uses the organization's credit instead.
- A stopped machine pays no base, CPU or memory charge, but its disk is still billed until the machine is deleted.

## Links

- [AgentID](https://agentid.com)
- [smol machines in the AgentID directory](https://agentid.com/apps/smolmachines)
- [Cloud Quick Start](/docs/cloud)

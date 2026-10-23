---
title: Organizations
---

# Organizations

An organization is a smol cloud account that several people share. Its machines, volumes, registry namespace, API keys, balance and card belong to the organization, and each person's role decides what they can do there. Your own account stays yours; you switch between the accounts you belong to in the console.

## Create an organization

Create one from [the console](/console/org/new), or with a signed-in session:

```http
POST /v1/org
Content-Type: application/json

{ "displayName": "Acme Robotics", "name": "acme-robotics" }
```

- `displayName` is the label shown in the console, 1 to 100 characters. An owner or admin can change it later with `PATCH /v1/org`.
- `name` is the identifier: 3 to 50 lowercase letters, digits, `-` or `_`, unique across smol cloud and final. A taken identifier is refused with `409`.

Opening an organization needs your own account on a paid plan; otherwise the request is refused with `402`. You become its first owner. Creating, converting, renaming and deleting an organization, and inviting people to it, need a person signed in: an API key is refused with `403`.

### Convert your own account

`POST /v1/org/convert` with `{ "displayName": "..." }` turns your own account into an organization in place. Its machines, keys, registry entries, balance and card stay where they are, and you become its owner. Converting needs a paid plan and a card on file (`402` without either), and an account that is already an organization is refused with `409`.

Only the person it belongs to can turn a converted account back, with `DELETE /v1/org`, once it has no sub-organizations.

## Roles

| Role | Can |
|---|---|
| `owner` | Everything an admin can, plus make other owners and delete the organization |
| `admin` | Run machines and volumes, read usage, manage billing, invite and remove people, change roles, create API keys |
| `member` | Run machines and volumes, read usage and the member list |

An organization keeps at least one owner: removing or demoting the last one is refused with `409` until someone else is promoted. Only an owner can make someone an owner.

Owners and admins create the organization's API keys. Each key is for one member, named with `personId` when it is created, and holds no more than that member's role allows. Removing a person revokes their keys on the organization and its sub-organizations; the machines they started keep running.

## Invite people

Owners and admins invite from [Members](/console/members), or with:

```http
POST /v1/org/members/invite
Content-Type: application/json

{ "email": "teammate@company.com", "role": "member" }
```

- An invitation stands for seven days, and an address holds one pending invitation per organization. Resend one with `POST /v1/org/invitations/:id/resend`, or withdraw it with `DELETE /v1/org/invitations/:id`.
- The invited person signs in with an email address they have verified that matches the invited address, then accepts. An expired invitation answers `410`.
- `PATCH /v1/org/members/:id/role` changes a role, and `DELETE /v1/org/members/:id` removes a person.

`GET /v1/org/memberships` lists the organizations you belong to, and `GET /v1/org/invitations/mine` lists the invitations waiting for your verified address.

## Act in an organization

An API key created in the organization's account acts there. A signed-in session names the account with the `Smol-Tenant` header, set to the organization's id; without the header it acts in your own account. The console sets the header for the account you pick.

## Billing

An organization pays for itself, separately from its people's own accounts. Until it has a card on file, and credit or [auto-recharge](/console/billing), its requests that create or change anything are refused with `402`, which names what is missing; inviting people needs them too.

Billing email goes to the organization's own address, or, when it has none, to its longest-standing owner with one.

## Delete an organization

`DELETE /v1/org` is owner only. For an organization opened with `POST /v1/org`, it is refused with `409` while the organization still has machines, volumes, pools, checkpoints, snapshots, cache disks or groups, holds credit, owes for the current period, has sub-organizations, or its sub-organizations have billing pending for this period. The refusal names what to remove first.

## Sub-organizations

A sub-organization is an organization that another organization creates, owns and pays for, for example one per customer you run machines for. Sub-organizations come with an Enterprise contract; on any other plan creating one is refused with `403`.

An owner or admin of the parent creates one from [Sub-organizations](/console/sub-orgs) or with a signed-in session:

```http
POST /v1/org/sub
Content-Type: application/json

{ "displayName": "Acme Robotics", "name": "acme-robotics" }
```

The identifier follows the same rules as an organization's, and nothing of the parent's name appears on the sub-organization. It starts with no members.

- `GET /v1/org/sub` lists them with what each has spent this period. It needs `billing:read`. A deleted one stays listed until the period ends, because its spend is on the parent's bill.
- `DELETE /v1/org/sub/:id` is for the parent's owners only. Like deleting an organization, it is refused with `409` while the sub-organization still has machines or other resources, and also while the parent's balance has run out. Its keys, members and invitations go with it.

**Who does what in a sub-organization:**

- The parent's owners and admins act in it as its provider: they create, start, stop and delete its machines and volumes, read its usage and manage its members. The provider does not reach inside its machines: exec, files, export, checkpoint capture and restore, images from the sub-organization's own registry namespace, stored credentials, registry pull credentials and custom domains are refused with `403`.
- Its own people hold `admin`, `member` or `downstream`. There is no owner, since the parent owns it. `downstream` works inside the machines (exec and files), exports them and captures and restores their checkpoints, and reads them and the member list, but does not otherwise create or delete machines.
- Billing lives on the parent: the sub-organization's spend is drawn from the parent's balance, counts toward the parent's limits, and its billing email goes to the parent.
- A request acting in a sub-organization finds no `/v1/org/sub` routes, and its own people see their own roster, not the parent's people.

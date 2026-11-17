---
title: Organizations
---

# Organizations

An organization is a smol cloud account that several people share. Its machines, registry namespace, API keys, balance and card belong to the organization, and each person's role decides what they can do there. Your own account stays yours; you switch between the accounts you belong to in the console.

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
| `admin` | Run machines, read usage, manage billing, invite and remove people, change roles, create API keys |
| `member` | Run machines, read usage and the member list |

An organization keeps at least one owner: removing or demoting the last one is refused with `409` until someone else is promoted. Only an owner can make someone an owner.

Owners and admins create the organization's API keys. Each key is for one member, named with `personId` when it is created, and holds no more than that member's role allows. A key carries only machine and volume scopes, `usage:read` and `group:write`, so reading the member list, inviting, changing roles, managing keys and billing are done signed in, never with a key. Removing a person revokes their keys on the organization and its sub-organizations; the machines they started keep running.

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

An API key created in the organization's account acts there, and only there: a key sent with a `Smol-Tenant` header naming another account is refused with `400`. A signed-in session names the account with the `Smol-Tenant` header, set to the organization's id; without the header it acts in your own account. The console sets the header for the account you pick.

## Billing

An organization pays for itself, separately from its people's own accounts. Until it has a card on file, and credit or [auto-recharge](/console/billing), its requests that create or change anything are refused with `402`, which names what is missing; inviting people needs them too. A plan it subscribed to itself runs the free plan's concurrent machines and vCPUs per machine until its first payment or subscription is a week old.

Billing email goes to the organization's own address, or, when it has none, to its longest-standing owner with one.

## Delete an organization

`DELETE /v1/org` is owner only. For an organization opened with `POST /v1/org`, it is refused with `409` while the organization still has machines, volumes, pools, checkpoints, snapshots, cache disks or groups, holds credit, owes for the current period, has sub-organizations, or its sub-organizations have billing pending for this period. The refusal names what to remove first.

## Sub-organizations

A sub-organization is an organization that another organization creates, owns and pays for, for example one per customer you run machines for. Sub-organizations come with an Enterprise contract; on any other plan creating one is refused with `403`.

An owner or admin of the parent, signed in, creates one from [Sub-organizations](/console/sub-orgs) or with:

```http
POST /v1/org/sub
Content-Type: application/json

{ "displayName": "Acme Robotics", "name": "acme-robotics" }
```

An API key is refused with `403`. The identifier follows the same rules as an organization's, and nothing of the parent's name appears on the sub-organization. It starts with no members.

- `GET /v1/org/sub` lists them with what each has spent this period. It needs `billing:read`, which an owner or admin of the parent holds signed in and no API key carries. A deleted one stays listed until the period ends, because its spend is on the parent's bill.
- `DELETE /v1/org/sub/:id` is for the parent's owners only. Like deleting an organization, it is refused with `409` while the sub-organization still has machines or other resources, and also while the parent's balance has run out. Its keys, members and invitations go with it.

### Who does what in a sub-organization

The parent's owners and admins act in a sub-organization as its provider. Its own people are invited as on any organization, and there is no owner, since the parent owns it.

| Role | Can |
|---|---|
| provider | Create machines, with their network and published ports set in the create request; start, stop, resize and delete them; create and delete volumes; read usage and the activity log. Signed in, also read the member list, invite and remove people, change roles, and create and revoke keys |
| `admin` | Run machines and change them after create, store and bind credentials, read usage, invite and remove people, change roles, create and revoke keys |
| `member` | Run machines and change them after create, store and bind credentials, read usage and the member list |
| `downstream` | Work inside the machines (exec, files, logs and connecting to their ports), export them, capture and restore their checkpoints, read them and, signed in, the member list. It creates a machine only by restoring a checkpoint, and starts one only by working inside it while it is stopped. Not stop or delete machines, change their network or ports, or read usage |

So changing an existing machine's network or ports, making it public, storing a credential and binding it take an `admin` or `member` of the sub-organization, signed in or with a key created for them.

The provider does not reach inside the machines. Exec, files, connecting to a port, machine logs, export, checkpoint capture and restore, snapshots, rollback, changing a machine's network, published ports or credential bindings after create, a create that binds a stored credential, mounts a volume or is public, making a machine public, port links, share links, images from the sub-organization's own registry namespace, storing credentials, registry pull credentials and custom domains are refused to it with `403`.

A provider who is also invited onto the sub-organization's roster holds both roles, signed in and in the keys created for them there, and so reaches inside its machines like anyone with that row. The row shows on the sub-organization's roster.

### Keys on a sub-organization

A provider or the sub-organization's `admin` creates its keys, signed in, from [API Keys](/console/keys) with the sub-organization picked as the account, or with `POST /v1/apikeys` and the `Smol-Tenant` header set to its id. `personId` names who the key is for:

| `personId` | The key | Holds at most |
|---|---|---|
| Your own id, as a provider | A provider key, for your own software. It stops working once you are no longer an owner or admin of the parent and hold no role on the sub-organization | `machine:create`, `machine:read`, `machine:delete`, `volume:create`, `volume:read`, `volume:delete`, `usage:read` |
| A person on its roster | That person's key, which follows their role | What their role holds, within the scopes a key carries |
| The sub-organization's own id | Its customer's key, for someone who never signs in | `machine:read`, `machine:exec`, `machine:files` |

The customer's key works inside the machines: exec, files, logs and connecting to a published port, and it can export them and capture and restore their checkpoints. It is refused the create, start, stop and delete requests (a restore creates a machine), changing their network or ports, the account and usage, and the member list. An exec, a file read or write, or a terminal on a stopped machine starts it, and that machine's time is billed to the parent like any other in the sub-organization. What the parent charges its customer for it is the parent's own arrangement.

The sub-organization's own people neither list nor revoke a provider's keys there.

### Billing and visibility

- Billing lives on the parent: the sub-organization's spend is drawn from the parent's balance, counts toward the parent's limits, and its billing email goes to the parent.
- A request acting in a sub-organization finds no `/v1/org/sub` routes, and its own people see their own roster, not the parent's people.

# Traps, with the observation behind each

Reproduced on smolfleet API 0.1.0 on 2026-09-10 unless an item says otherwise.

## "Check the HTTP status before decoding a success response" is backwards for exec

The status is 200 for a command that succeeded, one that exited 42, one that timed out and one
whose interpreter was missing:

```
{"command":["sh","-c","echo out; echo err >&2; exit 42"]}   -> 200, exitCode 42
{"command":["sh","-c","sleep 30"],"timeoutSeconds":3}       -> 200, exitCode 124
{"command":["python3","-c","print(1)"]}                     -> 200, exitCode 255
```

The last one's stderr reads
`executable file 'python3' not found in $PATH: No such file or directory`. All three are
indistinguishable from success by status.

The CLI does the right thing and propagates the guest exit code; raw HTTP does not. Both SDKs
propagate it too, but their `exec` promise **resolves** for a failed command, so a `try/catch`
around it catches transport errors only.

## Error bodies are not one format

`401` is JSON with a `code`:

```
{"code":"unknown_key","error":"unknown API key"}
```

`400`, `403`, `404`, `409`, `422` and `501` are plain text. So the common advice not to parse
error message text when a type or code is available is good advice that mostly cannot be followed
here, because for most statuses no code is available.

A client that calls `.json()` on an error path works against an expired key and throws on a
duplicate name.

## A 422 cannot be triaged by status, and neither can a 400

Three distinct causes, one status:

| Cause | Status |
|---|---|
| Missing required field (`source`) | 422 |
| Wrong type (`"cpus":"lots"`) | 422 |
| Over plan quota | 422 |

And the reverse, a well-formed body failing a semantic rule with a **400**:

```
{"network":{"mode":"allowCidrs","cidrs":[]}}
allowCidrs network mode requires at least one CIDR or host
http=400
```

So the status separates a parse failure from a validation failure in neither direction. Read the
body.

## Unauthenticated, every path is 401, including paths that do not exist

`GET /v1/nope` with no credential is 401 with an empty body, not 404. Route probing without a key
tells you nothing, and an empty-bodied 401 cannot be told from a missing route.

## The 403 body names the exact missing scope

```
missing scope: volume:read
http=403
```

That is more useful than the status and more reliable than comparing against `smol auth status`,
because it names what this call needed rather than what the key has.

## Do not use a machine count to detect a failed create

A create that fails after the record exists rolls the record back. `smol cloud deploy` with a bad
image prints `Created: ... (id: mach-...)` and then deletes it, and that id 404s afterwards. Do
not chase the id from a failed deploy, and do not infer a leak from the printed line.

## `x-ratelimit-remaining` exists and is undocumented

It is returned on responses and appears in no reference page. It is the cheapest way to see how
much of the request budget a burst consumed, which matters because the rate limit is the one
documented failure that a healthy account cannot easily provoke.

## A duplicate name is one of the few real 4xx a healthy account produces

Creating a second machine with a name already in use returns 409 with a plain-text body. It is
worth having in a test suite for that reason: most of this API's failure surface needs either a
malformed request or a broken account, and this one needs neither.

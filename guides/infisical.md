---
title: Use Infisical with smol machines
---

# Use Infisical with smol machines

Keep an API key in [Infisical](https://infisical.com) and let a machine call the API without holding the key. The Infisical CLI reads the secret on your computer or in a CI job. The machine gets a placeholder, and the host outside it swaps in the value only on HTTPS requests to the hosts you name, as [Credential substitution](/docs/introduction/concepts/isolation-networking-credentials#credential-substitution) describes.

The example is a GitHub token saved as `GITHUB_TOKEN` in the `dev` environment of an Infisical project. Any API that reads its key as plain text from a request header works the same way.

The local steps were tested on macOS with smolvm v1.37.1 and Infisical CLI 0.44.11.

## Before you start

- [Install smolvm](/docs/local) and the [Infisical CLI](https://infisical.com/docs/cli/install).
- Create an Infisical [machine identity with Universal Auth](https://infisical.com/docs/documentation/platform/identities/universal-auth). The Viewer role on the project is enough.
- Set the identity's `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID` and `INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET` in your shell, from a password manager or the CI system's secret store. Set `INFISICAL_PROJECT_ID` as well.

The CLI connects to Infisical's US cloud by default. For another instance, set the address as [Infisical's CLI quickstart](https://infisical.com/docs/cli/usage) shows.

## Log in and check the secret

```bash
export INFISICAL_TOKEN="$(infisical login --method=universal-auth --silent --plain)"
unset INFISICAL_UNIVERSAL_AUTH_CLIENT_ID INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET GITHUB_TOKEN
infisical run --env=dev --silent -- sh -c 'echo "GITHUB_TOKEN is ${GITHUB_TOKEN:+set}"'
```

The last line prints `GITHUB_TOKEN is set`, without the value. Unsetting `GITHUB_TOKEN` matters: when the Infisical environment does not have the name, a value already in your shell is used.

Check before you start a machine, because a missing value does not stop one from starting. The login token stays valid for as long as the identity allows, 30 days by default, so run `unset INFISICAL_TOKEN` when you finish.

## Run one command

```bash
infisical run --env=dev --silent -- env -u INFISICAL_TOKEN \
  smolvm machine run --image quay.io/curl/curl:latest \
  --credential github=GITHUB_TOKEN@api.github.com -- sh -c '
    echo "inside: $GITHUB_TOKEN"
    curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user'
```

The first line of output is `inside: SMOL_PLACEHOLDER_GITHUB_...`. GitHub receives the real token and answers with your account. Any other host would receive the placeholder.

[`infisical run`](https://infisical.com/docs/cli/reference#secrets-manager-run) (`infisical sm run` in Infisical's reference) gives the command every secret in the environment, and `INFISICAL_TOKEN` too. None of it enters the machine, but the machine's process on the host keeps it all while it runs, where other processes of the same user can read it. `env -u INFISICAL_TOKEN` takes the Infisical token out.

`infisical run` also turns every failure into exit code 1. To hand over one secret and keep the machine's own exit code, read the secret by name:

```bash
(
  export GITHUB_TOKEN="$(infisical secrets get GITHUB_TOKEN --env=dev --plain --silent)"
  [ -n "$GITHUB_TOKEN" ] || exit 1
  env -u INFISICAL_TOKEN smolvm machine run --image quay.io/curl/curl:latest \
    --credential github=GITHUB_TOKEN@api.github.com -- sh -c \
    'curl -sS --fail -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user'
)
```

Keep the `-n` check. `infisical secrets get` exits 0 and prints nothing for a name that does not exist, and smolvm then sends an empty credential.

## Use a persistent machine

Creating the machine needs no value. Start it without one, then hand it the value with `machine credentials refresh`:

```bash
smolvm machine create --name demo --image quay.io/curl/curl:latest \
  --credential github=GITHUB_TOKEN@api.github.com -- sleep infinity
env -u INFISICAL_TOKEN smolvm machine start --name demo
infisical run --env=dev --silent -- env -u INFISICAL_TOKEN \
  smolvm machine credentials refresh --name demo
smolvm machine exec --name demo -- sh -c \
  'curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user'
```

Started this way, the machine's host process has none of the Infisical secrets in its environment. Requests get a `502` until the refresh, so run it after every `machine start`. `machine exec` does not need Infisical. Starting the machine under `infisical run` works too, but leaves every secret of the environment in the host process until the machine stops.

## Rotate the secret

After the value changes in Infisical, run the same `machine credentials refresh` command again. The machine uses the new value from its next request, without a restart. If the environment no longer has the name, the refresh fails and the machine keeps the old value.

Delete the example machine with `smolvm machine delete --name demo --force`.

## Use it on smol cloud

On smol cloud the value is stored once, under a name, and a machine binds that name. A CI job can store it. Give the job a smol cloud key with the `machine:create` scope in `SMOL_CLOUD_TOKEN`, set `SMOL_CLOUD_URL` as in the [Cloud Quick Start](/docs/cloud), and save this as `store.sh`:

```bash
set -eu
: "${GITHUB_TOKEN:?not in this Infisical environment}"
jq -n '{envVar: "GITHUB_TOKEN", hosts: ["api.github.com"], value: env.GITHUB_TOKEN}' |
  curl -sS --fail-with-body -X PUT "$SMOL_CLOUD_URL/v1/credentials/github" \
    -H @<(printf 'Authorization: Bearer %s\n' "$SMOL_CLOUD_TOKEN") \
    -H 'Content-Type: application/json' --data-binary @-
```

After the [log in](#log-in-and-check-the-secret) step, the job runs it with the secret in its environment:

```bash
infisical run --env=dev --silent -- bash store.sh
```

The value goes through the pipe into the request, and the response does not contain it. Do not print it on the way. `infisical export` and `infisical secrets` (`get` included) write values to standard output, and `bash -x` prints them too. `infisical export --output-file` leaves every secret in a plain text file that other users can read under the usual umask.

Then create machines with the credential's name:

```bash
curl --fail-with-body -X POST "$SMOL_CLOUD_URL/v1/machines" \
  -H "Authorization: Bearer $SMOL_CLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "github-worker",
    "source": {"type": "image", "reference": "alpine"},
    "network": {"mode": "open"},
    "credentials": ["github"]
  }'
```

To rotate, run the job again. The response says which running machines took the new value, as [Credentials the machine never holds](/docs/cloud/lifecycle-storage-networking#credentials-the-machine-never-holds) explains.

## Limits

- The value is put in only in request headers, on HTTPS port 443, to the named hosts. Over plain HTTP or on another port the placeholder travels as text.
- HTTP Basic encodes the placeholder (`curl -u` does this), so it is not replaced. For an API that uses Basic, store the whole header value, such as `Basic dXNlcjprZXk=`, and end the binding with [`:set-header=authorization`](/docs/local/machine-lifecycle-cli-reference#common-resource-flags).
- When an API sends the value back, plain or in base64, it is removed from the response. Other forms, such as hex or reversed text, are not caught, so bind only APIs you trust.

| Message | Meaning |
|---|---|
| `smolvm credentials: credential unavailable` | `502`: the name is not in that Infisical environment, or the machine has no value yet |
| `placeholders are substituted in request headers only` | `403`: the placeholder was in the URL |
| `body substitution is disabled for this binding` | `403`: the placeholder was in the request body |
| `Folder with path '/' in environment 'x' was not found` | The `--env` name is wrong |
| `failed to wait for command termination` | The command under `infisical run` failed |

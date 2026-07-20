# SEA local dev infrastructure

A TLS-terminated Keycloak for driving the iOS demo app end-to-end.

> **Everything here is DEV ONLY.** Admin `admin`/`admin`, a fixed client
> secret in source, and a public OAuth client that must never exist in a real
> environment. None of it is a deployment reference — §26 of the spec is.

## Why there is a TLS proxy

SEA's authorize-URL validator (§6.2, contract §5) requires `https` and a
standard port, and §8.2 forbids any debug bypass of TLS handling. A plain
`http://localhost:8080` Keycloak is therefore rejected **by our own core** —
correctly.

There were two ways out: weaken the validator for debug builds, or make local
dev speak real HTTPS. We chose the second. nginx terminates TLS on `:443` with
an mkcert certificate, and Keycloak sits behind it, unpublished.

The payoff is that the validator, app-bound-domains enforcement, and the TLS
challenge path all run locally in their **production configuration**. There is
no debug-only security relaxation anywhere in this project, so none can escape
into a release build — because none was ever written.

## Setup

```bash
brew install mkcert            # once
./gen-certs.sh                 # generate infra/tls/*.pem
docker compose up -d
./provision-realm.sh           # create realm, clients, demo user
```

With a simulator booted, trust the CA inside it:

```bash
xcrun simctl boot 'iPhone 17'; open -a Simulator
./trust-ca-simulator.sh
```

This adds the CA to the **simulator** keychain only. We deliberately do not run
`mkcert -install`, which would modify your macOS system trust store.

## Verify

```bash
curl --cacert "$(mkcert -CAROOT)/rootCA.pem" \
  https://localhost/realms/bankerise-mobile/.well-known/openid-configuration
```

Expected `issuer`: `https://localhost/realms/bankerise-mobile` — note `https`,
which confirms the proxy headers are reaching Keycloak.

## What's provisioned

| | |
|---|---|
| Realm | `bankerise-mobile` — SSO idle 30d, max 90d (§11.2), brute-force on, en/fr/ar |
| Admin console | https://localhost/admin — `admin` / `admin` |
| Test user | `demo` / `demo123` |

### Clients

**`bankerise-mobile`** — confidential, PKCE S256, exact-match redirect
`bankerise-auth://callback`, direct access grants **off** (§12.1 forbids ROPC).
This is the production shape. Its secret belongs to the API Gateway alone (§6);
nothing on the device ever holds it.

**`sea-dev-public`** — public client, same redirect URI. **A dev-only
shortcut.** It exists so the iOS demo can drive the WebView surface with no
gateway in the loop, which is all Phase 1 needs. It does *not* reflect the
production BFF architecture, where the client is confidential and all token
custody is server-side. Delete it the moment a real gateway is available.

## Authorize URL for the demo app's mock-gateway field

```
https://localhost/realms/bankerise-mobile/protocol/openid-connect/auth?response_type=code&client_id=sea-dev-public&redirect_uri=bankerise-auth%3A%2F%2Fcallback&scope=openid&state=devstate123&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256
```

The `code_challenge` is the RFC 7636 worked example, whose verifier is
`dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk`.

Phase 1 never exchanges the code — SEA's job ends at capture (§6.3) — so the
verifier only matters once you have a gateway, or are testing an exchange by
hand.

## Realm changes

Edit `provision-realm.sh` and re-run it; it is idempotent. We provision through
`kcadm` rather than importing a hand-written realm export because kcadm
validates every field against the running server, so the result is canonical by
construction. A hand-authored export was tried first and failed import on
several invented fields.

## Reset

```bash
docker compose down -v && docker compose up -d && ./provision-realm.sh
```

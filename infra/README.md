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
brew install mkcert jq          # once — jq drives provision-realm.sh's
                                 # WebAuthn flow scripting
./gen-certs.sh                  # generate infra/tls/*.pem
docker compose up -d
./provision-realm.sh            # create realm, clients, demo user, passkeys
```

### `auth.bank.local` — required host entry (human step, needs sudo)

The passkey RP ID (§10.3) and the iOS Associated Domain are both fixed to
`auth.bank.local`, not `localhost`. Point it at the loopback address —
**this is not something Claude/automation can do; run it yourself**:

```bash
echo '127.0.0.1 auth.bank.local' | sudo tee -a /etc/hosts
```

The iOS Simulator shares the Mac's DNS/hosts resolution, so no simulator-side
config is needed for this part. `localhost` keeps working unmodified
throughout (nginx `server_name` lists both; the cert SANs cover both) — this
entry only adds a second name for the same loopback stack, it changes
nothing about existing `https://localhost` usage.

With a simulator booted, trust the CA inside it:

```bash
xcrun simctl boot 'iPhone 17'; open -a Simulator
./trust-ca-simulator.sh
```

This adds the CA to the **simulator** keychain only. We deliberately do not run
`mkcert -install`, which would modify your macOS system trust store.

If you ever regenerate the cert (`./gen-certs.sh`), re-run
`./trust-ca-simulator.sh` too — the new cert is untrusted in the simulator
until you do, and both the `auth.bank.local` and `localhost` WebViews will
show TLS errors until it's re-trusted.

## Verify

```bash
curl --cacert "$(mkcert -CAROOT)/rootCA.pem" \
  https://localhost/realms/bankerise-mobile/.well-known/openid-configuration
```

Expected `issuer`: `https://auth.bank.local/realms/bankerise-mobile` — the
issuer is pinned to `auth.bank.local` (`KC_HOSTNAME`) regardless of which
server name you connect through, because the passkey RP ID must be stable.
`https://localhost` still resolves and proxies correctly; only the URLs
Keycloak *mints* are fixed to `auth.bank.local`.

You can validate the `auth.bank.local` path before touching `/etc/hosts`, by
forcing the resolution on the curl command line instead:

```bash
curl --resolve auth.bank.local:443:127.0.0.1 --cacert "$(mkcert -CAROOT)/rootCA.pem" \
  https://auth.bank.local/realms/bankerise-mobile/.well-known/openid-configuration

curl --resolve auth.bank.local:443:127.0.0.1 --cacert "$(mkcert -CAROOT)/rootCA.pem" \
  https://auth.bank.local/.well-known/apple-app-site-association
```

The second command should return `200`, `Content-Type: application/json`,
and the AASA body described below.

### Known quirk: the `tls` healthcheck can show `unhealthy`

`docker compose ps` may show `sea-keycloak-tls` as `unhealthy` even though
everything above works. Cause: the nginx image's IPv6-listener setup script
can't patch our read-only-mounted `default.conf`, so nginx only binds `:443`
on IPv4; the healthcheck's `wget https://localhost/...` resolves `localhost`
to `::1` first *inside the container* and gets "connection refused" before
falling back. This is a container-internal-networking artifact, pre-existing
and unrelated to the `auth.bank.local` change — `curl`/WKWebView from the
host or the simulator are unaffected because they don't share the
container's resolver. Safe to ignore; not fixed here to keep this change
scoped to passkeys/`auth.bank.local`.

## Apple App Site Association (AASA)

`nginx/apple-app-site-association` is served at
`https://auth.bank.local/.well-known/apple-app-site-association` (and via
`https://localhost/...`, same file, same server block) with an exact path
match, no `.json` extension, no redirect, `Content-Type: application/json` —
per Apple's associated-domains requirements. It is a static file, mounted
read-only into the `tls` container; nginx serves it directly and never
proxies that path to Keycloak.

```json
{"webcredentials":{"apps":["TEAMID.com.bankerise.sea.demo","TEAMID.com.bankerise.sea.demorn"]}}
```

Both demo apps' bundle IDs must be listed — `apps/demo-ios` and
`apps/demo-rn` each carry their own `com.apple.developer.associated-domains`
entitlement (`apps/demo-ios/Sources/SEADemo.entitlements` and
`apps/demo-rn/ios/demo_rn/demo_rn.entitlements`, both
`webcredentials:auth.bank.local?mode=developer`) and Apple validates the
AASA's `apps` array contains the exact `TeamID.BundleID` of whichever app is
asking — a missing entry means WebAuthn silently fails to bind for that app
and Keycloak falls back to password-only, with no error surfaced.

`TEAMID` is a placeholder — the same value in both entries. It must equal
the app's `application-identifier` entitlement, i.e.
`<Apple Development Team ID>.com.bankerise.sea.demo` (or `.demorn`) exactly
— a 10-character alphanumeric Team ID, not a display name. To find
yours: Xcode → target → Signing & Capabilities → the value shown under
"Team" resolves to a Team ID visible at
https://developer.apple.com/account/#/membership, or run
`security find-identity -v -p codesigning` and read the ID out of a matching
signing identity. Edit `infra/nginx/apple-app-site-association` and replace
`TEAMID` once you know it; no rebuild needed beyond
`docker compose restart tls` (or just `docker compose up -d`, since the
volume mount is read live from disk — re-running the container isn't
strictly required for a bind-mounted file, but do it if nginx doesn't seem
to pick up the change).

For Simulator development, Xcode's **debug-signed** builds normally still
carry a real Team ID (from your paid or free Apple ID), so the same
`TEAMID.com.bankerise.sea.demo` value generally works — there is no separate
"simulator-only" identifier. Associated Domains validation in the Simulator
also requires **Settings → Developer → Associated Domains Development**
switched on for the domain to be validated on-device rather than skipped;
see below.

## What's provisioned

| | |
|---|---|
| Realm | `bankerise-mobile` — SSO idle 30d, max 90d (§11.2), brute-force on, en/fr/ar |
| Admin console | https://auth.bank.local/admin (or https://localhost/admin) — `admin` / `admin` |
| Test user | `demo` / `demo123` |
| Passkeys | WebAuthn Passwordless required action enabled; RP ID `auth.bank.local`; passkey-first, password-fallback browser flow (`browser-passkey`) — see below |

### Clients

**`bankerise-mobile`** — confidential, PKCE S256, exact-match redirect
`bkrmob://callback`, direct access grants **off** (§12.1 forbids ROPC).
This is the production shape. Its secret belongs to the API Gateway alone (§6);
nothing on the device ever holds it.

**`sea-dev-public`** — public client, same redirect URI. **A dev-only
shortcut.** It exists so the iOS demo can drive the WebView surface with no
gateway in the loop, which is all Phase 1 needs. It does *not* reflect the
production BFF architecture, where the client is confidential and all token
custody is server-side. Delete it the moment a real gateway is available.

> The redirect URI used to be `bankerise-auth://callback`; the iOS app now
> captures `bkrmob://`, so `provision-realm.sh` pins `bkrmob://callback` on
> both clients — including on re-runs against a realm provisioned before
> this change.

## Passkeys / WebAuthn (spec §10)

`provision-realm.sh` configures Keycloak 26.6 passwordless WebAuthn end to
end:

- **Required action** `webauthn-register-passwordless` — enabled, not a realm
  *default* action, but **pre-armed on the `demo` user at first provision** so
  a fresh setup prompts passkey enrollment on `demo`'s first login (register
  once, then the passkey-first CTA works). Re-running provisioning never
  clobbers a user who already enrolled, and password (`demo123`) always remains
  as the fallback. To force enrollment for other users, assign the required
  action to them or make it a realm default action.
- **Realm WebAuthn Passwordless policy** — RP entity name `Bankerise (dev)`,
  RP ID `auth.bank.local`, signature algorithms `ES256`/`RS256`, attestation
  `none`, authenticator attachment `platform`, resident key required,
  user verification `required`.
- **`browser-passkey` flow** — the canonical Keycloak "passwordless OR
  password" nested tree, rebuilt from scratch each run for a deterministic
  structure:

  ```
  browser-passkey
    Cookie                          ALTERNATIVE   (§11.1 silent SSO re-auth)
    Identity Provider Redirector    ALTERNATIVE
    forms                           ALTERNATIVE
      passkey-or-password           REQUIRED
        WebAuthn Passwordless        ALTERNATIVE  (passkey-first)
        password                     ALTERNATIVE  (fallback)
          Username Password Form      REQUIRED
          conditional-otp             CONDITIONAL
            Condition - user configured REQUIRED
            OTP Form                    REQUIRED
  ```

  The top-level Cookie authenticator is untouched, so the §11.1 silent
  SSO-cookie re-auth path still runs first — passkey-vs-password only matters
  for an *interactive* login. The realm's `browserFlow` is bound to this flow.

  **Why nested, and the trap it avoids (important if you edit this block):**
  Keycloak refuses to execute any level that mixes `REQUIRED` with
  `ALTERNATIVE` — it logs `REQUIRED and ALTERNATIVE elements at same level!`,
  *ignores the alternatives*, and the whole flow throws
  `AuthenticationFlowException` → HTTP 400 with the theme's error page instead
  of a login form. A `kcadm get` of the flow looks perfectly fine in that
  state; only *driving the real authorize endpoint* reveals it. So the passkey
  and password options must be `ALTERNATIVE` siblings under their **own
  `REQUIRED` subflow** (`passkey-or-password`), never siblings of the
  conditional-OTP subflow. An earlier flat version of this flow (WebAuthn +
  Username Password Form both `ALTERNATIVE` directly inside `forms`, next to
  the `CONDITIONAL` OTP subflow) hit exactly this and could not log in at all.

  Scripting notes:
  - The flow is dropped and recreated every run. A flow bound as `browserFlow`
    can't be deleted, so the script rebinds to the built-in `browser` first
    (which also means an interrupted run leaves a *working* default bound, not
    a half-built flow). Deleting the top-level flow frees its nested subflow
    aliases too.
  - Executions are created top-down so their priorities come out already
    ordered — no `raise-priority` juggling. Requirements are then set with the
    current `priority` **always carried through explicitly**: PUTting a
    requirement change through `authentication/flows/{alias}/executions`
    without a `priority` in the body zeroes that execution's priority as a
    Keycloak 26.6 side effect, which would scramble sibling order.
  - Nested-execution requirements are set through the *top-level* flow's
    `/executions` endpoint (it returns and accepts the whole nested tree by
    id), so the script never has to URL-encode subflow paths.

### Enrolling and testing a passkey for `demo`

Provisioning **pre-arms** `webauthn-register-passwordless` on `demo` at first
creation, so the flow is demoable with no manual step:

1. **First login** (`demo`/`demo123`) → Keycloak prompts *"Passkey
   Registration"* → register the passkey. Registration clears the required
   action.
2. **Subsequent logins** → the login page shows a **"Sign in with Passkey"**
   primary CTA above the password form (see the theme note below). Tapping it
   runs a usernameless passkey ceremony; password remains as fallback.

If you need to re-arm enrollment (e.g. after deleting the credential), set the
required action again:

```sh
DEMO_ID=$(docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh \
  get users -r bankerise-mobile -q username=demo --fields id --format csv --noquotes)
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh \
  update users/$DEMO_ID -r bankerise-mobile \
  -s 'requiredActions=["webauthn-register-passwordless"]'
```

You can also add a passkey from the account console
(`https://auth.bank.local/realms/bankerise-mobile/account/#/security/signing-in`),
or trigger enrollment ad hoc by appending
`&kc_action=webauthn-register-passwordless` to the authorize URL.

### Passkey-first CTA and the theme import-map requirement (spec §10, §18.2)

The `bankerise-mobile` login theme surfaces passkeys as a **first-class,
passkey-first** action:

- **`login.ftl`** renders a primary **"Sign in with Passkey"** button above the
  username/password form. It has no dedicated Keycloak variable — it finds the
  WebAuthn Passwordless authenticator in `auth.authenticationSelections` and
  POSTs that execution's `authExecId` as `authenticationExecution` (the same
  mechanism as "Try Another Way", surfaced as a one-tap action). It renders
  only when that selection is offered, so a realm without passkeys degrades
  cleanly to password-only. We deliberately do **not** use conditional-UI
  autofill: on Keycloak 26.6 that path (`enableWebAuthnConditionalUI`) is set
  only by the deprecated `WebAuthnConditionalUIAuthenticator` (feature off), and
  autofill is unreliable inside `WKWebView` anyway.
- **`template.ftl` MUST emit the `rfc4648` import map.** Because this theme
  fully replaces `base/login/template.ftl`, it has to re-emit the
  `<script type="importmap">` that maps the bare specifier `"rfc4648"` (imported
  at the top of Keycloak's `webauthnRegister.js` / `webauthnAuthenticate.js`).
  **Without it, the WebAuthn module silently fails to load and the passkey
  register/authenticate button does nothing** — no console error inside
  `ASWebAuthenticationSession`'s Safari view, so this failure is easy to
  misdiagnose as a platform limitation. Keep it in sync with
  `base/login/template.ftl`.
- We do **not** override `webauthn-register.ftl` / `webauthn-authenticate.ftl`,
  so those two ceremony pages render Keycloak's stock body inside our login
  chrome (functional, lightly unstyled). Styling them is a known follow-up.

### Validate the passkey ceremony in a desktop browser first

Do this *before* touching the Simulator — it isolates Keycloak/RP-side
correctness from anything iOS/WKWebView-specific, and it works without
`/etc/hosts` or Simulator setup at all:

1. Add the host entry (§ above), or just use `https://localhost` for this
   part — RP ID is fixed to `auth.bank.local` either way since that's what
   `KC_HOSTNAME` mints.
2. Open Chrome → DevTools → **More tools → WebAuthn** → check "Enable
   virtual authenticator environment" → add an authenticator with Protocol
   `ctap2`, Transport `internal`, "Supports resident keys" checked,
   "Supports user verification" checked (this mimics a platform
   authenticator like Face ID/Touch ID/Windows Hello).
3. Navigate to the authorize URL above (with the real `redirect_uri` it'll
   404 in the browser after redirecting — that's fine, the point is
   exercising the login page, not completing the OAuth round trip).
4. Log in as `demo`/`demo123`, then register a passkey (account console or
   `kc_action=webauthn-register-passwordless`, see above) — the virtual
   authenticator auto-responds with no OS prompt.
5. Log out, log back in: the login page renders (HTTP 200, not the 400 error
   page), and the `browser-passkey` flow offers both the passkey ceremony and
   the username/password fallback. The exact CTA layout ("Sign in with a
   passkey" button, "Try another way", etc.) is owned by the `bankerise-mobile`
   theme; what infra guarantees is that both branches are reachable and the
   password fallback completes to a `bkrmob://callback?code=...` redirect.

A quick non-interactive smoke test of the same thing (no browser needed):

```bash
# 1. authorize endpoint must return the LOGIN FORM at HTTP 200, not a 400 error
curl -s -o /tmp/lp.html -w '%{http_code}\n' \
  --resolve auth.bank.local:443:127.0.0.1 --cacert "$(mkcert -CAROOT)/rootCA.pem" \
  "https://auth.bank.local/realms/bankerise-mobile/protocol/openid-connect/auth?client_id=sea-dev-public&redirect_uri=bkrmob%3A%2F%2Fcallback&response_type=code&scope=openid&state=devstate123&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
grep -q 'id="kc-form-login"' /tmp/lp.html && echo "login form present"

# 2. no flow-config error in the server log for that request
docker logs sea-keycloak 2>&1 | grep -c "REQUIRED and ALTERNATIVE elements at same level"   # want 0
```

If this works, the RP ID, policy, and flow structure are all correct and any
remaining issue is genuinely iOS/WKWebView-side (§10.2's engineering note —
WebAuthn-in-WebView support is the least stable part of this spec).

> If the authorize endpoint ever returns **400 with the theme's error page**
> and the log shows `REQUIRED and ALTERNATIVE elements at same level!`, the
> flow's nesting has regressed — see the "Why nested" note under
> [Passkeys / WebAuthn](#passkeys--webauthn-spec-10). A `kcadm get` of the
> flow will look fine even while it's broken; only the live authorize call
> catches it.

### iOS Simulator: Associated Domains + Face ID

Once the desktop check passes:

1. **Enable Associated Domains Development** on the booted Simulator (so it
   validates the `webcredentials:auth.bank.local` domain on-device instead
   of silently skipping validation): on the Simulator, go to
   **Settings → Developer → Associated Domains Development** and switch it
   on. (This toggle only appears once a build with an Associated Domains
   entitlement has run at least once; if you don't see it yet, run the demo
   app first, then check Settings again.)
2. **Enroll a simulated Face ID** so the platform authenticator has
   something to assert with: Simulator menu → **Features → Face ID →
   Enrolled**.
3. During the ceremony (registration or login), when the passkey prompt
   appears: Simulator menu → **Features → Face ID → Matching Face** to
   simulate a successful biometric match (or **Non-matching Face** to
   exercise the failure path).
4. If the ceremony never triggers a native prompt, re-check: the AASA `curl`
   check above returns 200 with the *real* Team ID (not the `TEAMID`
   placeholder) baked in, the CA is trusted in the simulator
   (`./trust-ca-simulator.sh`, re-run after any `./gen-certs.sh`), and
   `/etc/hosts` has the `auth.bank.local` line.

## Authorize URL for the demo app's mock-gateway field

```
https://auth.bank.local/realms/bankerise-mobile/protocol/openid-connect/auth?response_type=code&client_id=sea-dev-public&redirect_uri=bkrmob%3A%2F%2Fcallback&scope=openid&state=devstate123&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256
```

The `code_challenge` is the RFC 7636 worked example, whose verifier is
`dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk`.

Phase 1 never exchanges the code — SEA's job ends at capture (§6.3) — so the
verifier only matters once you have a gateway, or are testing an exchange by
hand.

`apps/demo-rn`'s `src/mockGateway.ts` hardcodes this exact same URL, so both
demo apps exercise the identical realm/client/PKCE values.

## `sea-react-native` bridge + `apps/demo-rn` (spec §4.2, §4.4, §7)

Dev-mode setup, root of the repo:

```bash
nvm use            # Node >=22.13 — see .nvmrc; the RN 0.86 toolchain rejects Node 18
yarn install        # Yarn classic v1 workspaces: packages/sea-react-native, apps/demo-rn
cd apps/demo-rn/ios && pod install   # first run downloads RN prebuilt artifacts, ~3 min
cd .. && yarn ios    # or: npx react-native start, then build/run demo_rn.xcworkspace in Xcode
```

Notes:

- `packages/sea-core-ios/SEACore.podspec` is a thin wrapper (no logic
  change) so CocoaPods can consume the same `Sources/SEACore` that
  `apps/demo-ios` consumes via SwiftPM — see the `#if SWIFT_PACKAGE` seam in
  `SEAStrings.swift` (SwiftPM's `Bundle.module` doesn't exist under
  CocoaPods). `apps/demo-rn/ios/Podfile` pins it by local `:path`, per §4.5.
- All bridge logic lives in `packages/sea-react-native/ios/SEABridgePresenter.swift`
  (builds a `SEAConfig` from primitive props, calls `SEASession.start`) — the
  generated Fabric view (`SeaReactNativeView.mm`) only marshals props/events,
  per §7.4's bridge-purity rule.
- `apps/demo-rn` bundles its own `SEASecurityConfig.plist`, `bkrmob`
  URL-scheme registration, **and** `demo_rn.entitlements`
  (`com.apple.developer.associated-domains`), identical in shape to
  `apps/demo-ios`'s, so it talks to the same local realm/theme and gets the
  same passkey-first CTA — see the AASA section above; both apps' bundle IDs
  must be listed there or WebAuthn silently fails to bind for whichever one
  is missing.
- Metro needs `watchFolders`/`nodeModulesPaths` pointed at the workspace root
  (see `apps/demo-rn/metro.config.js`) to see the hoisted root
  `node_modules`, and `resolver.unstable_enablePackageExports` +
  the `sea-react-native-source` condition name to resolve
  `sea-react-native` straight to its TS source — no separate build step is
  needed in dev.
- `apps/demo-rn` has three tabs (hand-rolled, no navigation library):
  Config (gateway URL / mock toggle / allowed domains / presentation /
  timeout / start / purge web data), Result, and Telemetry — mirroring
  `apps/demo-ios`'s ConfigView/ResultsView/TelemetryConsoleView. The Fuzz
  view is intentionally not ported: it drives `SEACore`'s internal
  Swift-only fuzz harness directly and isn't part of the bridge surface
  `sea-react-native` exposes. Settings are in-memory only (no
  AsyncStorage-equivalent dependency), unlike `apps/demo-ios`'s persisted
  `UserDefaults`.
- Telemetry (§20) and purge-web-data (§11.3) cross the bridge via a small
  `SeaTelemetryEmitter` native module
  (`packages/sea-react-native/ios/SeaTelemetryEmitter.swift`) — a classic
  `RCTEventEmitter`, not a Fabric view, since it has no visual surface.
  Exported from JS as `subscribeToTelemetry`/`purgeWebData`/`copyToClipboard`
  in `sea-react-native`. Swift↔React-Core ObjC interop needed `import React`
  in the Swift file plus `#import <React/RCTEventEmitter.h>` (and
  `RCTBridgeModule.h`) added to `SeaReactNativeView.mm` — the generated
  `SeaReactNative-Swift.h` header references `RCTEventEmitter` and
  `RCTPromise{Resolve,Reject}Block` but doesn't import them itself, so
  whatever `.mm` file includes that header first must import them.
- Android is not implemented (`sea-core-android` doesn't exist in this repo
  yet).

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

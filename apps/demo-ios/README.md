# SEADemo — `demo-ios` native harness

Primary device-lab vehicle for exercising the `SEACore` package with **no React
Native in the loop** (spec §23.3). Every "does this actually work on a real
device" question — WebView hardening, navigation policy, telemetry, capture
posture — should be answerable from this app.

This app contains **no security logic of its own**. All authorize-URL
validation and in-WebView navigation policy live in `SEACore`
(`packages/sea-core-ios/`, built against `docs/api-contract-ios-v1.md`). This
app only: persists tester-facing config, runs the §6.1 two-hop gateway start
sequence (or a mock), calls into `SEACore`'s public API, and displays what
comes back.

## Generating the Xcode project

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (developed against
v2.46):

```sh
cd apps/demo-ios
xcodegen generate
open SEADemo.xcodeproj
```

`SEADemo.xcodeproj` is generated, not committed — re-run `xcodegen generate`
any time `project.yml` or the `Sources/` file layout changes.

The app target depends on the local Swift package at
`../../packages/sea-core-ios` (product `SEACore`), declared in `project.yml`
via `packages:` / `dependencies: [package: SEACore]`. That package is being
built in parallel — if it's missing or its API doesn't match
`docs/api-contract-ios-v1.md` yet, `xcodegen generate` will still succeed
(it's just a project reference) but `xcodebuild` will fail at Swift Package
Manager resolution or at the `import SEACore` / API call sites in this app's
source. That is expected until the core package catches up to the contract.

## Running against the mock gateway (zero backend)

Default state out of the box:

- **Use mock gateway**: ON
- **Mock redirectUrl**: a canned local-Keycloak-shaped authorize URL
  (`https://auth.bank.local/realms/bankerise/protocol/openid-connect/auth?...`)

With the toggle on, "Start login" skips all networking and hands that URL
straight to `SEASession.start`. This lets you exercise the WebView surface —
sheet/fullscreen presentation, header/appearance, navigation policy against a
real page load, telemetry events, screen-security posture — with nothing else
running. Note the mock does **not** bypass `SEACore`'s own validation: the
canned URL still has to be `https` and host-allowlisted, or you'll get
`onError(.invalidAuthorizeURL)` exactly as you would from a real gateway
response. Edit the mock URL on the Config screen to point at whatever
Keycloak realm/theme you're iterating on.

## Running against local Keycloak / the real gateway

Turn "Use mock gateway" off and point **Gateway base URL** at your local
gateway instance (default: `http://localhost:8080`). Local backend
infrastructure (gateway + Keycloak realm) is being set up in parallel under
`infra/` at the repo root — see that directory for how to bring it up. This
app makes no assumptions about how it's started; it only speaks the §6.1
contract:

```
POST {gatewayBaseURL}/authorization/start  -> { redirect, authMode, provider }
GET  {redirect}                            -> { redirectUrl, provider }
```

`GatewayClient` uses a `URLSession` with `httpCookieAcceptPolicy = .always` so
the pre-auth `SESSION` cookie set on hop 2 is retained in the **native**
cookie jar (§6.5) — this app never shares that jar with the WebView, and never
reads or extracts WebView cookies.

Because the final `redirectUrl` (the Keycloak authorize URL) must be `https`
and host-allowlisted per `SEACore`'s validator, your local Keycloak / gateway
setup needs to actually terminate TLS on a host in your **Allowed domains**
list (e.g. `auth.bank.local` via `/etc/hosts` + a local cert) for the embedded
flow to get past validation — plain `http://localhost` Keycloak will be
rejected by design (this is not a bug in the demo app; see "Contract
ambiguities" below).

## Screens

- **Config** (root/first tab) — gateway base URL, callback scheme, allowed
  domains (comma list), presentation (sheet/fullscreen), timeout, mock
  gateway toggle + mock URL. All persisted to `UserDefaults`. Also hosts
  "Start login" and "Purge web data" (`SEASession.purgeWebData`, for testing
  §11.1 SSO persistence vs. a clean slate).
- **Result** — the last session's terminal outcome verbatim: on
  `onCaptured`, every raw callback param in a table (including `code` /
  `state` — this is a dev harness, showing them is intentional); on
  `onCancelled` / `onError`, which one and the error detail.
- **Telemetry** — live, scrolling console of every `SEAEvent` the core emits
  (`SEATelemetrySink`), with a "Copy all" button. This is how you verify §20
  events actually fire for a given interaction.
- **Fuzz** — one-tap §23.2 navigation-fuzzing corpus (`javascript:`, `intent:`,
  `file:`, plain `http`, look-alike hosts, a userinfo trick, `data:`, an
  oversized URL). Runs each through `SEAAuthorizeURLValidator.validate` and
  shows allow/block + reason per entry. See the contract-ambiguity note below.

## DEV-ONLY ATS warning

`Sources/Info.plist` contains an `NSAppTransportSecurity` exception domain for
`localhost`, wrapped in a clearly marked `// DEV ONLY` block. It exists solely
so this app's own `GatewayClient` can talk to a locally-run plaintext-HTTP
gateway during development — it has nothing to do with the WebView, which
only ever loads `https` authorize URLs per §6.2 and needs no ATS exception.

**This exception must never ship.** Delete the entire
`NSAppTransportSecurity` block from `Sources/Info.plist` before any build of
this app leaves a developer's machine (TestFlight, ad hoc, or App Store).

## Contract ambiguities hit while building this

1. **Fuzz screen validation surface.** `docs/api-contract-ios-v1.md` §5
   exposes exactly one public validator,
   `SEAAuthorizeURLValidator.validate(_:against:narrowedBy:)`, which is scoped
   to the *authorize URL* (§6.2) — evaluated once, before any WebView
   navigation happens. The *navigation policy* (§6 of the contract / spec
   §7.3) that governs in-WebView navigation decisions (blocked schemes,
   allowlist checks on subsequent navigations, the callback-scheme preempt) is
   implemented inside `SEACore`'s `WKNavigationDelegate` and is not exposed as
   a standalone callable API. The Fuzz screen therefore runs its corpus
   through the authorize-URL validator, not the live navigation-delegate code
   path. For every entry in this corpus the two policies should agree (same
   scheme/host/userinfo/length rules), but this is worth the core team
   confirming — and if a future phase wants the fuzz screen to exercise the
   *actual* navigation delegate, the contract will need to expose that as a
   testable seam (or the demo would need to drive a real WKWebView through
   each URL, which is a materially different, much heavier test).
2. **Local dev TLS.** The authorize-URL validator requires `scheme == https`
   with no documented dev/debug exception (unlike, say, TLS certificate
   handling, which explicitly documents "no debug bypass" — scheme has no
   such caveat either way). A plain-HTTP local Keycloak (the common
   `http://localhost:8080` dev setup) will always fail `.scheme` validation
   when its authorize URL is handed to `SEACore`. Local infra will need to
   terminate TLS on an allowlisted host for the embedded (non-mock) flow to
   be exercisable at all — flagging this so `infra/` and the core team can
   reconcile expectations.

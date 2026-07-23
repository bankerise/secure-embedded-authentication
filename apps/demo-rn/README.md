# demo_rn — `sea-react-native` bridge validation harness

Bridge validation only (spec §4.4) — this app exists to exercise
`packages/sea-react-native`'s Fabric component against `sea-core-ios`, not to
be a feature-complete demo. Every "does the WebView surface actually work on
a real device" question belongs to `apps/demo-ios` instead — that app
exercises `SEACore` directly with no RN in the loop.

Three tabs (hand-rolled `src/TabBar.tsx`, not a navigation library — not
worth the dependency for three screens), mirroring
`apps/demo-ios`'s Config/Result/Telemetry screens:

- **Config** (`src/screens/ConfigScreen.tsx`) — gateway base URL, mock
  gateway toggle + editable mock redirect URL, allowed domains, presentation
  (sheet/fullscreen), timeout, Start login, Logout, Purge web data.
- **Result** (`src/screens/ResultScreen.tsx`) — the last `onCaptured` /
  `onCancelled` / `onError` outcome, raw params shown verbatim (this is a
  dev harness, not a production integration).
- **Telemetry** (`src/screens/TelemetryScreen.tsx`) — live console of every
  `SEAEvent` SEACore emits (spec §20), via `sea-react-native`'s
  `subscribeToTelemetry`.

Not ported: `apps/demo-ios`'s Fuzz view — it drives `SEACore`'s internal
Swift-only fuzz harness directly, which isn't part of the bridge surface
`sea-react-native` exposes. Settings (`src/settings.ts`) are in-memory only,
not persisted across launches like `apps/demo-ios`'s `UserDefaults` — no
AsyncStorage-equivalent dependency in this harness.

This app contains **no security logic of its own**. `App.tsx` builds an
authorize URL either via `src/mockGateway.ts` (a zero-network stand-in
mirroring `apps/demo-ios/Sources/Networking/MockGateway.swift` — same realm,
client, and PKCE values) or `src/gateway.ts` (the real §6.1 two-hop start
sequence, mirroring `GatewayClient.swift`, toggled by the Config screen's
"Use mock gateway" switch) and hands the result to
`<SecureAuthenticationView>` from `sea-react-native`. All validation,
navigation policy, and WebView hardening live in `SEACore`; the bridge only
marshals props in and events out (§7.4).

Logout (`src/logout.ts`, `src/useSessionLogout.ts`) mirrors
`apps/demo-ios`'s `LogoutRunner`/`SessionTokenStore`, but is simpler than the
iOS version because RN's `fetch` does not share cookies with the WKWebView's
`WKWebsiteDataStore`: the mock path exchanges the captured `code` for an
`id_token` (RFC 7636 worked-example verifier, demo-only) purely to get an
`id_token_hint` for RP-initiated logout against Keycloak directly; the real
gateway path calls `POST /gw/logout`, which automatically carries the
gateway's session cookie since all RN fetches share one jar — no explicit
cookie-jar config needed, unlike iOS's `URLSessionConfiguration` setup.

`ios/demo_rn/demo_rn.entitlements` (associated domains,
`webcredentials:auth.bank.local?mode=developer`) is what makes the
passkey-first CTA appear at all — without it Keycloak's WebAuthn client-side
check fails and the login page falls back to password-only. This app's
bundle ID (`com.bankerise.sea.demorn`) must also be listed in
`infra/nginx/apple-app-site-association`'s `apps` array alongside
`apps/demo-ios`'s — see [infra/README.md](../../infra/README.md#apple-app-site-association-aasa).

## Setup

See [infra/README.md](../../infra/README.md#sea-react-native-bridge--appsdemo-rn-spec-42-44-7)
for the full dev-mode setup (Node/Yarn versions, Podfile wiring, Metro
config). Short version, from the repo root:

```bash
nvm use && yarn install
cd apps/demo-rn/ios && pod install && cd ..
yarn ios
```

Requires the local infra Keycloak stack running
(`docker compose -f ../../infra/docker-compose.yml up -d`) — this app talks
to the same `bankerise-mobile` realm / `sea-dev-public` client as
`apps/demo-ios`, no separate backend needed.

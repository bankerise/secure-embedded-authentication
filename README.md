# Bankerise SEA — Secure Embedded Authentication

[![sea-core-ios](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/sea-core-ios.yml/badge.svg)](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/sea-core-ios.yml)
[![sea-react-native](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/sea-react-native.yml/badge.svg)](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/sea-react-native.yml)
[![npm](https://img.shields.io/npm/v/%40bankerise-platform%2Fsea-react-native)](https://www.npmjs.com/package/@bankerise-platform/sea-react-native)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Native-feeling login for apps that authenticate against Keycloak (or any
OIDC provider), without handing the whole login screen off to a system
browser.

## The problem

The standards-recommended way to do OAuth2/OIDC on mobile is to open the
authorize URL in an external user-agent — `ASWebAuthenticationSession` on
iOS, Chrome Custom Tabs on Android. It's secure and RFC-8252-compliant, but
it's also a visibly non-native experience: browser chrome, an address bar,
a jarring context switch away from your app. For a login screen — the front
door of the app — that seam is exactly where users notice they've left your
product.

**SEA** is a hardened embedded `WKWebView` that gets you the native,
in-app feel back, while keeping the security properties (origin-validated
authorize URLs, in-process callback capture, deny-by-default navigation,
passkey/WebAuthn support) that make the system-browser pattern safe in the
first place. See [bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md)
for the full threat model and design rationale.

## Screenshots

<!-- TODO: replace with real screenshots — embedded login (password),
     passkey-first CTA, and the system-browser fallback for comparison. -->

| Embedded login | Passkey-first | System-browser fallback |
|---|---|---|
| _screenshot placeholder_ | _screenshot placeholder_ | _screenshot placeholder_ |

## Packages

| Package | What it is | Install |
|---|---|---|
| `sea-core-ios` | Swift package — the audited security core | CocoaPods (below) |
| `sea-react-native` | Fabric bridge wrapping `sea-core-ios` (spec §7) | `yarn add @bankerise-platform/sea-react-native` |
| `sea-core-android` | Not started yet — core-first, iOS-first (spec §4.8) | — |

### iOS (CocoaPods)

The `Specs/` index lives in this same repo, so no extra Specs repo is
needed — just add this repo as a Podfile `source` alongside the default
CDN:

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/bankerise/secure-embedded-authentication.git'

pod 'SEACore', '~> 0.0.1'
```

### React Native

```bash
yarn add @bankerise-platform/sea-react-native
```

```tsx
<SecureAuthenticationView
  authorizeUrl={authorizeUrl}
  presentation="sheet"
  appearance={{ headerBackground: '#0B1E3F', accent: '#3D8BFF' }}
  allowedDomains={['auth.example.com']}
  onCaptured={(params) => submitToGateway(params)}
  onCancelled={() => {}}
  onError={(e) => console.error(e.code)}
/>
```

## Layout

```
packages/sea-core-ios/     Swift package — the audited security core
packages/sea-react-native/ Fabric bridge wrapping sea-core-ios (spec §7)
apps/demo-ios/             Native device-lab harness (§23.3)
apps/demo-rn/               Bridge validation harness only (§4.4)
infra/                     Keycloak dev stack + realm export
themes/                    Keycloak theme shipped alongside SEA
docs/                      Spec + API contract
```

`sea-core-android` is not started yet — the build is core-first and
iOS-first per §4.8. `sea-react-native` is implemented and validated against
`sea-core-ios` in dev mode (local CocoaPods `:path`, §4.5), including its
telemetry/purge-web-data module and demo-rn's logout flow; it has no
Android side to bridge to until `sea-core-android` exists.

## Current status — Phase 1, iOS

Implemented:

- §6.2 authorize-URL integrity validation
- §6.3 in-process callback capture (+ POST-redirect backstop)
- §7.3 deny-by-default navigation policy
- §8.2 hardened `WKWebView` configuration
- §10 passkeys/WebAuthn (embedded ceremonies) + §10.4 capability fallback
- §11.3 RP-initiated logout (`demo-ios`, `demo-rn`)
- §17.1 iOS screen-security posture
- §18.1 sheet presentation, native header, native failure states
- §20.1 telemetry event emission with §20.2 redaction
- §4.2/§7 React Native Fabric bridge (`sea-react-native`) + telemetry module

**Not yet implemented.** These are declared seams, not stubs — nothing
silently succeeds in their place:

| Area | Spec | Status |
|---|---|---|
| JS bridge | §14 | Not needed; default is no bridge |
| Broker `EXTERNAL_TAB` | §12.4 | Phase 2 |
| Kill-switch fallback (gateway `authMode`) | §21 | Phase 2 — not yet branched on in either demo app |
| Android core | §4.2 | Not started |
| Android Auth Tab / Custom Tabs runner | §10.4 | Decision recorded, not implemented (needs `sea-core-android`) |

**App Attest (§16) and TLS/certificate pinning (§15) are explicitly out of
SEA's scope**, not a SEA phase-2 item — they are host-app/API Gateway
responsibilities.

This phase covers the §6 handoff perimeter, passkeys, and the RN bridge. A
full security review additionally requires the host app/gateway's
attestation and pinning configuration (§15, §16) and the still-pending
broker/kill-switch items above.

## Getting started

```bash
# 1. Keycloak
docker compose -f infra/docker-compose.yml up -d

# 2. Core tests
cd packages/sea-core-ios
xcodebuild test -scheme SEACore -destination 'platform=iOS Simulator,name=iPhone 17'

# 3. Demo app (native)
cd apps/demo-ios
xcodegen generate
open SEADemo.xcodeproj

# 4. Demo app (React Native bridge) — see infra/README.md for detail
nvm use && yarn install
cd apps/demo-rn/ios && pod install && cd ..
yarn ios
```

See each directory's README for detail.

## Prerequisites

Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), Docker, Node >=22.13 (see `.nvmrc`) + Yarn
classic for `apps/demo-rn`.

## Documentation

- [bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md) — the
  normative spec (threat model, design rationale, full contract).
- [docs/api-contract-ios-v1.md](docs/api-contract-ios-v1.md) — the iOS API
  contract derived from it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the dev setup, monorepo ground
rules, and release process. Security issues: see
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

[MIT](LICENSE).

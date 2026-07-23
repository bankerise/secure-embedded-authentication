# Bankerise SEA — Secure Embedded Authentication

Native authentication using hardened embedded WebViews (the Binance / Revolut
pattern), against a bank-owned Keycloak, orchestrated by the Bankerise API
Gateway as confidential OAuth2 client (BFF).

## Specifications

[bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md) — v1.2, normative.

The iOS API contract derived from it:
[docs/api-contract-ios-v1.md](docs/api-contract-ios-v1.md).

## Layout

```
packages/sea-core-ios/     Swift package — the audited security core
packages/sea-react-native/ Fabric bridge wrapping sea-core-ios (spec §7)
apps/demo-ios/             Native device-lab harness (§23.3)
apps/demo-rn/               Bridge validation harness only (§4.4)
infra/                     Keycloak dev stack + realm export
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

**App Attest (§16) and TLS/certificate pinning (§15) are explicitly out of
SEA's scope**, not a SEA phase-2 item — they are host-app/API Gateway
responsibilities. The Bankerise Mobile SDK already performs app attestation
against the gateway independently of SEA.

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
